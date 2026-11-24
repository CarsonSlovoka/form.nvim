local api = vim.api
local schema = require('form.schema')
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
    local name = api.nvim_buf_get_name(buf)
    -- A form is not a disk file. Reject explicit alternate destinations.
    if ev.match ~= name and ev.file ~= name and ev.match ~= uri and ev.file ~= uri then
      fail(buf, 'write the form with :w (alternate filenames are unsupported)')
    end
    if writing then fail(buf, 'recursive submission is unsupported') end
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local data, errors = schema.validate(definition, lines)
    diagnostics(buf, errors, display)
    if not data then
      fail(buf, ('Validation failed (%d error%s)'):format(#errors, #errors == 1 and '' or 's'))
    end
    -- Synchronous callback: returning false or throwing means write failure.
    if definition.on_submit then
      writing = true
      local ok, accepted, message = pcall(definition.on_submit, data, { bufnr = buf, title = title })
      writing = false
      if not ok or accepted == false then
        local reason = not ok and accepted or (message or 'Submission rejected')
        local text = 'Submission failed: ' .. tostring(reason)
        diagnostics(buf, { { name = '_form', row = 0, col = 0, last = #lines[1], message = text } }, display)
        fail(buf, text)
      end
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
