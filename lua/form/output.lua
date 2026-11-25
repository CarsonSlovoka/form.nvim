-- File destinations and built-in serialization for form buffers.
local M = {}

function M.check_format(format)
  assert(format == nil or format == 'raw' or format == 'json' or type(format) == 'function',
    'form.nvim: format must be raw, json, or a function')
  return format or 'raw'
end

function M.path(path)
  assert(type(path) == 'string' and path ~= '' and not path:find('\0', 1, true),
    'form.nvim: path must be a non-empty file path')
  assert(not path:match('^%a[%w+%.%-]*://'), 'form.nvim: only local file paths are supported')
  -- Do not resolve symlinks or expand glob characters in the filename.
  return vim.fn.fnamemodify(path, ':p')
end

function M.serialize(format, data, ctx, lines)
  if format == 'raw' then return table.concat(lines, '\n') .. '\n' end
  if format == 'json' then
    return vim.json.encode(next(data) == nil and vim.empty_dict() or data) .. '\n'
  end
  local value = format(data, ctx)
  if type(value) == 'string' then
    return value:sub(-1) == '\n' and value or value .. '\n'
  end
  assert(type(value) == 'table', 'format must return a string or a list of lines')
  local count = #value
  for k, v in pairs(value) do
    assert(type(k) == 'number' and k % 1 == 0 and k >= 1 and k <= count
      and type(v) == 'string' and not v:find('\n', 1, true),
      'format must return a dense list of single-line strings')
  end
  for i = 1, count do
    assert(type(value[i]) == 'string', 'format must return a dense list of strings')
  end
  return count == 0 and '' or table.concat(value, '\n') .. '\n'
end

-- Helpers share a successful serialization for one synchronous submission.
-- Capture the resolved destination and bang flag, not mutable context fields.
function M.attach_context(ctx, format, data, lines)
  local path, force = ctx.path, ctx.force
  local active, serializing = true, false
  local cached

  local function check_active()
    if not active then error('Submission context is no longer active', 0) end
  end

  local function serialize()
    check_active()
    if cached ~= nil then return cached end
    if serializing then error('Recursive serialization is unsupported', 0) end
    serializing = true
    local ok, result = pcall(M.serialize, format, data, ctx, lines)
    serializing = false
    if not ok then error(result, 0) end
    cached = result
    return cached
  end

  ctx.serialize = serialize
  ctx.write = function()
    check_active()
    if not path then error('Please specify an output path', 0) end
    M.write(path, serialize(), force)
    return true
  end

  return function() active = false end
end

-- Publish only after writing the entire output. A hard link provides exclusive
-- creation without a check-then-overwrite race; rename implements forced replacement.
-- Both operations use a temporary file in the destination directory.
function M.write(path, contents, force)
  local uv = vim.uv
  local stat, err, code = uv.fs_lstat(path)
  if stat then
    if not force then error('File already exists; use :w! to overwrite: ' .. path, 0) end
    if stat.type ~= 'file' then error('Not a regular file: ' .. path, 0) end
  elseif code ~= 'ENOENT' then
    error(err or ('Cannot inspect ' .. path), 0)
  end

  local template = vim.fs.joinpath(vim.fs.dirname(path), '.form.nvim-XXXXXX')
  local fd, tmp = uv.fs_mkstemp(template)
  if not fd then error(tmp or 'Cannot create temporary file', 0) end

  local ok, reason = pcall(function()
    local offset = 0
    while offset < #contents do
      local n, write_err = uv.fs_write(fd, contents:sub(offset + 1), offset)
      if not n or n == 0 then error(write_err or 'Incomplete write', 0) end
      offset = offset + n
    end
    -- New files retain mkstemp's private permissions. Preserve ordinary mode
    -- bits on forced replacement, but do not copy special bits or metadata.
    if stat then assert(uv.fs_fchmod(fd, stat.mode % 512)) end
    assert(uv.fs_fsync(fd))
    local closed, close_err = uv.fs_close(fd)
    fd = nil
    assert(closed, close_err)

    if force then
      assert(uv.fs_rename(tmp, path))
      tmp = nil
    else
      local linked, link_err, link_code = uv.fs_link(tmp, path)
      if not linked and link_code == 'EEXIST' then
        error('File already exists; use :w! to overwrite: ' .. path, 0)
      end
      assert(linked, link_err)
    end
  end)
  if fd then pcall(uv.fs_close, fd) end
  if tmp then
    local removed, remove_err = uv.fs_unlink(tmp)
    if not removed then
      -- A successful publication must not be reported as a failed write.
      vim.notify('form.nvim: Could not remove temporary file: ' .. tostring(remove_err), vim.log.levels.WARN)
    end
  end
  if not ok then error(reason, 0) end
end

return M
