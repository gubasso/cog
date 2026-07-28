# Subcommand Pattern (Python)

> Prerequisite: [General principles — Architecture](../../../cli-design/00-architecture.md) for the four-edit rule, parse-shape vs runtime-shape, and service extraction. Parameter-level Typer details live in [Typer / Click Patterns](./typer-patterns.md).

## The four responsibilities (Python + Typer)

Rust has a literal four-edit rule because parser registration and dispatch usually land in separate files. Python with Typer keeps the same four responsibilities, but steps 2 and 4 often collapse into one module or callback: the same function that Typer registers may also build the request and call the handler.

For a new `widget` subcommand, the responsibilities are:

1. **`cli/widget.py`** — Typer command definition, parse-shape only.
2. **`cli/__init__.py` or `cli/app.py`** — register with `app.add_typer(...)` or `@app.command`.
3. **`commands/widget.py`** — runtime handler, a free `run(ctx, request)` function.
4. **Root dispatch/wrapper** — call the handler from the Typer callback or command body.

The important invariant is not the number of touched files. It is that parser shape, registration, runtime projection, and command execution remain separate responsibilities.

## File-by-file skeleton

### 1. `cli/widget.py` (parse-shape)

```python
from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from app.commands import widget as widget_command
from app.context import AppContext
from app.error import run_with_error_boundary

app = typer.Typer(help="Operate on widgets.")


@app.command(help="Inspect widgets.", rich_help_panel="Widget commands")
def inspect(
    ctx: typer.Context,
    widget_id: Annotated[
        str | None,
        typer.Argument(help="Widget ID to inspect. Omit to inspect all widgets."),
    ] = None,
    config: Annotated[
        Path | None,
        typer.Option(
            "--config",
            exists=True,
            file_okay=True,
            dir_okay=False,
            readable=True,
            resolve_path=True,
            help="Path to an alternate config file.",
        ),
    ] = None,
    dry_run: Annotated[
        bool,
        typer.Option("--dry-run", "-n", help="Print what would happen without modifying anything."),
    ] = False,
) -> None:
    app_ctx = ctx.obj["app_context"]

    def handler() -> None:
        request = widget_command.request_from_cli(
            widget_id=widget_id,
            config=config,
            dry_run=dry_run,
        )
        widget_command.run(app_ctx, request)

    run_with_error_boundary(handler)
```

Rules:

- One file per subcommand or subcommand group.
- Typer owns parse-shape: options, arguments, names, short help, and parser-level coercion.
- No business logic, no direct I/O, and no service calls except the final handoff to the command handler.
- Keep deeper parameter recipes in [Typer / Click Patterns](./typer-patterns.md), not in every subcommand chapter.

### 2. `cli/__init__.py` or `cli/app.py` (register the command)

```python
from __future__ import annotations

import typer

from app.cli import widget

app = typer.Typer(
    name="app",
    help="One-line summary that shows in generated help.",
)

app.add_typer(widget.app, name="widget")
```

Use a sub-`Typer` when a command has subcommands of its own or enough options to deserve a dedicated file. For a simple top-level verb, `@app.command` in the root app module is fine as long as the same parse-shape and handler boundaries remain intact.

### 3. `commands/widget.py` (handler)

```python
from __future__ import annotations

from pathlib import Path

from pydantic import BaseModel, ConfigDict, field_validator

from app.context import AppContext
from app.error import AppError, DomainError


class WidgetRequest(BaseModel):
    model_config = ConfigDict(frozen=True)

    widget_id: str | None
    config: Path | None
    dry_run: bool = False

    @field_validator("widget_id")
    @classmethod
    def normalize_widget_id(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("widget id must not be empty")
        return cleaned


def request_from_cli(
    *,
    widget_id: str | None,
    config: Path | None,
    dry_run: bool,
) -> WidgetRequest:
    try:
        return WidgetRequest(widget_id=widget_id, config=config, dry_run=dry_run)
    except ValueError as exc:
        raise DomainError(
            "invalid widget request",
            kind="WidgetRequestInvalid",
            context={"widget_id": widget_id},
        ) from exc


def run(ctx: AppContext, request: WidgetRequest) -> None:
    report = ctx.services.widgets.inspect(request)
    ctx.output.render_widget_report(report)
```

