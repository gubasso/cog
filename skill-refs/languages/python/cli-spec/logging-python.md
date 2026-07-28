# Python Logging

Python-specific logging setup for CLI tools using `structlog`.

Facing-category consequences follow [General — Facing category & message types](../../../cli-design/00-architecture.md#facing-category--message-types).

## Stack

| Concern              | Library                 |
| -------------------- | ----------------------- |
| Structured records   | `structlog`             |
| XDG state directory  | `platformdirs`          |
| File sink            | `logging.FileHandler`   |
| Optional stderr sink | `logging.StreamHandler` |

## Rules

- Default log file: `${XDG_STATE_HOME:-$HOME/.local/state}/<app>/<app>.log`.
- Default records are JSON, one line per event.
- Levels include at least `error`, `warn`, `info`, and `debug`; `trace` can be modeled as verbose `debug` or a project-specific lower level if needed.
- `mirror_stderr` is explicit opt-in. Default it to `false` for machine-facing CLIs; set it from `--log-stderr`, verbosity policy, or config for human-facing CLIs.

## Worked Example

```python
from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

import structlog
from platformdirs import user_state_dir


def default_log_path(app_name: str) -> Path:
    state_home = os.environ.get("XDG_STATE_HOME")
    if state_home:
        return Path(state_home) / app_name / f"{app_name}.log"
    return Path(user_state_dir(app_name, appauthor=False)) / f"{app_name}.log"


def configure_logging(
    app_name: str,
    *,
    level: str = "INFO",
    mirror_stderr: bool = False,
    log_file: Path | None = None,
) -> Path:
    path = log_file or default_log_path(app_name)
    path.parent.mkdir(parents=True, exist_ok=True)

    handlers: list[logging.Handler] = [
        logging.FileHandler(path, encoding="utf-8"),
    ]
    if mirror_stderr:
        handlers.append(logging.StreamHandler(sys.stderr))

    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        handlers=handlers,
        format="%(message)s",
        force=True,
    )

    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.TimeStamper(fmt="iso", utc=True, key="ts"),
            structlog.stdlib.add_log_level,
            structlog.processors.EventRenamer("msg"),
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            getattr(logging, level.upper(), logging.INFO)
        ),
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )

    return path
```

Usage from a Typer entry point:

```python
import typer
import structlog

app = typer.Typer()


@app.callback()
def main(
    verbose: int = typer.Option(0, "-v", count=True),
    log_stderr: bool = typer.Option(False, "--log-stderr"),
) -> None:
    level = "WARNING"
    if verbose == 1:
        level = "INFO"
    elif verbose >= 2:
        level = "DEBUG"
    configure_logging("my-cli", level=level, mirror_stderr=log_stderr)


@app.command()
def sync() -> None:
    log = structlog.get_logger(__name__)
    log.info("sync.complete", op="sync", status="ok", count=12)
    typer.echo('{"ok": true, "count": 12}')
```

The command output stays separate from log records. Tests should set `XDG_STATE_HOME` to a temporary directory and assert that the log file contains newline-delimited JSON records.
