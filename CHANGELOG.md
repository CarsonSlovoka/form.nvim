# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Support for specifying a local output destination with `:w filename`, `:w! filename`, and `:wq filename`.
- Built-in file persistence with raw text, JSON, and custom serializer functions via the `format` option.
- Optional `path` setting for a default output destination; an explicit filename overrides it for a single write.
- `ctx.path` and `ctx.force` in the `on_submit` callback and custom serializer context.
- Overwrite protection, staged file writes, and diagnostics for serialization or filesystem failures.
- Traditional Chinese documentation (`README.zh_TW.md`) and a project changelog.
- Serializer and simulated-filesystem writer unit tests, plus filesystem integration tests covering explicit and default destinations, overwrite protection, validation, and callback precedence.

### Changed

- Forms without an `on_submit` callback can now write directly to disk when an output path is supplied.
- The location example now demonstrates built-in JSON export instead of requiring a custom submission callback.

## [0.1.0]

### Added

- Initial form API using native `vim.snippet` and `acwrite` buffers.
- Schema-driven single-line fields, defaults, required values, type conversion, numeric bounds, and custom field/form validation.
- Validation and synchronous submission on `:w`, with native diagnostics and modified-state handling.
- Buffer-local snippet navigation, configurable windows, English README, Neovim help, examples, and tests.

[Unreleased]: #unreleased
[0.1.0]: #010
