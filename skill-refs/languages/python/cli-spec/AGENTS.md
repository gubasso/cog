---
digest-of: languages/python/cli-spec
last-synced: 2026-07-10
source-files:
  - README.md
  - config-precedence-python.md
  - error-handling-python.md
  - logging-python.md
  - parse-cli-options-examples.py
  - subcommand-pattern-python.md
  - symbol-visibility-python.md
  - typer-patterns.md
token-estimate: 500
---

# AGENTS

## Scope

Python-specific CLI conventions using Typer/Click and Pydantic. Covers stack defaults, subcommand layout, typed CLI patterns, layered errors, file-first logging, layered config, and validation callbacks.

## Key Points

- **Stack**: Typer (parsing), Pydantic v2 (validation), pydantic-settings (layered config), structlog/loguru (file-first logging), rich and questionary for human-facing UX only, pytest + syrupy (testing), ruff (lint+format).
- **Logging**: `structlog` JSON records default to `${XDG_STATE_HOME:-$HOME/.local/state}/<app>/<app>.log`; `mirror_stderr` is explicit opt-in and defaults false for machine-facing CLIs.
- **Subcommands**: One parse-shape file under `cli/<name>.py`, one runtime handler under `commands/<name>.py`; Typer params project into Pydantic request models before services run.
- **Parse-shape to runtime-shape**: Typer parameters map to Pydantic request models. Validation in `__post_init__`/validators, not handler bodies.
- **Error handling**: Typed `AppError` subclasses carry stable `kind` and context, map explicitly to BSD sysexits, and are caught once at the Typer boundary for structured stderr output.
- **Config precedence**: Two patterns: (1) manual 5-layer loader with `lru_cache`, `platformdirs`, provenance dict; (2) `pydantic-settings` with `settings_customise_sources` for larger configs.
- **Provenance**: Errors must name the source layer (`user-file:/path`, `env:MYAPP_X`, `cli-flag:--x`).
- **Typed CLI options**: Path validation at parse time (`exists=True`, `resolve_path=True`), Pydantic `RootModel` for custom types, `callback=` for email/tag validation.
- **Key=value parsing**: `extract_cli_server_details` pattern for complex multi-field CLI entries.
- **Testing**: `pytest -n auto`, one `tests/test_cmd_<name>.py` per subcommand, `typer.testing.CliRunner`.
- **Symbol visibility**: enforce the leading-underscore module-private convention with a custom stdlib-`ast` pre-commit checker — public iff referenced by another `src/` module (dev `tests/` excluded; tests may import `_name` internals). Custom checker owns Direction A (public name, no external ref → must be `_`); Ruff `PLC2701` (preview, isolated hook) owns Direction B (cross-module `_name` import). Auto-exempt union families, entry points, pytest fixtures/hooks; `# visibility: public` for dynamic cases. Resolve relative + module-qualified imports; rename with token-aware tooling.

## Source Map

| Topic                                        | File                            |
| -------------------------------------------- | ------------------------------- |
| Stack defaults, TL;DR                        | `README.md`                     |
| Typer subcommand structure, dispatch         | `subcommand-pattern-python.md`  |
| Layered exceptions, sysexits, error boundary | `error-handling-python.md`      |
| File-first structlog setup                   | `logging-python.md`             |
| Typer patterns, Pydantic validators          | `typer-patterns.md`             |
| 5-layer config loader, pydantic-settings     | `config-precedence-python.md`   |
| Runnable validation examples                 | `parse-cli-options-examples.py` |
| Leading-underscore visibility enforcement    | `symbol-visibility-python.md`   |

## Maintenance Notes

- The `.py` file contains runnable examples, not documentation prose.
- Regenerate when Typer or Pydantic major versions change.
