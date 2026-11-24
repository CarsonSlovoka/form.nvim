# form.nvim

A small, dependency-free form UI for Neovim 0.12+. Native `vim.snippet` handles input; `:write` validates and submits. No snippet-completion hooks, private snippet APIs, LSP, or live validation.

## Install

Extract `form.nvim.zip` into a native package directory. On a default macOS/Linux Neovim setup:

```sh
mkdir -p ~/.local/share/nvim/site/pack/local/start
unzip form.nvim.zip -d ~/.local/share/nvim/site/pack/local/start
```

Restart Neovim. If you use another data directory, check `:echo stdpath('data')`.
For help tags, run `:helptags ~/.local/share/nvim/site/pack/local/start/form.nvim/doc`.

## Quick start

```lua
vim.api.nvim_create_user_command('LocationForm', function()
  require('form').open({
    title = 'location',
    fields = {
      { name = 'longitude', label = '經度', type = 'number', min = -180, max = 180, required = true },
      { name = 'latitude', label = '緯度', type = 'number', min = -90, max = 90, required = true },
      { name = 'description', label = '描述', required = true },
    },
    on_submit = function(data)
      vim.print(data)
    end,
  })
end, {})
```

Run `:LocationForm`. Tab and Shift-Tab move between the native snippet tabstops. Press Escape, then `:w` to validate and submit. Errors appear as native diagnostics (use `]d` / `[d` to move between them). Edit freely in Normal mode or Insert mode and write again.

## API

`require('form').open(spec)` opens a new listed `acwrite` buffer and returns its buffer number. Call from Normal mode, a user command, or a Normal-mode mapping. No `setup()` call required.

| Form option | Meaning |
| --- | --- |
| `title` | Display name for the virtual buffer (default `form`). |
| `fields` | Non-empty ordered list of field definitions. |
| `window` | `split` (default), `vsplit`, or `current`. |
| `validate` | Optional function `(data) -> nil or { field_name = 'message' }`. |
| `on_submit` | Optional synchronous function `(data, context)`. |
| `mappings` | Buffer-local Tab/Shift-Tab mappings; set `false` to keep your own. |
| `diagnostic` | Native diagnostic display options; merged with defaults. |
| `notify` | Set `false` to disable the success notification. |

| Field option | Meaning |
| --- | --- |
| `name` | Unique Lua table key, starting with an ASCII letter or `_`; remaining characters may be letters, digits, `_`, `.`, `-`. `_form` is reserved. |
| `label` | Optional display label; defaults to `name`. Unique, no colon or control characters. |
| `type` | `string` (default), `number`, `integer`, `boolean`. |
| `required` | `true` disallows empty or whitespace-only values. Defaults to `false`. |
| `default` | Initial single-line scalar value; selected on entering the tabstop if non-empty. |
| `min`, `max` | Inclusive numeric bounds for `number` and `integer`. |
| `validate` | Optional function `(value) -> true` or `false, 'message'`. |

Numbers use Lua `tonumber`, then reject non-finite values. Integers must have no fractional part. Boolean text must be exactly `true` or `false`. All field values are trimmed; an omitted optional value is absent (`nil`) in the returned table. A field's custom validator runs only if that field has a non-empty, successfully parsed value. The form-level validator runs only when all field-level checks pass.

### Custom validation and cross-field rules

```lua
require('form').open({
  title = 'range',
  fields = {
    { name = 'start', type = 'integer', required = true },
    { name = 'finish', type = 'integer', required = true },
    {
      name = 'description', required = true,
      validate = function(value)
        return vim.fn.strchars(value) >= 3, 'Enter at least 3 characters'
      end,
    },
  },
  validate = function(data)
    if data.finish < data.start then
      return { finish = 'Must be greater than or equal to start' }
    end
    -- nil or {} means success; use _form for a general error.
  end,
  on_submit = function(data, context)
    vim.print(data, context)
  end,
})
```

### Writing to a real file

A form buffer is virtual. The plugin does not write any disk file by default. Define persistence in `on_submit`:

```lua
on_submit = function(data)
  local path = vim.fn.stdpath('data') .. '/location.json'
  if vim.fn.writefile({ vim.json.encode(data) }, path) ~= 0 then
    return false, 'Could not write ' .. path
  end
end,
```

The callback can instead write a database entry, send an IPC request, or update another buffer. Returning `false, message` or throwing an error rejects the write. Any other normal return (including nil) means success. Callback completion must be synchronous. Do not change/delete the form buffer itself from the callback. If a callback has external side effects and subsequently fails, the plugin cannot roll them back.

## Write semantics

- `:w` checks all fields and submits if valid, even if the snippet session has ended or the buffer has not changed. Repeated writes call the submission callback again; callbacks should handle duplicates if necessary.
- A failed validation or callback produces a real write error, retains the modified flag, and does not mark the form as saved. `:w!` uses the same validation. On a failed write, `:wq` is intended to stay open.
- A successful submission clears the plugin's diagnostics and resets `modified`. `:wq` then closes the window. `:update` and `:x` may skip writing an already unmodified buffer, as usual.
- Diagnostics are snapshots from the last write attempt; they are not revalidated while typing. The next write replaces them.
- A form uses exactly one line per field, in schema order. Labels are part of the structure and must stay intact. Colons inside values are fine. Multiline values are not supported in this version.
- Alternate filenames, partial writes, and appending are unsupported. `:write !command` is Neovim's external-filter/output mechanism, not a form submission. This plugin is a workflow tool, not a security boundary.
- Normal buffers are unaffected. Forms can be hidden and reopened using `:buffer` / `:ls`. Use `:bd!` to discard a form buffer; `:q!` closes its window and may leave the buffer hidden if other windows remain.
- Neovim's global `autowrite`/`autowriteall` can also initiate writes; turn them off if you want submission only when you explicitly write.

## Development

```sh
make test
```

The first suite tests the pure Lua schema, parsing, validation and snippet rendering. The second requires Neovim and exercises real write events, failure/retry, forced writes, `:wq`, and callback rejection.

Build verification: pure Lua schema tests and Lua syntax checks passed using Lua 5.4. Neovim was unavailable in the build environment, so the integration suite is supplied but has not been run there. Run `make test` on Neovim 0.12+ before relying on it in production.
