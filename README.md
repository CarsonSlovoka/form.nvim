# form.nvim

[English](README.md) | [繁體中文](README.zh_TW.md) | [Changelog](CHANGELOG.md)

A dependency-free form UI for Neovim 0.12+. Native `vim.snippet` handles input; `:write` validates and submits. Single-line and multiline string fields are supported. Independent Extmark anchors track multiline form structure and report structural errors during editing; value validation and submission remain write-time only. No snippet-completion hooks, private snippet APIs, LSP, or external dependencies.

## Install

Extract `form.nvim.zip` (or `form.nvim-unreleased.zip`) into a native package directory. On a default macOS/Linux Neovim setup:

```sh
mkdir -p ~/.local/share/nvim/site/pack/local/start
unzip form.nvim-unreleased.zip -d ~/.local/share/nvim/site/pack/local/start
```

For an existing installation, replace the old plugin directory with the new `form.nvim/` directory. Restart Neovim. If you use another data directory, check `:echo stdpath('data')`. Run `:helptags ~/.local/share/nvim/site/pack/local/start/form.nvim/doc` to enable `:help form.nvim`.

Alternatively, add the plugin directory to `runtimepath` while developing it:

```lua
vim.opt.runtimepath:prepend('/path/to/form.nvim')
```

No `setup()` call is required.

## Quick start

```lua
vim.api.nvim_create_user_command('LocationForm', function()
  require('form').open({
    title = 'location',
    fields = {
      { name = 'longitude', label = '經度', type = 'number', min = -180, max = 180, required = true },
      { name = 'latitude', label = '緯度', type = 'number', min = -90, max = 90, required = true },
      { name = 'description', label = '描述', multiline = true, required = true },
    },
    format = 'json',
  })
end, {})
```

Run `:LocationForm`. Tab and Shift-Tab move between native snippet tabstops. Press Escape, then `:w ~/location.json` to validate and write the result to disk. Errors appear as native diagnostics (use `]d` / `[d` to move between them). Edit freely in Normal or Insert mode and write again.

Example output (JSON key order is not guaranteed):

```json
{"longitude":121.5,"latitude":25.03,"description":"台北車站\n  Nearby shops"}
```

## API

`require('form').open(spec)` opens a new listed `acwrite` buffer and returns its buffer number. Call from Normal mode, a user command, or a Normal-mode mapping.

| Form option | Meaning |
| --- | --- |
| `title` | Display name for the virtual buffer (default `form`). |
| `fields` | Non-empty ordered list of field definitions. |
| `window` | `split` (default), `vsplit`, or `current`. |
| `path` | Optional default local output path, made absolute when the form opens; explicit `:w filename` overrides it for that write only. |
| `format` | `raw` (default), `json`, or a function `(data, ctx) -> string or string[]`. Used only by the built-in writer when a path is available. |
| `validate` | Optional function `(data) -> nil or { field_name = 'message' }`. |
| `on_submit` | Optional synchronous function `(data, ctx)` that replaces the built-in writer. |
| `mappings` | Buffer-local Tab/Shift-Tab mappings; set `false` to keep your own. |
| `diagnostic` | Native diagnostic display options; merged with defaults. |
| `notify` | Set `false` to disable the success notification. |

| Field option | Meaning |
| --- | --- |
| `name` | Unique Lua table key, starting with an ASCII letter or `_`; remaining characters may be letters, digits, `_`, `.`, `-`. `_form` is reserved. |
| `label` | Optional display label; defaults to `name`. Unique, no colon or control characters. |
| `type` | `string` (default), `number`, `integer`, `boolean`. |
| `required` | `true` disallows empty or whitespace-only values. Defaults to `false`. |
| `multiline` | Boolean, default `false`; available for `type = 'string'` only. |
| `default` | Initial single-line scalar, or a string containing LF/tab for a multiline field; native snippet selects nonempty defaults. |
| `min`, `max` | Inclusive numeric bounds for `number` and `integer`. |
| `validate` | Optional function `(value) -> true` or `false, 'message'`. |

