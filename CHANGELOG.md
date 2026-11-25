# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Opt-in `multiline = true` for string fields, including multiline defaults and preservation of nonblank whitespace, indentation, and line breaks.
- Independent Extmark label anchors and structural diagnostics for mixed/multiline forms; values remain available after the native snippet session ends.
- Multiline schema, range, and integration tests covering linewise edits, label-like value text, invalid structures, Undo/Redo, diagnostics, and raw/JSON exports.
- Support for specifying a local output destination with `:w filename`, `:w! filename`, and `:wq filename`.
- Built-in file persistence with raw text, JSON, and custom serializer functions via the `format` option.
- Optional `path` setting for a default output destination; an explicit filename overrides it for a single write.
- `ctx.path` and `ctx.force` in the `on_submit` callback and custom serializer context.
- `ctx.serialize()` and `ctx.write()` for custom submission callbacks, with lazy, per-submission caching of successful formatted output and reuse of built-in overwrite protection.
- Unit and integration tests for the submission helpers, cache lifetime, missing destinations, and serialization/write failures.
- Overwrite protection, staged file writes, and diagnostics for serialization or filesystem failures.
- Traditional Chinese documentation (`README.zh_TW.md`) and a project changelog.
- Serializer and simulated-filesystem writer unit tests, plus filesystem integration tests covering explicit and default destinations, overwrite protection, validation, and callback precedence.

### Changed

- Mixed/multiline forms check anchored field structure during editing and again before submission; data validators and submission callbacks still run only on write. Single-line-only forms retain the legacy parser.
- The location example and bilingual documentation demonstrate multiline descriptions.
- Forms without an `on_submit` callback can now write directly to disk when an output path is supplied.
- The README location examples demonstrate built-in JSON export; the standalone example uses `ctx.write()` in its custom submission callback.

## [0.1.0]

### Added

- Initial form API using native `vim.snippet` and `acwrite` buffers.
- Schema-driven single-line fields, defaults, required values, type conversion, numeric bounds, and custom field/form validation.
- Validation and synchronous submission on `:w`, with native diagnostics and modified-state handling.
- Buffer-local snippet navigation, configurable windows, English README, Neovim help, examples, and tests.

[Unreleased]: #unreleased
[0.1.0]: #010
