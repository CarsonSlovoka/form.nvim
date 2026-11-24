-- Pure Lua writer tests with a simulated synchronous libuv filesystem.
-- tests/output_test.lua exercises the same behavior against actual Neovim/libuv.
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path
local output = require('form.output')
local files, handles, serial, fault = {}, {}, 0, nil
local function entry(text, kind)
  return { type = kind or 'file', mode = 420, contents = text }
end
local function reset()
  files, handles, serial, fault = {}, {}, 0, nil
end
local uv = {}
function uv.fs_lstat(path)
  if files[path] then return files[path] end
  return nil, 'no such file', 'ENOENT'
end

function uv.fs_mkstemp(template)
  if fault == 'mkstemp' then return nil, 'cannot create temp' end
  serial = serial + 1
  local tmp = template .. serial
  local e = entry('')
  files[tmp], handles[serial] = e, e
  return serial, tmp
end

function uv.fs_write(fd, bytes, offset)
  if fault == 'write' then return nil, 'disk full' end
  local e = assert(handles[fd])
  assert(offset == #e.contents)
  -- Always simulate short writes to exercise the retry loop.
  local n = math.min(#bytes, 2)
  e.contents = e.contents .. bytes:sub(1, n)
  return n
end

function uv.fs_fchmod(fd, mode)
  handles[fd].mode = mode; return true
end

function uv.fs_fsync()
  if fault == 'sync' then return nil, 'sync failed' end; return true
end

function uv.fs_close(fd)
  handles[fd] = nil; return true
end

function uv.fs_link(src, dst)
  if fault == 'race' then files[dst] = entry('competitor') end
  if files[dst] then return nil, 'already exists', 'EEXIST' end
  if fault == 'link' then return nil, 'not supported' end
  files[dst] = assert(files[src]); return true
end

function uv.fs_rename(src, dst)
  if fault == 'rename' then return nil, 'rename failed' end
  files[dst], files[src] = assert(files[src]), nil; return true
end

function uv.fs_unlink(path)
  files[path] = nil; return true
end

vim = vim or {}
local original_uv, original_fs, original_notify, original_log = vim.uv, vim.fs, vim.notify, vim.log
vim.uv = uv
vim.fs = { dirname = function() return '/dir' end, joinpath = function(a, b) return a .. '/' .. b end }
vim.notify = function() error('unexpected cleanup warning') end
vim.log = { levels = { WARN = 2 } }
local target = '/dir/output.txt'
local function clean()
  assert(next(handles) == nil, 'Handle leaked')
  for path in pairs(files) do assert(not path:find('.form.nvim-', 1, true), 'Temp file leaked') end
end
local function write(force)
  return pcall(output.write, target, 'new content\n', force)
end
local success, err = pcall(function()
  reset()
  assert(write(false))
  assert(files[target].contents == 'new content\n')
  clean()
  files[target] = entry('old')
  assert(not write(false) and files[target].contents == 'old')
  files[target].mode = 384
  assert(write(true) and files[target].contents == 'new content\n' and files[target].mode == 384)
  clean()
  for _, kind in ipairs({ 'link', 'directory', 'fifo' }) do
    files[target] = entry('old', kind)
    assert(not write(true) and files[target].contents == 'old')
    clean()
  end
  for _, mode in ipairs({ 'mkstemp', 'write', 'sync', 'link', 'race' }) do
    reset(); fault = mode
    assert(not write(false))
    if mode == 'race' then assert(files[target].contents == 'competitor') else assert(not files[target]) end
    clean()
  end
  for _, mode in ipairs({ 'mkstemp', 'write', 'sync', 'rename' }) do
    reset(); files[target] = entry('old'); fault = mode
    assert(not write(true) and files[target].contents == 'old')
    clean()
  end
end)
vim.uv, vim.fs, vim.notify, vim.log = original_uv, original_fs, original_notify, original_log
assert(success, err)
print('writer unit tests passed (simulated filesystem)')
