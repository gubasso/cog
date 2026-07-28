# Error Handling (Python)

> Prerequisite: [General principles — Error Messages](../../../cli-design/02-error-messages.md) for stable `err.kind`, BSD sysexits, structured stderr, and error-chain expectations. This chapter is the Python implementation using typed exceptions and Typer.

Typed exception classes per layer, one top-level `AppError` base, explicit `kind` and `context`, and one Typer boundary that maps `AppError` to BSD sysexits and emits a structured error to `stderr`.

## The layer table

| Layer                 | Raises / catches                        | Rule                                                                                         |
| --------------------- | --------------------------------------- | -------------------------------------------------------------------------------------------- |
| `domain/`             | `DomainError` subclasses                | Invariant failures only. No filesystem, network, subprocess, or terminal concerns.           |
| `adapters/`           | `<Sys>AdapterError` subclasses          | One error family per external system. Wrap upstream exceptions with `raise ... from exc`.    |
| `services/`           | `ServiceError` subclasses               | Compose domain and adapter failures. Do not swallow causes or collapse distinct `kind`s.     |
| `commands/`           | raises `AppError` subclasses            | Handlers do not call `sys.exit`; they raise typed errors and let the boundary render them.   |
| Typer boundary / main | catches `AppError`, exits with its code | Emit the machine-facing error shape to `stderr`; map unexpected exceptions to `EX_SOFTWARE`. |

## Why typed exceptions, not bare `Exception`

- A stable `err.kind` gives scripts, logs, tests, and coding agents something durable to match.
- `raise ... from exc` preserves the cause chain, so the boundary can explain why the operation failed without parsing arbitrary prose.
- `exit_code` is explicit API surface. Shell callers can distinguish usage, config, input, I/O, and internal failures.
- Structured context keeps agent-readable logs and stderr payloads consistent with the facts.

## Skeleton: `error.py`

```python
from __future__ import annotations

from collections.abc import Mapping
from typing import Any

EX_USAGE = 64
EX_DATAERR = 65
EX_NOINPUT = 66
EX_UNAVAILABLE = 69
EX_SOFTWARE = 70
EX_IOERR = 74
EX_NOPERM = 77
EX_CONFIG = 78


class AppError(Exception):
    """Base application error returned to the CLI boundary."""

    def __init__(
        self,
        message: str,
        *,
        kind: str,
        context: Mapping[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.kind = kind
        self.context = dict(context or {})

    @property
    def exit_code(self) -> int:
        return EX_SOFTWARE


class DomainError(AppError):
    @property
    def exit_code(self) -> int:
        return EX_DATAERR


class GitAdapterError(AppError):
    @property
    def exit_code(self) -> int:
        if self.kind == "GitNotFound":
            return EX_NOINPUT
        if self.kind == "GitUnavailable":
            return EX_UNAVAILABLE
        if self.kind == "GitPermissionDenied":
            return EX_NOPERM
        return EX_IOERR


class ServiceError(AppError):
    @property
    def exit_code(self) -> int:
        return EX_SOFTWARE
```

`AppError` is an `Exception`, not a Pydantic model. Pydantic validates request and config shapes; exceptions carry failure identity, context, and chain information.

## BSD sysexits cheat sheet

| Code | Constant         | When                                    |
| ---- | ---------------- | --------------------------------------- |
| `64` | `EX_USAGE`       | Wrong CLI usage, bad flag, missing arg. |
| `65` | `EX_DATAERR`     | Input data was malformed.               |
| `66` | `EX_NOINPUT`     | Input file did not exist or unreadable. |
| `69` | `EX_UNAVAILABLE` | Required service is not available.      |
| `70` | `EX_SOFTWARE`    | Internal bug or unexpected exception.   |
| `74` | `EX_IOERR`       | I/O error during execution.             |
| `77` | `EX_NOPERM`      | Permission denied.                      |
| `78` | `EX_CONFIG`      | Config file invalid.                    |

