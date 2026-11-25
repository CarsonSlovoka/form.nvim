-- Real native snippet / acwrite integration, independent of range-only tests.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local form = require('form')
local submitted, validated, received, context = 0, 0
local function open(opts)
  local spec = vim.tbl_extend('force', {
    title = 'multiline', window = 'split', notify = false,
    fields = {
      { name = 'title', default = 'Hello', required = true },
      { name = 'description', label = '描述', multiline = true, required = true,
        default = 'One\n\tTwo', validate = function(value)
          validated = validated + 1
          return not value:find('INVALID', 1, true), 'Invalid description'
        end },
      { name = 'author', required = true, default = 'Admin' },
    },
    on_submit = function(data, ctx)
      submitted = submitted + 1
      received, context = data, ctx
    end,
  }, opts or {})
  if spec.on_submit == false then spec.on_submit = nil end
  local buf = form.open(spec)
  assert(vim.snippet.active(), 'Native snippet should remain active on open')
  assert(vim.snippet.active({ direction = 1 }), 'Native snippet should support forward navigation')
  return buf
end
local function stop()
  vim.snippet.stop()
  vim.cmd.stopinsert()
  api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
end
local function eq(a, b) assert(vim.deep_equal(a, b), vim.inspect({ expected = a, actual = b })) end
local function write(cmd)
  local ok, err = pcall(vim.cmd, cmd or 'write')
  assert(ok, tostring(err))
end
local function invalid(buf, cmd)
  local before = submitted
  assert(not pcall(vim.cmd, cmd or 'write'), 'Write should fail')
  assert(vim.bo[buf].modified and submitted == before and #vim.diagnostic.get(buf) > 0)
end
local function edit(buf, sr, sc, er, ec, lines)
  api.nvim_buf_set_text(buf, sr, sc, er, ec, lines)
end
local function refresh(buf)
  api.nvim_exec_autocmds('TextChanged', { buffer = buf })
end

vim.o.expandtab = true
local buf = open()
eq({ 'title: Hello', '描述:', 'One', '\tTwo', 'author: Admin' }, api.nvim_buf_get_lines(buf, 0, -1, false))
assert(vim.bo[buf].expandtab, 'expandtab must be restored after expansion')
assert(validated == 0 and submitted == 0)
stop()
edit(buf, 3, 4, 3, 4, { '', '', 'author: body text', '  中文  ', '' })
refresh(buf)
assert(validated == 0 and #vim.diagnostic.get(buf) == 0)
local target = vim.fn.tempname()
write('w ' .. vim.fn.fnameescape(target))
eq('One\n\tTwo\n\nauthor: body text\n  中文  \n', received.description)
eq('Admin', received.author)
assert(context.path == target and submitted == 1 and validated == 1)
assert(vim.fn.filereadable(target) == 0 and not vim.bo[buf].modified)
-- A damaged label blocks submission before user validators, even with :w!.
edit(buf, 1, 0, 1, #'描述:', { 'Changed:' })
refresh(buf)
assert(#vim.diagnostic.get(buf) > 0 and validated == 1)
invalid(buf, 'w! ' .. vim.fn.fnameescape(target))
assert(validated == 1 and vim.fn.filereadable(target) == 0)
api.nvim_buf_delete(buf, { force = true })

-- Empty and whitespace-only values, and the actual shifted diagnostic row.
buf = open()
stop()
edit(buf, 2, 0, 3, 4, { '' })
refresh(buf)
assert(#vim.diagnostic.get(buf) == 0, 'Clearing a value is structurally valid')
invalid(buf)
assert(vim.diagnostic.get(buf)[1].lnum == 2)
edit(buf, 2, 0, 2, 0, { 'First', 'Second', 'Third' })
edit(buf, 5, #'author: ', 5, #'author: Admin', { '' })
invalid(buf)
local ds = vim.diagnostic.get(buf)
assert(#ds == 1 and ds[1].code == 'author' and ds[1].lnum == 5)
edit(buf, 5, #'author: ', 5, #'author: ', { 'New' })
write()
eq('First\nSecond\nThird', received.description)
eq('New', received.author)
assert(#vim.diagnostic.get(buf) == 0)
api.nvim_buf_delete(buf, { force = true })

-- The initial snippet is the baseline. Undo must restore a deleted anchor,
-- even after the snippet has stopped; redo must invalidate it again.
buf = open()
stop()
api.nvim_buf_set_lines(buf, 1, 2, true, {})
refresh(buf)
invalid(buf)
vim.cmd.undo()
refresh(buf)
assert(#vim.diagnostic.get(buf) == 0)
write()
eq('One\n\tTwo', received.description)
vim.cmd.redo()
refresh(buf)
invalid(buf)
api.nvim_buf_delete(buf, { force = true })

-- Optional first/last multiline fields, JSON and raw serialization.
local paths = { vim.fn.tempname(), vim.fn.tempname() }
local ok, err = xpcall(function()
  for i, format in ipairs({ 'json', 'raw' }) do
    buf = open({ format = format, on_submit = false, fields = {
      { name = 'first', multiline = true },
      { name = 'middle', type = 'integer', default = 7 },
      { name = 'last', multiline = true, default = '\n  x\n\n' },
    } })
    stop()
    write('w ' .. vim.fn.fnameescape(paths[i]))
    local file = vim.fn.readfile(paths[i])
    if format == 'json' then
      eq({ middle = 7, last = '\n  x\n\n' }, vim.json.decode(table.concat(file, '\n')))
    else
      eq({ 'first:', '', 'middle: 7', 'last:', '', '  x', '', '' }, file)
    end
    api.nvim_buf_delete(buf, { force = true })
  end
end, debug.traceback)
for _, p in ipairs(paths) do vim.fn.delete(p) end
assert(ok, err)
-- Custom submission may use formatted multiline content after snippet stops.
local destination = vim.fn.tempname()
local serialized, format_calls
local success, reason = xpcall(function()
  format_calls = 0
  buf = open({ format = function(data)
    format_calls = format_calls + 1
    return data.description
  end, on_submit = function(_, ctx)
    assert(ctx.write())
    serialized = ctx.serialize()
  end })
  stop()
  write('w ' .. vim.fn.fnameescape(destination))
  eq('One\n\tTwo\n', serialized)
  eq({ 'One', '\tTwo' }, vim.fn.readfile(destination))
  assert(format_calls == 1)
  api.nvim_buf_delete(buf, { force = true })
end, debug.traceback)
vim.fn.delete(destination)
assert(success, reason)
print('multiline integration tests passed')
