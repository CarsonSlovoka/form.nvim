local api = vim.api
local schema = require('form.schema')
local output = require('form.output')
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

--- Open a single-line-per-field form. Call from Normal mode.
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
  local snippet = schema.snippet(definition)
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
  local function write(ev)
    if writing then fail(buf, 'recursive submission is unsupported') end
    local name = api.nvim_buf_get_name(buf)
    local force = vim.v.cmdbang == 1
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local data, errors = schema.validate(definition, lines)
    diagnostics(buf, errors, display)
    if not data then
      fail(buf, ('Validation failed (%d error%s)'):format(#errors, #errors == 1 and '' or 's'))
    end

    writing = true
    local ok, reason = pcall(function()
      -- <afile> preserves the filename spelling; <amatch> is only used as
      -- a fallback. A bare :w targets the virtual buffer name.
      local target = ev.file ~= '' and ev.file or ev.match
      local path = default_path
      if target ~= name and target ~= uri and ev.match ~= name and ev.match ~= uri then
        path = output.path(target)
      end
      local ctx = { bufnr = buf, title = title, path = path, force = force }

      -- A custom submit callback takes full responsibility for persistence.
      -- Without one, use the configured serializer and built-in file writer.
      if definition.on_submit then
        local accepted, message = definition.on_submit(data, ctx)
        if accepted == false then error(message or 'Submission rejected', 0) end
      elseif path then
        local contents = output.serialize(format, data, ctx, lines)
        output.write(path, contents, force)
      end
    end)
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
  -- No snippet completion hooks and no TextChanged validation.
  local ok, err = pcall(function()
    if window == 'split' then vim.cmd.split() end
    if window == 'vsplit' then vim.cmd.vsplit() end
    api.nvim_win_set_buf(0, buf)
    api.nvim_win_set_cursor(0, { 1, 0 })
    vim.snippet.expand(snippet)
    bo.modified = true
  end)
  if not ok then
    pcall(api.nvim_buf_delete, buf, { force = true })
    error(err, 0)
  end
  return buf
end

return M