The full matrix lives in [General — Exit codes / BSD sysexits](../../../cli-design/02-error-messages.md#exit-codes--bsd-sysexits). Do not use platform-specific `os.EX_*` constants; use documented module constants or literal ints.

## Per-layer exception examples

### Domain error

```python
class WidgetIdError(DomainError):
    @classmethod
    def too_short(cls, value: str) -> "WidgetIdError":
        return cls(
            "widget id must not be empty",
            kind="WidgetIdEmpty",
            context={"value": value},
        )


def parse_widget_id(value: str) -> str:
    cleaned = value.strip()
    if not cleaned:
        raise WidgetIdError.too_short(value)
    return cleaned
```

Domain errors describe invariant violations. They do not wrap `OSError`, subprocess failures, HTTP responses, terminal output, or config files.

### Adapter error

`GitAdapterError` is the `AppError` subclass defined in the skeleton above (its `exit_code` maps `GitNotFound -> EX_NOINPUT`, `GitUnavailable -> EX_UNAVAILABLE`, `GitPermissionDenied -> EX_NOPERM`, else `EX_IOERR`). The adapter only constructs it with the right `kind`:

```python
from pathlib import Path
import subprocess


def read_git_head(repo: Path) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise GitAdapterError(
            "git binary not found",
            kind="GitNotFound",
            context={"repo": str(repo)},
        ) from exc
    except PermissionError as exc:
        raise GitAdapterError(
            "permission denied while invoking git",
            kind="GitPermissionDenied",
            context={"repo": str(repo)},
        ) from exc
    except subprocess.CalledProcessError as exc:
        raise GitAdapterError(
            "git command failed",
            kind="GitFailed",
            context={"repo": str(repo), "stderr": exc.stderr},
        ) from exc

    return result.stdout.strip()
```

Adapters translate external failures into named application failures while preserving the original exception as the cause.

### Service error

```python
class WidgetServiceError(ServiceError):
    pass


def load_widget_report(repo: Path, widget_id: str) -> dict[str, str]:
    try:
        parsed_id = parse_widget_id(widget_id)
        head = read_git_head(repo)
    except DomainError as exc:
        raise WidgetServiceError(
            "invalid widget request",
            kind="WidgetRequestInvalid",
            context={"widget_id": widget_id},
        ) from exc
    except GitAdapterError as exc:
        raise WidgetServiceError(
            "failed to inspect widget repository",
            kind="WidgetRepositoryUnavailable",
            context={"repo": str(repo), "widget_id": widget_id},
        ) from exc

    return {"widget_id": parsed_id, "head": head}
```

Services may add use-case context, but they keep the cause chain intact and keep distinct failure kinds distinct.

## Where to raise vs. where to catch

Handlers and lower layers raise typed errors. The top-level Typer boundary is the only place that turns an application failure into stderr output and a process exit code.

Rules:

- Domain, adapter, and service code raises the most specific `AppError` subclass it owns.
- Command handlers raise typed errors or let typed service errors pass through.
- The Typer boundary catches `AppError`, renders it, logs it, and exits with `err.exit_code`.
- Unexpected exceptions are logged and mapped to `EX_SOFTWARE = 70`.
- Handlers do not call `sys.exit`, `raise typer.Exit`, or print error prose themselves.

## Printing errors at the Typer boundary

```python
from __future__ import annotations

import json
import sys
import typer


def error_payload(err: AppError) -> dict[str, object]:
    return {
        "ok": False,
        "error": {
            "kind": err.kind,
            "message": str(err),
            "context": err.context,
        },
    }


def run_with_error_boundary(call) -> None:
    try:
        call()
    except AppError as err:
        print(json.dumps(error_payload(err), separators=(",", ":")), file=sys.stderr)
        raise typer.Exit(code=err.exit_code) from err
    except Exception as err:
        payload = {
            "ok": False,
            "error": {
                "kind": "InternalError",
                "message": "internal error",
                "context": {},
            },
        }
        print(json.dumps(payload, separators=(",", ":")), file=sys.stderr)
        raise typer.Exit(code=EX_SOFTWARE) from err
```

For machine-facing CLIs, structured JSON to `stderr` is the default. Human prose belongs only behind an explicit human-UX mode. `stdout` remains reserved for successful command output. Program logs still go through the file-first logging setup in [Python — Logging](./logging-python.md).

## try/except rules

- Catch only where you can add context or translate a layer boundary.
- Always preserve causes with `raise NewError(...) from exc`.
- Never use `except Exception: pass`.
- Never collapse distinct failures into one generic `kind`.
- Unit-test the `exit_code` mapping; shell callers depend on it.

## Rules

- Every application failure has a named, stable `kind`.
- Every `AppError` maps explicitly to a BSD sysexits value.
- Error handlers preserve cause chains and do not swallow context.
- Machine-facing failures are structured on `stderr`; logs carry the same facts through the logging layer.
