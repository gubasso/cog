# Config Precedence — Python Pattern

> Prerequisite: [General — Config Precedence](../../../cli-design/03-config-precedence.md) for the canonical rule (`defaults < user file < project file < env vars < CLI flags`), XDG paths, and per-key provenance contract. This file is a worked Python implementation of that rule.

This chapter shows two Python implementations of the canonical 5-layer ladder:

1. A **manual implementation** with `platformdirs`, suitable for small CLIs (≤ ~3 knobs) or when you cannot pull in `pydantic-settings`.
2. A **`pydantic-settings` implementation** for anything larger, with the mapping back to the canonical ladder spelled out.

Both implementations:

- Use the app-prefixed env var (`MYAPP_*`), not bare `CONFIG_PATH`.
- Resolve **config files**, not directories — `<app>/config.toml`, not `<app>/`.
- Track provenance so error messages can name the layer that set a bad value.

## Pattern 1 — Manual 5-layer loader

```python
from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field, replace
from functools import lru_cache
from pathlib import Path
from typing import Any, Mapping

from platformdirs import user_config_path

APP = "myapp"
ENV_PREFIX = f"{APP.upper()}_"                   # MYAPP_
CONFIG_FILE_ENV = f"{ENV_PREFIX}CONFIG_FILE"     # explicit file override


@dataclass(frozen=True)
class Config:
    timeout_secs: int = 30
    editor: str = "vi"
    # per-key provenance: which layer set each field; populated by the loader.
    sources: Mapping[str, str] = field(default_factory=dict)


def _user_config_file() -> Path:
    # XDG: $XDG_CONFIG_HOME/myapp/config.toml or ~/.config/myapp/config.toml
    return user_config_path(APP) / "config.toml"


def _project_config_file(start: Path | None = None) -> Path | None:
    # Walk up from cwd looking for ./.myapp/config.toml; stop at the repo root or filesystem root.
    cur = (start or Path.cwd()).resolve()
    while True:
        candidate = cur / f".{APP}" / "config.toml"
        if candidate.is_file():
            return candidate
        if cur == cur.parent:
            return None
        cur = cur.parent


def _load_toml(path: Path | None) -> dict[str, Any]:
    if path is None or not path.is_file():
        return {}
    with path.open("rb") as fh:
        return tomllib.load(fh)


def _env_overrides() -> dict[str, Any]:
    out: dict[str, Any] = {}
    for raw_key, raw_val in os.environ.items():
        if not raw_key.startswith(ENV_PREFIX):
            continue
        # Skip the file-override env, that's handled separately.
        if raw_key == CONFIG_FILE_ENV:
            continue
        out[raw_key[len(ENV_PREFIX):].lower()] = raw_val
    return out


def _coerce(field_name: str, raw: Any) -> Any:
    """Coerce a raw string from env or file into the field's type. Boundary parsing only."""
    target = Config.__dataclass_fields__[field_name].type
    if target is int or target == "int":
        return int(raw)
    return raw


@lru_cache(maxsize=1)
def load_config(
    cli_overrides: Mapping[str, Any] | None = None,
    cli_config_file: Path | None = None,
) -> Config:
    """Resolve the full 5-layer ladder (see general chapter for the contract). Cache once per process.

    Python-specific note: `MYAPP_CONFIG_FILE` is an env-layer escape hatch that replaces
    the project-file source (layer 3) instead of setting a field's value.
    """
    sources: dict[str, str] = {}

    # Layer 1: defaults (Config() with no args; tracked implicitly).
    resolved: dict[str, Any] = {
        name: f.default
        for name, f in Config.__dataclass_fields__.items()
        if name != "sources"
    }
    for k in resolved:
        sources[k] = "default"

    # Layer 2: user file.
    user_path = _user_config_file()
    for k, v in _load_toml(user_path).items():
        if k in resolved:
            resolved[k] = _coerce(k, v)
            sources[k] = f"user-file:{user_path}"

    # Layer 3: project file (or explicit env override of which file to use).
    explicit_file_env = os.environ.get(CONFIG_FILE_ENV)
    project_path = (
        Path(explicit_file_env)
        if explicit_file_env
        else _project_config_file()
    )
    for k, v in _load_toml(project_path).items():
        if k in resolved:
            resolved[k] = _coerce(k, v)
            sources[k] = f"project-file:{project_path}"

    # Layer 4: env vars.
    for k, raw in _env_overrides().items():
        if k in resolved:
            resolved[k] = _coerce(k, raw)
            sources[k] = f"env:{ENV_PREFIX}{k.upper()}"

    # Layer 5: CLI flags (and an explicit CLI --config-file overrides layer 3).
    if cli_config_file is not None:
        for k, v in _load_toml(cli_config_file).items():
            if k in resolved:
                resolved[k] = _coerce(k, v)
                sources[k] = f"cli-config-file:{cli_config_file}"
    for k, v in (cli_overrides or {}).items():
        if k in resolved and v is not None:
            resolved[k] = _coerce(k, v)
            sources[k] = f"cli-flag:--{k.replace('_', '-')}"

    return Config(**resolved, sources=sources)
```

### Why this shape

