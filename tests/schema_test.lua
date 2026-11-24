package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path
local schema = require('form.schema')
local calls = 0
local s = schema.compile({
  fields = {
    { name = 'longitude', label = '經度', type = 'number', min = -180, max = 180, required = true },
    { name = 'latitude', label = '緯度', type = 'number', min = -90, max = 90, required = true },
    {
      name = 'description',
      label = '描述',
      required = true,
      validate = function(v)
        calls = calls + 1; return #v >= 3, 'Too short'
      end
    },
    { name = 'enabled', type = 'boolean', default = false },
    { name = 'count',   type = 'integer' },
  },
  validate = function(data)
    if data.longitude == 0 and data.latitude == 0 then return { longitude = 'Choose a location' } end
  end,
})
local function validate(...)
  return schema.validate(s, { ... })
end
local data, errors = validate('經度: 121.5', '緯度: 25', '描述: 台北: 車站', 'enabled: false', 'count: ')
assert(data and data.longitude == 121.5 and data.latitude == 25 and data.enabled == false)
assert(data.description == '台北: 車站' and data.count == nil and #errors == 0)
data, errors = validate('經度: 181', '緯度: -91', '描述: ', 'enabled: maybe', 'count: 1.2')
assert(not data and #errors == 5)
assert(errors[1].col == #'經度: ' and errors[1].row == 0)
data, errors = validate('經度: 0', '緯度: 0', '描述: abc', 'enabled: true', 'count: 2')
assert(not data and #errors == 1 and errors[1].name == 'longitude')
data, errors = validate('經度: nan', '緯度: 1e999', '描述: a', 'enabled: false', 'count: 0')
assert(not data and #errors == 3)
data, errors = validate('經度: 180', '緯度: -90', '描述: abc', 'enabled: ', 'count: 0', 'extra')
assert(not data and #errors == 1 and errors[1].name == '_form')
data, errors = validate('wrong: 1')
assert(not data and #errors == 5)
assert(calls == 4)
assert(schema.snippet(s):find('${4:false}', 1, true))
local escaped = schema.compile({ fields = { { name = 'x', label = 'a$}', default = 'x\\$}' } } })
assert(schema.snippet(escaped) == [[a\$\}: ${1:x\\\$\}}$0]])
assert(not pcall(schema.compile, { fields = { { name = 'x', min = 1 } } }))
assert(not pcall(schema.compile, { fields = { { name = 'x' }, { name = 'x' } } }))
print('schema tests passed')

-- Exact rendered coordinates and whitespace semantics for mixed forms.
local multi = schema.compile({
  fields = {
    { name = 'x', label = '經度', type = 'number', default = 5 },
    {
      name = 'note',
      label = '描述',
      multiline = true,
      required = true,
      default = '\tfirst\n\n  second $}\\\n'
    },
    { name = 'empty', multiline = true },
    { name = 'enabled', type = 'boolean', default = false },
  }
})
local snippet, lines, spans = schema.render(multi)
assert(multi.has_multiline and not multi.fields[1].multiline)
assert(table.concat(lines, '\n') == '經度: 5\n描述:\n\tfirst\n\n  second $}\\\n\nempty:\n\nenabled: false')
assert(snippet:find('描述:\n${2:', 1, true))
assert(spans[1].start[2] == #'經度: ' and spans[1].finish[2] == #'經度: 5')
assert(spans[2].start[1] == 2 and spans[2].start[2] == 0)
assert(spans[2].finish[1] == 5 and spans[2].finish[2] == 0)
assert(spans[3].start[1] == 7 and spans[3].finish[1] == 7)
assert(spans[4].start[1] == 8)
local positions = {}
for _, span in ipairs(spans) do
  positions[span.name] = { row = span.start[1], col = span.start[2], last = #lines[span.start[1] + 1] }
end
local raw = { x = ' 5 ', note = '\n\t中文\n  content\n\n', empty = ' \n\t', enabled = ' false ' }
data, errors = schema.validate_ranges(multi, lines, raw, positions)
assert(data and data.x == 5 and data.note == raw.note and data.empty == nil and data.enabled == false)
raw.note = ' \n\t'
data, errors = schema.validate_ranges(multi, lines, raw, positions)
assert(not data and #errors == 1 and errors[1].name == 'note' and errors[1].row == 2)
for _, invalid in ipairs({
  { name = 'x', multiline = 'yes' },
  { name = 'x', multiline = true, type = 'number' },
  { name = 'x', multiline = true, default = 42 },
  { name = 'x', multiline = true, default = 'a\rb' },
  { name = 'x', default = 'a\nb' },
}) do
  assert(not pcall(schema.compile, { fields = { invalid } }))
end
print('multiline schema tests passed')
