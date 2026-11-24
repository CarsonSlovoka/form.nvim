package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path
local output = require('form.output')
local ctx = { path = '/tmp/data', force = true }
assert(output.check_format(nil) == 'raw')
assert(output.check_format('json') == 'json')
assert(not pcall(output.check_format, 'xml'))
assert(not pcall(output.check_format, false))
assert(output.serialize('raw', {}, ctx, { 'x: 5', 'note: 台北' }) == 'x: 5\nnote: 台北\n')
assert(output.serialize(function(data, context)
  assert(context == ctx and data.x == 5)
  return { 'x=5', 'note=台北' }
end, { x = 5 }, ctx, {}) == 'x=5\nnote=台北\n')
assert(output.serialize(function() return 'a\nb' end, {}, ctx, {}) == 'a\nb\n')
assert(output.serialize(function() return 'a\n' end, {}, ctx, {}) == 'a\n')
assert(output.serialize(function() return {} end, {}, ctx, {}) == '')
for _, value in ipairs({ 12, true, { foo = 'bar' }, { 'ok', 12 }, { 'a\nb' }, { [1] = 'a', [3] = 'b' } }) do
  assert(not pcall(output.serialize, function() return value end, {}, ctx, {}))
end
assert(not pcall(output.serialize, function() error('boom') end, {}, ctx, {}))
print('serialization tests passed')
