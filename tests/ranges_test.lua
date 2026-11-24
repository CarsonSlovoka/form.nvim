-- Run from the archive root: nvim --headless -u NONE -l tests/ranges_test.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local ranges = require('form.ranges')
local passed = 0
local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
end
local function fixture(fn)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].undolevels = -1
  api.nvim_buf_set_lines(buf, 0, -1, false, { 'Title: Hello', 'Description:', 'One', 'Two', 'Author: Admin' })
  vim.bo[buf].undolevels = 1000
  local tracker = ranges.attach(buf, {
    { name = 'title',       start = { 0, 7 }, finish = { 0, 12 } },
    { name = 'description', multiline = true, start = { 2, 0 },  finish = { 3, 3 } },
    { name = 'author',      start = { 4, 8 }, finish = { 4, 13 } },
  })
  local ok, err = pcall(fn, buf, tracker)
  tracker:detach()
  api.nvim_buf_delete(buf, { force = true })
  assert(ok, err)
  passed = passed + 1
end
local function collect(tracker)
  local values, errors = tracker:collect()
  assert(values, vim.inspect(errors))
  return values
end
local function invalid(tracker)
  local values, errors = tracker:refresh()
  eq(nil, values)
  assert(#errors > 0, 'Expected structure errors')
end

fixture(function(_, t)
  eq({ title = 'Hello', description = 'One\nTwo', author = 'Admin' }, collect(t))
end)
fixture(function(buf, t)
  api.nvim_buf_set_text(buf, 3, 3, 3, 3, { '', '  中文', '', 'Author: body text' })
  eq('One\nTwo\n  中文\n\nAuthor: body text', collect(t).description)
  eq('Admin', collect(t).author)
end)
fixture(function(buf, t)
  -- Linewise put / o / set_lines insert at the next label's row, not the
  -- preceding value's end column. Anchoring labels handles either splice.
  api.nvim_buf_set_lines(buf, 4, 4, true, { 'Three', 'Four' })
  eq('One\nTwo\nThree\nFour', collect(t).description)
  api.nvim_buf_set_lines(buf, 5, 6, true, {})
  eq('One\nTwo\nThree', collect(t).description)
  api.nvim_buf_set_lines(buf, 2, 3, true, {})
  eq('Two\nThree', collect(t).description)
end)
fixture(function(buf, t)
  api.nvim_buf_set_text(buf, 2, 0, 3, 3, { '' })
  eq('', collect(t).description)
  api.nvim_buf_set_text(buf, 2, 0, 2, 0, { 'First', 'Second', '' })
  eq('First\nSecond\n', collect(t).description)
end)
fixture(function(buf, t)
  api.nvim_buf_set_text(buf, 0, 7, 0, 7, { '中' })
  eq('中Hello', collect(t).title)
  api.nvim_buf_set_text(buf, 0, 15, 0, 15, { '文' })
  eq('中Hello文', collect(t).title)
end)
fixture(function(buf, t)
  api.nvim_buf_set_text(buf, 0, 12, 0, 12, { '', 'Oops' })
  invalid(t)
end)
fixture(function(buf, t)
  api.nvim_buf_set_text(buf, 1, 0, 1, 11, { 'Changed' })
  invalid(t)
end)
fixture(function(buf, t)
  api.nvim_buf_set_text(buf, 3, 1, 4, 10, { '' })
  invalid(t)
end)
fixture(function(buf, t)
  api.nvim_buf_set_lines(buf, 1, 2, true, {})
  invalid(t)
  vim.cmd('undo')
  eq('One\nTwo', collect(t).description)
  vim.cmd('redo')
  invalid(t)
end)
fixture(function(buf, t)
  t:watch()
  api.nvim_buf_set_text(buf, 1, 0, 1, 1, { 'X' })
  api.nvim_exec_autocmds('TextChanged', { buffer = buf })
  assert(#vim.diagnostic.get(buf) > 0)
end)
fixture(function(buf, t)
  -- Clearing a separate namespace, including by a snippet engine, cannot remove form marks.
  local other = api.nvim_create_namespace('form-test.other')
  api.nvim_buf_set_extmark(buf, other, 2, 0, { end_row = 3, end_col = 3 })
  api.nvim_buf_clear_namespace(buf, other, 0, -1)
  eq('One\nTwo', collect(t).description)
end)
-- Integration smoke test with the real public snippet API.
do
  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_current_buf(buf)
  vim.snippet.expand('Title: ${1:Hello}\nDescription:\n${2:One\nTwo}\nAuthor: ${3:Admin}$0')
  local t = ranges.attach(buf, {
    { name = 'title',       start = { 0, 7 }, finish = { 0, 12 } },
    { name = 'description', multiline = true, start = { 2, 0 },  finish = { 3, 3 } },
    { name = 'author',      start = { 4, 8 }, finish = { 4, 13 } },
  })
  eq('One\nTwo', collect(t).description)
  vim.snippet.stop()
  eq('One\nTwo', collect(t).description)
  t:detach()
  api.nvim_buf_delete(buf, { force = true })
  passed = passed + 1
end
print(('PASS: %d range tests'):format(passed))
