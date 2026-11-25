local api = vim.api
local schema = require('form.schema')
local output = require('form.output')
local ranges = require('form.ranges')
local M = {}
local ns = api.nvim_create_namespace('form.nvim')

local function fail(buf, message)
  -- Keep the pending form dirty and raise an actual write error, not just a notification.
  vim.bo[buf].modified = true
  error('form.nvim: ' .. message, 0)
end

local function diagnostics(buf, errors, opts)
  local items = {}
  for i, err in ipairs(errors) do
    items[i] = {
      lnum = err.row,
      col = err.col,
      end_col = err.last,
      severity = vim.diagnostic.severity.ERROR,
      source = 'form.nvim',
      code = err.name,
      message = err.message,
    }
  end
  vim.diagnostic.set(ns, buf, items, opts)
end

local function set_mappings(buf)
  for _, m in ipairs({ { '<Tab>', 1 }, { '<S-Tab>', -1 } }) do
    local key, direction = m[1], m[2]
    vim.keymap.set({ 'i', 's' }, key, function()
      if vim.snippet.active({ direction = direction }) then
        return ('<Cmd>lua vim.snippet.jump(%d)<CR>'):format(direction)
      end
      return key
    end, { buffer = buf, expr = true, silent = true, desc = 'Form snippet navigation' })
  end
end

--- Open a schema-driven form. Call from Normal mode.
--- @param spec table
--- @return integer bufnr
function M.open(spec)
  local definition = schema.compile(spec)
  local format = output.check_format(spec.format)
  local default_path = spec.path ~= nil and output.path(spec.path) or nil
  local title = spec.title or 'form'
  assert(type(title) == 'string' and title ~= '', 'form.nvim: title must be a non-empty string')
  local window = spec.window or 'split'
  assert(window == 'split' or window == 'vsplit' or window == 'current', 'form.nvim: invalid window')
  assert(spec.diagnostic == nil or type(spec.diagnostic) == 'table', 'form.nvim: diagnostic must be a table')
  assert(vim.snippet and vim.snippet.expand, 'form.nvim: native vim.snippet is required')
  local snippet, expected, spans = schema.render(definition)
  local display = vim.tbl_extend('force', {
    virtual_text = true, underline = true, signs = true, update_in_insert = false,
  }, spec.diagnostic or {})
  local buf = api.nvim_create_buf(true, false)
  local uri = ('form://%d/%s'):format(buf, title:gsub('[^%w_.%-]', '-'))
  api.nvim_buf_set_name(buf, uri)
  local bo = vim.bo[buf]
  bo.buftype = 'acwrite'
  bo.bufhidden = 'hide'
  bo.swapfile = false
  bo.undofile = false
  bo.modeline = false
  bo.filetype = 'form'
  local writing = false
  local tracker
  local function write(ev)
    if writing then fail(buf, 'recursive submission is unsupported') end
    local name = api.nvim_buf_get_name(buf)
    local force = vim.v.cmdbang == 1
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local data, errors
    if tracker then
      local values, structure_errors, positions = tracker:refresh()
      if not values then
        vim.diagnostic.reset(ns, buf)
        fail(buf, ('Invalid form structure (%d error%s); use undo to restore labels and separators')
          :format(#structure_errors, #structure_errors == 1 and '' or 's'))
      end
      data, errors = schema.validate_ranges(definition, lines, values, positions)
    else
      data, errors = schema.validate(definition, lines)
    end
    diagnostics(buf, errors, display)
    if not data then
      fail(buf, ('Validation failed (%d error%s)'):format(#errors, #errors == 1 and '' or 's'))
    end

    writing = true
    local finish_context
    local ok, reason = pcall(function()
      -- <afile> preserves the filename spelling; <amatch> is only used as
      -- a fallback. A bare :w targets the virtual buffer name.
      local target = ev.file ~= '' and ev.file or ev.match
      local path = default_path
      if target ~= name and target ~= uri and ev.match ~= name and ev.match ~= uri then
        path = output.path(target)
      end
      local ctx = { bufnr = buf, title = title, path = path, force = force }

      finish_context = output.attach_context(ctx, format, data, lines)

      -- Custom callbacks opt in to serialization and persistence via ctx.
      -- Without one, use the same helpers when a destination is available.
      if definition.on_submit then
        local accepted, message = definition.on_submit(data, ctx)
        if accepted == false then error(message or 'Submission rejected', 0) end
      elseif path then
        ctx.write()
      end
    end)
    if finish_context then finish_context() end
    writing = false
    if not ok then
      local text = 'Submission failed: ' .. tostring(reason)
      diagnostics(buf, { { name = '_form', row = 0, col = 0, last = #lines[1], message = text } }, display)
      fail(buf, text)
    end
    vim.diagnostic.reset(ns, buf)
    bo.modified = false
    if spec.notify ~= false then vim.notify('form.nvim: Submitted successfully', vim.log.levels.INFO) end
  end
  api.nvim_create_autocmd('BufWriteCmd', { buffer = buf, callback = write, desc = 'Validate and submit form' })
  api.nvim_create_autocmd({ 'FileWriteCmd', 'FileAppendCmd' }, {
    buffer = buf,
    callback = function() fail(buf, 'partial writes and append are unsupported; use :w') end,
    desc = 'Reject unsupported form writes',
  })
  if spec.mappings ~= false then set_mappings(buf) end
  -- Native snippet navigation; only mixed/multiline forms watch structure.
  -- User validators and submission callbacks still run exclusively on write.
  local ok, err = pcall(function()
    if window == 'split' then vim.cmd.split() end
    if window == 'vsplit' then vim.cmd.vsplit() end
    api.nvim_win_set_buf(0, buf)
    api.nvim_win_set_cursor(0, { 1, 0 })
    if definition.has_multiline then
      -- Snippet expansion normally converts literal tabs when expandtab is on.
      -- Preserve the schema's exact default bytes and the computed coordinates.
      -- The initial layout is a baseline, not an undoable user edit.
      local expandtab, undolevels = bo.expandtab, bo.undolevels
      bo.expandtab, bo.undolevels = false, -1
      local expanded, reason = pcall(vim.snippet.expand, snippet)
      bo.expandtab, bo.undolevels = expandtab, undolevels
      if not expanded then error(reason, 0) end
      assert(vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), expected),
        'form.nvim: native snippet expansion did not match the form layout')
      tracker = ranges.attach(buf, spans)
      tracker:watch(display)
    else
      vim.snippet.expand(snippet)
    end
    bo.modified = true
  end)
  if not ok then
    if api.nvim_get_current_buf() == buf and vim.snippet.active() then vim.snippet.stop() end
    pcall(api.nvim_buf_delete, buf, { force = true })
    error(err, 0)
  end
  return buf
end

return M