- **`lru_cache(maxsize=1)`** — config is immutable per process; recomputing is wasteful and risks divergence across call sites.
- **Layers merge top-down, last write wins** — matches the canonical contract one-for-one.
- **`sources` dict** — fulfills the "name the source" requirement from cli-design/03. Errors say `timeout_secs from project-file:/repo/.myapp/config.toml was negative` instead of `invalid value`.
- **`MYAPP_CONFIG_FILE`** — separate from the rest of the env layer because it changes _which file_ the project layer reads, not the value of a field.
- **`_coerce`** — boundary parsing only. Env vars are always strings; coerce once at the boundary, never deeper.
- **Unknown keys silently ignored at the file layer (`if k in resolved`)** — flip this to a hard error if you want strict mode. The canonical chapter explicitly calls out this trade-off.

### Sample usage from a Typer command

```python
import typer
app = typer.Typer()

@app.command()
def run(
    timeout_secs: int | None = typer.Option(None, "--timeout-secs"),
    editor: str | None = typer.Option(None, "--editor"),
    config_file: Path | None = typer.Option(None, "--config-file"),
) -> None:
    cfg = load_config(
        cli_overrides={"timeout_secs": timeout_secs, "editor": editor},
        cli_config_file=config_file,
    )
    typer.echo(f"timeout_secs = {cfg.timeout_secs}  (from {cfg.sources['timeout_secs']})")
```

The Typer layer never sees a half-resolved config. It assembles overrides, hands them to `load_config`, and reads a fully-merged value.

## Pattern 2 — `pydantic-settings` for larger configs

Once you have more than ~3 knobs, switch to [`pydantic-settings`](https://docs.pydantic.dev/latest/concepts/pydantic_settings/). It gives you the ladder + validation + nested-key binding for free.

```python
from pathlib import Path
from typing import Tuple, Type

from platformdirs import user_config_path
from pydantic_settings import (
    BaseSettings,
    SettingsConfigDict,
    PydanticBaseSettingsSource,
    TomlConfigSettingsSource,
)

APP = "myapp"
USER_CONFIG = user_config_path(APP) / "config.toml"
PROJECT_CONFIG = Path.cwd() / f".{APP}" / "config.toml"   # for repo-walking, do it externally


class Config(BaseSettings):
    timeout_secs: int = 30
    editor: str = "vi"

    model_config = SettingsConfigDict(
        env_prefix=f"{APP.upper()}_",       # MYAPP_
        env_nested_delimiter="__",          # MYAPP_LOG__FORMAT -> log.format
        extra="forbid",                     # unknown keys at the file layer = error
    )

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: Type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> Tuple[PydanticBaseSettingsSource, ...]:
        # pydantic-settings calls sources high-precedence-first.
        return (
            init_settings,                                          # 5: CLI flags (pass via Config(**cli_kwargs))
            env_settings,                                           # 4: MYAPP_* env vars
            TomlConfigSettingsSource(settings_cls, PROJECT_CONFIG), # 3: project file
            TomlConfigSettingsSource(settings_cls, USER_CONFIG),    # 2: user file
            # 1: defaults are taken from the field declarations automatically.
        )
```

### Mapping back to the canonical ladder

| Canonical layer (low → high) | `pydantic-settings` source                                   |
| ---------------------------- | ------------------------------------------------------------ |
| 1. Defaults                  | Field default values on the `Config` class                   |
| 2. User file                 | `TomlConfigSettingsSource(..., USER_CONFIG)`                 |
| 3. Project file              | `TomlConfigSettingsSource(..., PROJECT_CONFIG)`              |
| 4. Env vars                  | `env_settings` (uses `env_prefix="MYAPP_"`)                  |
| 5. CLI flags                 | `init_settings` — pass CLI flag values as `Config(**kwargs)` |

The tuple returned by `settings_customise_sources` is **high-precedence-first**, which is opposite to the canonical "low to high" reading order. Keep that inversion in mind when reviewing the code; the underlying contract is unchanged.

### Provenance with `pydantic-settings`

Out of the box `pydantic-settings` does not expose per-key source provenance. Two options:

- Print the resolved config with `Config().model_dump()` plus a parallel "which source won" map that you compute alongside it (mirror the `sources` dict from Pattern 1).
- Use `pydantic-settings >= 2.5` `model_dump_with_meta()` (where available) to get source info per field; cross-check the version you depend on before relying on it.

## Diagnostics

Mirror the canonical chapter's `--print-config` recommendation:

```python
@app.command("print-config")
def print_config() -> None:
    cfg = load_config()
    for key, value in vars(cfg).items():
        if key == "sources":
            continue
        typer.echo(f"{key:20s} = {value!r}  ({cfg.sources[key]})")
```

The output is one line per key with the winning source named in parentheses. This is the human-debuggable form of the provenance dict.

## See also

- [General — Config Precedence](../../../cli-design/03-config-precedence.md) — canonical rule and XDG paths.
- [General — Logging & Output](../../../cli-design/01-logging-and-output.md) — same provenance discipline applies to log destinations.
- [`typer-patterns.md`](./typer-patterns.md) — wiring this into Typer commands.