Numbers use Lua `tonumber`, then reject non-finite values. Integers must have no fractional part. Boolean text must be exactly `true` or `false`. Single-line values are trimmed during parsing. Multiline strings preserve their exact nonblank content, including leading/trailing whitespace and LF. Empty or whitespace-only values are omitted (`nil`) if optional and rejected if required. A field's custom validator runs only if that field has a non-empty, successfully parsed value. The form-level validator runs only when all field-level checks pass.

### Multiline fields

Set `multiline = true` on a string field; the label appears on its own line and the value starts on the next line. Other fields keep their existing `Label: value` layout. For example:

```lua
{
  name = 'description',
  label = 'Description',
  type = 'string',
  multiline = true,
  default = 'First line\n  Second line\n\nThird line',
}
```

```text
Title: Hello
Description:
First line
  Second line

Third line
Author: Admin
```

- Enter, paste, and linewise editing inside a multiline value can add or remove lines without imposing indentation or requiring an end delimiter. Keep at least one value line even when empty; clear the text rather than deleting the only value line.
- Independent Extmark label anchors track all fields of a form containing at least one multiline field. The next anchored label (or end of buffer) determines the value range, so literal text such as `Author: example` in a value is not mistaken for a field. Label text, order and position at the start of its line must remain intact. Single-line fields in a mixed form must stay on one line and retain their exact label prefix.
- Edits are not intercepted or automatically repaired. Structural diagnostics refresh on text changes (display during Insert mode follows `diagnostic.update_in_insert`); use `u` / `Ctrl-R` to restore or redo structural changes. Replacing an entire anchored label, even with identical text, may invalidate its anchor; use Undo to restore it. The initial layout is not an undoable edit. Avoid replacing the entire mixed-form buffer.
- Native snippet navigation is unchanged and works while the snippet session is active. After it stops, the form still tracks values, accepts Normal/Insert mode edits, and submits through `:w`. Structural checks do not execute custom validators. `:w` always checks the current structure before type conversion, custom validation or output.
- Forms without any multiline field keep the original line-based parser and write-time diagnostics, including support for replacing entire lines with the expected labels.

The submitted value is a Lua string, not a list. JSON encodes its newlines as `\n`; raw output preserves the actual buffer lines.

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
  on_submit = function(data, ctx)
    vim.print(data, ctx)
  end,
})
```

## Writing to a real file

You do not need an `on_submit` callback to write to disk. The built-in writer runs after validation if an output path is available and no custom `on_submit` is defined.

| Command | Behavior |
| --- | --- |
| `:w` | Use `path` if configured; otherwise validate and submit without writing a file. |
| `:w ~/my.txt` | Use the specified path instead of the default. |
| `:w! ~/my.txt` | Permit replacing an existing regular file; validation still runs. |
| `:wq ~/my.txt` | Validate and write, then close the window only on success. |
| `:w!` | Permit replacing the configured default file. |

Explicit destinations are one-time exports. The buffer keeps its `form://` name, and a subsequent bare `:w` does not reuse the previous explicit filename. If a default file already exists, use `:w!` to replace it. Neovim may reject an explicit existing destination before `BufWriteCmd` is reached; such a command does not submit or write the form. A bare `:w` with neither `path` nor `on_submit` preserves the original validation-only behavior of v0.1.0.

### Output formats

| `format` | Output |
| --- | --- |
| `raw` | Exact form buffer lines, including labels and original whitespace, with LF separators and a final newline. |
| `json` | A JSON object containing validated, typed field values and a final newline. Optional empty fields are omitted; an entirely empty object is `{}`. |
| Function | A string or a dense list of single-line strings, using validated data and submission context. A nonempty list is joined by LF with a final newline; an empty list writes an empty file. A string gets a final LF if it does not already end in one. |

Choose a format explicitly; file extensions do not select the serializer automatically. The built-in writer emits UTF-8 text with LF line endings rather than applying Neovim file encoding and line-ending options.

