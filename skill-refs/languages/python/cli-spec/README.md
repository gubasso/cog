# Python CLI Spec

Python-specific conventions for building a CLI tool, primarily with **Typer** (which wraps **Click**) and **Pydantic** for validation.

For the language-agnostic principles, see [`tech/cli-design/`](../../../cli-design/). Every Python-specific rule here applies the general principles to the specifics of Python. Facing-category consequences follow [General — Facing category & message types](../../../cli-design/00-architecture.md#facing-category--message-types).

## Files

| File                                                             | Hook                                                                                                                  |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| [typer-patterns.md](./typer-patterns.md)                         | Practical Typer/Click patterns: path options, Pydantic validators, multi-value parsing, RootModel-based custom types. |
| [parse-cli-options-examples.py](./parse-cli-options-examples.py) | Runnable examples: Typer + Pydantic for validation callbacks, tag parsing, complex key=value parsing.                 |
| [config-precedence-python.md](./config-precedence-python.md)     | Layered config-path resolution with `lru_cache` + `pydantic-settings`.                                                |
| [logging-python.md](./logging-python.md)                         | File-first `structlog` setup with XDG state paths and optional stderr mirroring.                                      |
| [subcommand-pattern-python.md](./subcommand-pattern-python.md)   | Typer subcommand structure: parse-shape files, handler files, dispatch wiring, and help rendering.                    |
| [error-handling-python.md](./error-handling-python.md)           | Layered Python exceptions, stable error kinds, BSD sysexits, and the top-level Typer error boundary.                  |
| [symbol-visibility-python.md](./symbol-visibility-python.md)     | Enforce the leading-underscore module-private convention via a custom AST pre-commit checker + Ruff `PLC2701`.        |

## Stack defaults

| Concern                  | Library                                            |
| ------------------------ | -------------------------------------------------- |
| Argument parsing         | `typer` (built on `click`)                         |
| Validation               | `pydantic` v2                                      |
| Layered config           | `pydantic-settings`                                |
| Logging emission         | `structlog` (or `loguru` for simplicity)           |
| Human-UX terminal output | `rich` (human-facing only)                         |
| Interactive prompts      | `questionary` or `rich.prompt` (human-facing only) |
| Tests                    | `pytest` + `typer.testing.CliRunner`               |
| Snapshots                | `syrupy`                                           |
| Linting                  | `ruff`                                             |
| Formatting               | `ruff format`                                      |
| Type checking            | `mypy` or `pyright`                                |

## TL;DR

- One file per subcommand under `cli/`; one handler per subcommand under `commands/`.
- General parse-shape → runtime-shape maps to **Typer parameters → Pydantic request models** in Python.
- Validation lives in `__post_init__` / Pydantic validators, not in handler bodies.
- Logging via `structlog` writes structured records to `${XDG_STATE_HOME:-~/.local/state}/<app>/<app>.log` by default.
- `pytest` with `-n auto`. Every subcommand has `tests/test_cmd_<name>.py`.

## See also

- [General — Architecture](../../../cli-design/00-architecture.md)
- [General — Logging & Output](../../../cli-design/01-logging-and-output.md)
- [General — Error Messages](../../../cli-design/02-error-messages.md)
- [General — Config Precedence](../../../cli-design/03-config-precedence.md)
- [General — Coding Style (Rust/Zig flavor, with Python translations)](../../../cli-design/04-coding-style-rust-zig.md)
- [Python — Logging](./logging-python.md)
- [Python — Error Handling](./error-handling-python.md)
