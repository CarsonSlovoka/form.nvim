-- Pure Lua tests for submission-scoped helpers; no Neovim required.
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path
local output = require('form.output')
local original_write = output.write
local writes = {}
output.write = function(path, contents, force)
  writes[#writes + 1] = { path, contents, force }
end
local calls = 0
local data = { note = 'a\nb' }
local lines = { 'note:', 'a', 'b' }
local function format(value, ctx)
  calls = calls + 1
  assert(value == data and ctx.title == 'test')
  return value.note
end
local function context(path, force, serializer)
  local ctx = { title = 'test', bufnr = 1, path = path, force = force }
  local finish = output.attach_context(ctx, serializer or format, data, lines)
  return ctx, finish
end
local ok, err = pcall(function()
  local ctx, finish = context('/tmp/a', false)
  assert(calls == 0 and #writes == 0)
  assert(ctx.serialize() == 'a\nb\n' and calls == 1 and #writes == 0)
  assert(ctx.serialize() == 'a\nb\n' and calls == 1)
  -- The original command's resolved destination and overwrite flag are fixed.
  ctx.path, ctx.force = '/tmp/other', true
  assert(ctx.write() == true and calls == 1 and #writes == 1)
  assert(writes[1][1] == '/tmp/a' and writes[1][2] == 'a\nb\n' and writes[1][3] == false)
  assert(ctx.write() and #writes == 2 and calls == 1)
  finish()
  assert(not pcall(ctx.serialize) and not pcall(ctx.write))

  ctx, finish = context('/tmp/b', true)
  data.note = 'new'
  assert(ctx.write() and calls == 2)
  assert(ctx.serialize() == 'new\n' and calls == 2)
  assert(writes[3][1] == '/tmp/b' and writes[3][2] == 'new\n' and writes[3][3] == true)
  finish()

  ctx, finish = context(nil, false)
  assert(not pcall(ctx.write) and calls == 2 and #writes == 3)
  assert(ctx.serialize() == 'new\n' and calls == 3 and #writes == 3)
  finish()

  local attempts = 0
  ctx, finish = context('/tmp/c', false, function()
    attempts = attempts + 1
    if attempts == 1 then error('serializer failed') end
    return {}
  end)
  local success, message = pcall(ctx.write)
  assert(not success and tostring(message):find('serializer failed', 1, true) and #writes == 3)
  assert(ctx.serialize() == '' and attempts == 2)
  assert(ctx.write() and attempts == 2 and writes[4][2] == '')
  finish()

  ctx, finish = context('/tmp/d', false, function(_, c) return c.serialize() end)
  success, message = pcall(ctx.serialize)
  assert(not success and tostring(message):find('Recursive serialization', 1, true))
  finish()
  ctx, finish = context('/tmp/d', false, function(_, c) return c.write() end)
  success, message = pcall(ctx.write)
  assert(not success and tostring(message):find('Recursive serialization', 1, true) and #writes == 4)
  finish()

  -- Writer errors propagate without losing a successfully serialized value.
  ctx, finish = context('/tmp/e', false, 'raw')
  output.write = function() error('disk full') end
  success, message = pcall(ctx.write)
  assert(not success and tostring(message):find('disk full', 1, true))
  assert(ctx.serialize() == 'note:\na\nb\n')
  finish()
end)
output.write = original_write
assert(ok, err)
print('submission context tests passed')
