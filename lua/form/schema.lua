-- Pure Lua schema, snippet rendering, parsing and validation.
local M = {}

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function check(condition, message)
  assert(condition, 'form.nvim: ' .. message)
end

local function finite(n)
  return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function scalar(v)
  return type(v) == 'string' or type(v) == 'boolean' or finite(v)
end

local function escape(s)
  return (s:gsub('[\\$}]', '\\%0'))
end

local function optional_function(v, name)
  check(v == nil or type(v) == 'function', name .. ' must be a function')
end

function M.compile(spec)
  check(type(spec) == 'table', 'expected a form definition')
  check(type(spec.fields) == 'table' and #spec.fields > 0, 'fields must be a non-empty list')
  for k in pairs(spec.fields) do
    check(type(k) == 'number' and k % 1 == 0 and k >= 1 and k <= #spec.fields,
      'fields must be a dense list')
  end
  optional_function(spec.validate, 'validate')
  optional_function(spec.on_submit, 'on_submit')
  local fields, by_name, labels = {}, {}, {}
  for i = 1, #spec.fields do
    local f = spec.fields[i]
    check(type(f) == 'table', 'invalid field #' .. i)
    check(type(f.name) == 'string' and f.name:match('^[%a_][%w_.%-]*$') and f.name ~= '_form',
      'invalid field name at #' .. i .. ' (_form is reserved)')
    check(not by_name[f.name], 'duplicate field: ' .. f.name)
    local label = f.label or f.name
    check(type(label) == 'string' and label ~= '' and trim(label) == label and not label:find('[:%c]'),
      'invalid label for ' .. f.name)
    check(not labels[label], 'duplicate label: ' .. label)
    local kind = f.type or 'string'
    check(kind == 'string' or kind == 'number' or kind == 'integer' or kind == 'boolean',
      'unsupported type for ' .. f.name)
    check(f.required == nil or type(f.required) == 'boolean', 'required must be a boolean')
    local numeric = kind == 'number' or kind == 'integer'
    check(f.min == nil or (numeric and finite(f.min)), 'invalid min for ' .. f.name)
    check(f.max == nil or (numeric and finite(f.max)), 'invalid max for ' .. f.name)
    check(f.min == nil or f.max == nil or f.min <= f.max, 'min exceeds max for ' .. f.name)
    check(f.default == nil or (scalar(f.default) and not tostring(f.default):find('[%c]')),
      'default must be a single-line scalar for ' .. f.name)
    optional_function(f.validate, f.name .. '.validate')
    local field = {
      name = f.name,
      label = label,
      type = kind,
      required = f.required == true,
      default = f.default,
      min = f.min,
      max = f.max,
      validate = f.validate,
      row = i,
    }
    fields[i], by_name[f.name], labels[label] = field, field, true
  end
  return { fields = fields, by_name = by_name, validate = spec.validate, on_submit = spec.on_submit }
end

function M.snippet(schema)
  local lines = {}
  for i, f in ipairs(schema.fields) do
    local text = f.default == nil and '' or tostring(f.default)
    local stop = text == '' and ('${%d}'):format(i) or ('${%d:%s}'):format(i, escape(text))
    lines[i] = escape(f.label .. ': ') .. stop
  end
  return table.concat(lines, '\n') .. '$0'
end

local function convert(f, text)
  if text == '' then
    if f.required then return nil, 'Required field' end
    return nil
  end
  if f.type == 'string' then return text end
  if f.type == 'boolean' then
    if text == 'true' then return true end
    if text == 'false' then return false end
    return nil, 'Expected true or false'
  end
  local n = tonumber(text)
  if not finite(n) then return nil, 'Expected a finite number' end
  if f.type == 'integer' and n % 1 ~= 0 then return nil, 'Expected an integer' end
  if f.min ~= nil and n < f.min then return nil, 'Must be greater than or equal to ' .. f.min end
  if f.max ~= nil and n > f.max then return nil, 'Must be less than or equal to ' .. f.max end
  return n
end

-- Every field gets checked before form-level validation. Error rows/columns are 0-based bytes.
function M.validate(schema, lines)
  local data, errors, positions = {}, {}, {}
  local function report(name, message, pos)
    pos = pos or { row = 0, col = 0, last = #(lines[1] or '') }
    errors[#errors + 1] = {
      name = name, message = tostring(message), row = pos.row, col = pos.col, last = pos.last,
    }
  end
  for i, f in ipairs(schema.fields) do
    local line = lines[i]
    local row = math.min(i - 1, math.max(0, #lines - 1))
    local pos = { row = row, col = 0, last = #(lines[row + 1] or '') }
    positions[f.name] = pos
    local prefix = f.label .. ':'
    if not line or line:sub(1, #prefix) ~= prefix then
      report(f.name, 'Expected field: ' .. f.label .. ':', pos)
    else
      local raw = line:sub(#prefix + 1)
      pos.col = #prefix + #(raw:match('^%s*') or '')
      local value, message = convert(f, trim(raw))
      if message then report(f.name, message, pos) else data[f.name] = value end
    end
  end
  if #lines > #schema.fields then
    local row = #schema.fields
    report('_form', 'Unexpected extra line(s); use one line per field', { row = row, col = 0, last = #lines[row + 1] })
  end
  -- Field validators only receive successfully parsed, non-empty values (false is a value).
  for _, f in ipairs(schema.fields) do
    if f.validate and data[f.name] ~= nil then
      local ok, valid, message = pcall(f.validate, data[f.name])
      if not ok then
        report(f.name, 'Validator error: ' .. tostring(valid), positions[f.name])
      elseif valid ~= true then
        report(f.name, message or 'Invalid value', positions[f.name])
      end
    end
  end
  -- Cross-field rules need a complete, valid typed table.
  if #errors == 0 and schema.validate then
    local ok, result = pcall(schema.validate, data)
    if not ok then
      report('_form', 'Validator error: ' .. tostring(result))
    elseif result ~= nil and type(result) ~= 'table' then
      report('_form', 'Form validator must return nil or a table of errors')
    elseif result then
      for _, f in ipairs(schema.fields) do
        if result[f.name] ~= nil then report(f.name, result[f.name], positions[f.name]) end
      end
      if result._form ~= nil then report('_form', result._form) end
      for name in pairs(result) do
        if name ~= '_form' and not schema.by_name[name] then
          report('_form', 'Unknown field in validator: ' .. tostring(name))
        end
      end
    end
  end
  if #errors > 0 then return nil, errors end
  return data, errors
end

return M