Rules:

- The handler is a free function named `run`, not a method on the parser object.
- Signature: `run(ctx: AppContext, request: WidgetRequest) -> None`.
- Projection from Typer params into `WidgetRequest` happens once, at the top of this boundary.
- After projection, services and adapters never see raw command-line strings.
- Handlers raise typed `AppError` subclasses; process exit is owned by the Typer boundary.

### 4. Root command body (wire dispatch)

```python
from __future__ import annotations

import typer

from app.context import AppContext
from app.error import run_with_error_boundary


def build_context() -> AppContext:
    return AppContext.load()


@app.callback()
def main(ctx: typer.Context) -> None:
    ctx.obj = {"app_context": build_context()}


@app.command(help="Run a one-file command without a sub-Typer.")
def doctor(ctx: typer.Context) -> None:
    app_ctx = ctx.obj["app_context"]
    run_with_error_boundary(lambda: doctor_command.run(app_ctx))
```

If the project uses `click.get_current_context().obj`, keep that lookup at the CLI boundary. Do not let service or domain code reach back into Click globals.

## Parse-shape → runtime-shape, in Python

See [General — parse-shape vs runtime-shape](../../../cli-design/00-architecture.md#parse-shape-vs-runtime-shape). The Python-specific mapping is:

- Typer params are parser-friendly: `str`, `Path`, `list[str]`, `bool`, optional values, and parser callbacks.
- Pydantic request models are runtime-friendly: normalized IDs, validated combinations, frozen request objects, and domain-facing names.
- The projection lives beside the command handler, not inside domain or adapter code.

For path options, callbacks, `RootModel`, and multi-value parsing, use [Typer / Click Patterns](./typer-patterns.md) instead of repeating those parameter-level mechanics.

## Handler signature convention

Every command handler exposes a free function:

```python
def run(ctx: AppContext, request: WidgetRequest) -> None:
    ...
```

Handlers return `None` on success and raise typed `AppError` subclasses on failure. They do not return process exit codes and do not call `sys.exit`; the boundary described in [Error Handling (Python)](./error-handling-python.md) owns that mapping.

## When to extract a service

See [General — When to extract a service](../../../cli-design/00-architecture.md#when-to-extract-a-service). Python has no special override: keep single-use orchestration in `commands/<name>.py`. Extract a service only when another command needs the same orchestration, the pure core deserves isolated tests, or the handler grows past the readable-command boundary.

## Python-specific anti-patterns

- **Giant `cli.py`** — every parser and handler in one file. Split parse-shape by subcommand.
- **Handler method on the parser object** — couples Typer's parse-shape to runtime execution.
- **Pydantic model doing I/O** — validators normalize and reject values; adapters talk to external systems.
- **Auto-discovered command registry** — useful for plugin systems, excessive for ordinary apps.
- **Direct `print` / `typer.echo` from commands** — machine-facing output belongs behind a structured output boundary; human-facing output belongs behind `ui/`.

## Help rendering with Typer / Click

> Prerequisite: [General — `--help` is generated, not authored](../../../cli-design/07-naming-and-docs.md#--help-is-generated-not-authored). Typer and Click own usage, option, and subcommand tables.

Use parser metadata for generated help:

- `help=` gives a short parser-owned description for commands, arguments, and options.
- `rich_help_panel=` groups related options for human-facing help without changing the parser contract.
- `epilog` or `context_settings` can carry narrative addenda such as examples or environment variables.

Do not hand-author usage lines, flag tables, or subcommand lists. They drift. When the parser owns the structure, `--help`, shell completion, and generated documentation remain consistent.

For machine-facing CLIs, keep generated `help`, `--json`, `doctor`, `init`, completion, and man-page surfaces terse, parseable, and self-documenting for agents. Human addenda belong behind explicit human-UX surfaces or long-form help.

## Rules

- Keep one parse-shape file under `cli/<name>.py` and one runtime handler under `commands/<name>.py`.
- Treat the Rust four-edit rule as four responsibilities; Typer may combine registration and dispatch in one callback.
- Project Typer params into a Pydantic v2 request model before calling services.
- Use a free `run(ctx, request)` handler and raise typed `AppError` subclasses.
- Let Typer and Click generate help structure; author only short descriptions and narrative addenda.
