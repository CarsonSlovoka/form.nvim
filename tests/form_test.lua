vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local form = require('form')
local submitted, validations = 0, 0
local reject = false
local last_ctx
local function open()
  local b = form.open({
    title = 'test', window = 'split', notify = false,
    fields = {
      { name = 'longitude', type = 'number', min = -180, max = 180, required = true,
        validate = function() validations = validations + 1; return true end },
      { name = 'description', required = true, default = 'example' },
    },
    on_submit = function(data, ctx)
      if reject then return false, 'backend refused' end
      assert(type(data.longitude) == 'number')
      last_ctx = ctx
      submitted = submitted + 1
    end,
  })
  assert(vim.bo[b].buftype == 'acwrite')
  assert(api.nvim_buf_get_lines(b, 0, -1, false)[2] == 'description: example')
  return b
end
local function set(b, lines)
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
end
local function write(command)
  return pcall(vim.cmd, command or 'write')
end
local buf = open()
assert(validations == 0 and submitted == 0)
-- Stop input navigation in the test; the plugin does not stop or hook the snippet.
vim.snippet.stop()
vim.cmd.stopinsert()
set(buf, { 'longitude: 200', 'description: ' })
assert(validations == 0 and #vim.diagnostic.get(buf) == 0)
assert(not write())
assert(vim.bo[buf].modified and submitted == 0 and #vim.diagnostic.get(buf) == 2)
assert(not write('write!'))
assert(not write('wq'))
assert(api.nvim_get_current_buf() == buf and vim.bo[buf].modified)
set(buf, { 'longitude: 121.5', 'description: 台北' })
reject = true
assert(not write())
assert(vim.bo[buf].modified and submitted == 0 and #vim.diagnostic.get(buf) == 1)
reject = false
assert(write())
assert(not vim.bo[buf].modified and submitted == 1 and #vim.diagnostic.get(buf) == 0)
assert(last_ctx.path == nil and last_ctx.force == false and last_ctx.bufnr == buf)
set(buf, { 'longitude: 0', 'description: valid' })
local target = vim.fn.tempname()
assert(write('write ' .. vim.fn.fnameescape(target)))
assert(vim.fn.filereadable(target) == 0 and submitted == 2) -- callback owns persistence
assert(last_ctx.path == target and last_ctx.force == false)
assert(write('write! ' .. vim.fn.fnameescape(target)))
assert(last_ctx.path == target and last_ctx.force == true and submitted == 3)
assert(not write('1write'))
assert(write('wq'))
assert(submitted == 4 and api.nvim_get_current_buf() ~= buf)
print('form integration tests passed')
