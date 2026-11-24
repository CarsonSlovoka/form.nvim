-- Track form labels independently of vim.snippet's private state.
-- The value ranges are derived from the anchored labels: unlike an end-of-line
-- value extmark, the next label follows linewise insertions/deletions (o, dd, p).
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace('form.nvim.ranges')
local diagnostic_ns = api.nvim_create_namespace('form.nvim.structure')
local Tracker = {}
Tracker.__index = Tracker

local function issue(lines, errors, row, col, message, name)
  row = math.max(0, math.min(row or 0, #lines - 1))
  col = math.max(0, math.min(col or 0, #lines[row + 1]))
  errors[#errors + 1] = {
    lnum = row,
    col = col,
    end_col = #lines[row + 1],
    severity = vim.diagnostic.severity.ERROR,
    source = 'form.nvim.structure',
    code = name,
    message = message,
  }
end

-- fields: ordered rendered value ranges, using 0-based byte coordinates.
-- Each field: { name, multiline?, start = { row, col }, finish = { row, col } }.
-- Call after rendering/snippet expansion, before user edits; one tracker per buffer.
function M.attach(buf, fields)
  if buf == 0 then buf = api.nvim_get_current_buf() end
  assert(api.nvim_buf_is_loaded(buf), 'form.nvim: form buffer must be loaded')
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local anchors, names, next_row = {}, {}, 0
  assert(type(fields) == 'table' and #fields > 0, 'form.nvim: expected rendered fields')
  for _, field in ipairs(fields) do
    assert(type(field.name) == 'string' and not names[field.name], 'form.nvim: duplicate or invalid field')
    names[field.name] = true
    local row = field.start[1] - (field.multiline and 1 or 0)
    local last = field.finish[1]
    assert(row == next_row and last >= field.start[1] and last < #lines,
      'form.nvim: invalid rendered range: ' .. field.name)
    assert(field.finish[2] == #lines[last + 1], 'form.nvim: incomplete rendered value')
    assert(field.multiline or field.start[1] == last, 'form.nvim: single-line value spans multiple lines')
    local col = field.multiline and #lines[row + 1] or field.start[2]
    assert(col > 0 and col <= #lines[row + 1], 'form.nvim: invalid rendered label')
    assert(not field.multiline or field.start[2] == 0, 'form.nvim: invalid multiline value start')
    anchors[#anchors + 1] = {
      name = field.name,
      multiline = field.multiline == true,
      prefix = lines[row + 1]:sub(1, col),
      row = row,
    }
    next_row = last + 1
  end
  assert(next_row == #lines, 'form.nvim: untracked rendered text')
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.diagnostic.reset(diagnostic_ns, buf)
  for _, a in ipairs(anchors) do
    a.id = api.nvim_buf_set_extmark(buf, ns, a.row, 0, {
      end_row = a.row,
      end_col = #a.prefix,
      right_gravity = true,
      end_right_gravity = false,
      invalidate = true,
      undo_restore = true,
    })
  end
  return setmetatable({ buf = buf, anchors = anchors }, Tracker)
end

-- Only a label at its own tracked location can delimit a field. A line in a
-- multiline value that happens to look like another label remains value text.
function Tracker:collect()
  local buf = self.buf
  assert(api.nvim_buf_is_loaded(buf), 'form.nvim: form buffer must be loaded')
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local errors, values, positions, rows = {}, {}, {}, {}
  for i, a in ipairs(self.anchors) do
    local m = api.nvim_buf_get_extmark_by_id(buf, ns, a.id, { details = true })
    local row, col, d = m[1], m[2], m[3]
    if not d or d.invalid or not lines[row + 1] then
      issue(lines, errors, row or a.row, col, 'Missing field label: ' .. a.name, a.name)
    elseif col ~= 0 or d.end_row ~= row or d.end_col ~= #a.prefix
        or lines[row + 1]:sub(1, #a.prefix) ~= a.prefix
        or (a.multiline and lines[row + 1] ~= a.prefix) then
      issue(lines, errors, row, col, 'Modified or misplaced field label: ' .. a.name, a.name)
    else
      rows[i] = row
    end
  end
  -- Check the anchor ordering before slicing any values. Never guess a missing
  -- label by searching the body; it can legitimately contain identical text.
  if #errors == 0 then
    if rows[1] ~= 0 then
      issue(lines, errors, 0, 0, 'Unexpected text before first field', '_form')
    end
    for i, a in ipairs(self.anchors) do
      local row = rows[i]
      local next_row = rows[i + 1] or #lines
      local count = next_row - row
      if count < (a.multiline and 2 or 1) then
        issue(lines, errors, row, 0, 'Missing value line or invalid field order: ' .. a.name, a.name)
      elseif not a.multiline and count ~= 1 then
        issue(lines, errors, row, 0, 'Single-line field contains extra line(s): ' .. a.name, a.name)
      elseif a.multiline then
        values[a.name] = table.concat(lines, '\n', row + 2, next_row)
        positions[a.name] = { row = row + 1, col = 0, last = #lines[row + 2] }
      else
        local raw = lines[row + 1]:sub(#a.prefix + 1)
        values[a.name] = raw
        positions[a.name] = { row = row, col = #a.prefix + #(raw:match('^%s*') or ''), last = #lines[row + 1] }
      end
    end
  end
  if #errors > 0 then return nil, errors end
  return values, errors, positions
end

-- Synchronous recheck on write, plus structural diagnostics while editing.
-- No custom validators, snippet internals or user callbacks are invoked here.
function Tracker:refresh()
  local values, errors, positions = self:collect()
  vim.diagnostic.set(diagnostic_ns, self.buf, errors, self.display)
  return values, errors, positions
end

function Tracker:watch(display)
  self.display = display
  if self.event then return end
  self.event = api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    buffer = self.buf,
    callback = function() self:refresh() end,
    desc = 'Check form field structure',
  })
  self:refresh()
end

function Tracker:detach()
  if self.event then pcall(api.nvim_del_autocmd, self.event) end
  self.event = nil
  if api.nvim_buf_is_valid(self.buf) then
    api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
    vim.diagnostic.reset(diagnostic_ns, self.buf)
  end
end

return M