```lua
require('form').open({
  title = 'location',
  fields = {
    { name = 'longitude', type = 'number', required = true, min = -180, max = 180 },
    { name = 'latitude', type = 'number', required = true, min = -90, max = 90 },
    { name = 'description', required = true },
  },
  path = '~/location.txt', -- optional; omit to specify a destination via :w
  format = function(data, ctx)
    return {
      'Longitude: ' .. data.longitude,
      'Latitude: ' .. data.latitude,
      'Description: ' .. data.description,
    }
  end,
})
```

The built-in writer requires the parent directory to exist. It stages output in a temporary file in that directory, creates the destination without overwriting (using a hard link), or replaces an existing regular file with `:w!` (using rename). New files have private temporary-file permissions (normally `0600` on POSIX); forced replacement preserves ordinary permission bits but not ownership, ACLs, extended attributes or hard-link identity. The destination filesystem must support the corresponding link/rename operations. Symbolic links, directories and other non-regular existing destinations are rejected. This is not a substitute for backups or a security boundary.

### Custom submission

`on_submit(data, ctx)` takes full responsibility for persistence, even when a path is supplied. The built-in serializer and writer do not run when this callback is configured. The plugin does not create a file or implement filesystem overwrite checks for the callback; handle those details yourself if needed. Neovim may still reject an explicit existing destination before invoking the callback.

| Context field | Meaning |
| --- | --- |
| `bufnr` | Form buffer number. |
| `title` | Form title. |
| `path` | Effective absolute local path, or `nil` if neither an explicit destination nor `path` was supplied. |
| `force` | Boolean indicating whether the write command used `!`. |

For example, use your own persistence function or send validated data to another subsystem:

```lua
on_submit = function(data, ctx)
  if not ctx.path then
    return false, 'Please specify an output path'
  end
  -- Your own synchronous persistence code goes here.
  -- For ordinary file exports, omit on_submit and use format instead.
  vim.print(data, ctx.path, ctx.force)
end,
```

Returning `false, message` or throwing an error rejects the write. Any other normal return (including nil) means success. Callbacks and format functions must complete synchronously and must not change/delete the form buffer itself. If a callback has external side effects and subsequently fails, the plugin cannot roll them back.

## Write semantics

- When Neovim accepts `:w` and reaches the form write handler, it checks all fields and submits if valid, independently of snippet state or the modified flag. Repeated writes call the submission callback again; callbacks should handle duplicates if necessary.
- Failed validation, serialization, file I/O or submission within the write handler raises a write error, retains `modified`, and displays diagnostics. `:w!` never bypasses validation. A failed `:wq` should leave the form open.
- Successful submission clears the plugin's diagnostics and resets `modified`. `:update` and `:x` may skip writing an already unmodified buffer, as usual.
- Value-validation and submission diagnostics are snapshots from the last write attempt. Mixed/multiline forms additionally refresh structural diagnostics during editing; the next write rechecks both.
- Fields retain schema order. Single-line fields occupy one line; multiline string fields use a label line followed by one or more value lines. Labels must stay intact. Colons and label-like lines inside values are fine.
- Partial writes and appending are unsupported. `:saveas` is not a supported form workflow; use `:w filename` instead. `:write !command` is Neovim's external-filter/output mechanism, not form submission.
- Normal buffers are unaffected. Forms can be hidden and reopened using `:buffer` / `:ls`. Use `:bd!` to discard a form buffer; `:q!` may leave it hidden if other windows remain.
- Global `autowrite`/`autowriteall` can also initiate writes; turn them off if you want submission only on explicit writes.

## Development

```sh
make test
# or: make test NVIM=/path/to/nvim
```

The schema, serializer, and simulated-filesystem writer unit suites can also be run using standalone Lua. The integration suites require Neovim 0.12+ and exercise write events, failure/retry, callback context, actual files, output formats, overwrite protection, `:wq`, multiline range tracking, structural diagnostics, Undo/Redo, and independent submission after the snippet session ends.

## Versions

See [CHANGELOG.md](CHANGELOG.md). The project follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) and [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). Changes stay under `Unreleased` until a release is explicitly made.
