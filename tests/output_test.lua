-- Run with Neovim; exercise the actual filesystem and Ex write events.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local uv = vim.uv
local form = require('form')
local dir = assert(uv.fs_mkdtemp(vim.fn.tempname() .. '-XXXXXX'))
dir = assert(uv.fs_realpath(dir))
local cwd = vim.fn.getcwd()
local function path(name) return vim.fs.joinpath(dir, name) end
local function read(name) return vim.fn.readfile(path(name)) end
local function exists(name) return uv.fs_lstat(path(name)) ~= nil end
local function command(cmd) return pcall(vim.cmd, cmd) end
local function expect_write(cmd)
  local ok, err = command(cmd)
  assert(ok, tostring(err))
end
local function expect_failure(buf, cmd)
  local ok = command(cmd)
  assert(not ok, 'Expected failure: ' .. cmd)
  assert(vim.bo[buf].modified, 'Failed write must remain modified')
end
local function open(opts)
  opts = vim.tbl_extend('force', {
    title = 'output-test', window = 'split', notify = false,
    fields = {
      { name = 'x', type = 'number', required = true, min = 0, default = 5 },
      { name = 'note', required = true, default = '台北' },
    },
  }, opts or {})
  local b = form.open(opts)
  vim.snippet.stop()
  vim.cmd.stopinsert()
  return b
end
local function set(b, x, note)
  api.nvim_buf_set_lines(b, 0, -1, false, { 'x: ' .. x, 'note: ' .. note })
end
local function close(b) api.nvim_buf_delete(b, { force = true }) end

local ok, err = xpcall(function()
  vim.cmd.cd(vim.fn.fnameescape(dir))
  local b = open()
  local name = api.nvim_buf_get_name(b)
  set(b, -1, '')
  expect_failure(b, 'w invalid.txt')
  expect_failure(b, 'w! invalid.txt')
  expect_failure(b, 'wq invalid.txt')
  assert(not exists('invalid.txt') and api.nvim_get_current_buf() == b)
  assert(#vim.diagnostic.get(b) == 2)
  set(b, 5, '台北')
  expect_write('w raw\\ file.txt')
  assert(vim.deep_equal(read('raw file.txt'), { 'x: 5', 'note: 台北' }))
  assert(not vim.bo[b].modified and api.nvim_buf_get_name(b) == name)
  assert(#vim.diagnostic.get(b) == 0)
  set(b, 7, 'changed')
  expect_failure(b, 'w raw\\ file.txt')
  assert(read('raw file.txt')[1] == 'x: 5')
  set(b, -1, 'invalid')
  expect_failure(b, 'w! raw\\ file.txt')
  assert(read('raw file.txt')[1] == 'x: 5')
  set(b, 7, 'changed')
  expect_write('w! raw\\ file.txt')
  assert(read('raw file.txt')[1] == 'x: 7')
  expect_failure(b, '1w partial.txt')
  expect_failure(b, 'w >> append.txt')
  expect_failure(b, 'w missing/sub.txt')
  assert(not exists('partial.txt') and not exists('append.txt') and not exists('missing'))
  assert(uv.fs_mkdir(path('directory'), 448))
  expect_failure(b, 'w! directory')
  -- No path: validate only; do not remember the last explicit export.
  expect_write('w')
  assert(not vim.bo[b].modified and api.nvim_buf_get_name(b) == name)
  expect_write('wq closed.txt')
  assert(exists('closed.txt') and api.nvim_get_current_buf() ~= b)
  close(b)

  -- JSON, default destination, explicit override, and paths with spaces.
  b = open({ format = 'json', path = 'default.json' })
  expect_write('w alternate.json')
  assert(exists('alternate.json') and not exists('default.json'))
  expect_write('w')
  local data = vim.json.decode(table.concat(read('default.json'), '\n'))
  assert(data.x == 5 and data.note == '台北')
  set(b, 9, 'again')
  expect_failure(b, 'w')
  expect_write('w!')
  assert(vim.json.decode(read('default.json')[1]).x == 9)
  close(b)

  local context
  b = open({ format = function(data, ctx)
    context = ctx
    return { ('X=%d'):format(data.x), 'note=' .. data.note }
  end })
  expect_write('w custom.txt')
  assert(context.path == path('custom.txt') and not context.force)
  assert(vim.deep_equal(read('custom.txt'), { 'X=5', 'note=台北' }))
  close(b)

  b = open({ format = function() return 'single string' end })
  expect_write('w string.txt')
  assert(vim.deep_equal(read('string.txt'), { 'single string' }))
  close(b)

  b = open({ format = function() error('serializer failed') end })
  expect_failure(b, 'w broken.txt')
  expect_failure(b, 'w! custom.txt')
  assert(not exists('broken.txt') and read('custom.txt')[1] == 'X=5')
  close(b)

  b = open({ format = function() return { 'ok', 12 } end })
  expect_failure(b, 'w badformat.txt')
  assert(not exists('badformat.txt'))
  close(b)

  -- Custom callback supersedes the built-in writer and receives the destination.
  b = open({ path = 'callback-default.txt', format = function() error('must not run') end,
    on_submit = function(data, ctx)
      assert(data.x == 5 and ctx.bufnr == api.nvim_get_current_buf())
      context = ctx
    end,
  })
  expect_write('w')
  assert(context.path == path('callback-default.txt') and not exists('callback-default.txt'))
  expect_write('w! callback.txt')
  assert(context.path == path('callback.txt') and context.force and not exists('callback.txt'))
  close(b)

  -- A symlink must not cause the built-in writer to overwrite its target.
  if uv.fs_symlink(path('raw file.txt'), path('link.txt')) then
    b = open()
    expect_failure(b, 'w link.txt')
    expect_failure(b, 'w! link.txt')
    assert(uv.fs_lstat(path('link.txt')).type == 'link' and read('raw file.txt')[1] == 'x: 7')
    close(b)
  end

  -- Shell-style tilde expansion happens in Ex, not the serializer.
  if vim.fn.has('unix') == 1 then
    b = open({ on_submit = function(_, ctx) context = ctx end })
    expect_write('w ~/form.nvim-test-output.txt')
    assert(context.path == vim.fn.fnamemodify('~/form.nvim-test-output.txt', ':p'))
    close(b)
  end

  b = open({ format = 'json', fields = { { name = 'optional' } } })
  expect_write('w empty.json')
  assert(read('empty.json')[1] == '{}')
  close(b)

  assert(not pcall(form.open, { fields = { { name = 'x' } }, format = 'xml' }))
  assert(not pcall(form.open, { fields = { { name = 'x' } }, path = '' }))
  assert(#vim.fn.glob(path('.form.nvim-*'), false, true) == 0, 'Temporary file leaked')
end, debug.traceback)
vim.cmd.cd(vim.fn.fnameescape(cwd))
vim.fn.delete(dir, 'rf')
assert(ok, err)
print('output integration tests passed')
