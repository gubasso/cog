# 03 — Config Precedence

Every configurable value comes from one of five sources. They merge in a fixed precedence order. The
loader tracks **which source set which value**, so error messages can name the file and line.

## The precedence rule

From **lowest** to **highest** precedence (later sources override earlier ones):

```
defaults  <  user file  <  project file  <  env vars  <  CLI flags
```

Compact form: **`cli > env > project > user > defaults`**.

This is the standard followed by AWS CLI, OCI CLI, kubectl, terraform, gcloud, and effectively every
well-designed CLI tool. Reuse it; don't reinvent.

### Why this order

| Source                                               | Why this position                                                                            |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **Defaults** (lowest)                                | Hard-coded in the binary. Always present. Cannot be edited at runtime.                       |
| **User file** (`$XDG_CONFIG_HOME/<app>/config.toml`) | Personal preferences. Persists across sessions.                                              |
| **Project file** (`./.<app>/config.toml` or similar) | Per-repo / per-directory overrides. Project beats user because you opted into the project.   |
| **Env vars**                                         | Set for one shell session or one process invocation. More specific than the persistent file. |
| **CLI flags** (highest)                              | A one-off override for this single invocation. Always wins.                                  |

## Implementation pattern (language-agnostic)

```
1. Construct a default `Config` value.
2. Merge the user file (if it exists). Missing file = no-op, not error.
3. Merge the project file (if it exists). Same.
4. Merge env vars (prefixed, e.g. `<APP>_*`).
5. Merge CLI flags last.
6. Validate the resolved value. Fail with a clear `where + why` message.
```

The merge must:

- Preserve **per-key source provenance** so errors say _"`timeout_secs` from `./app.toml` line 12
  was negative"_ instead of _"invalid value"_.
- Reject **unknown keys** at the file layer — silent acceptance hides typos. (Trade-off: this makes
  forward-compat configs harder. Surface it via a `--config-strict` toggle if you need both.)
- Treat env vars and CLI flags as having a known schema; ignore unknown env vars (don't crash on
  `LANG=en_US`).

## XDG paths

Use the XDG Base Directory spec everywhere; do not hand-roll `$HOME/.<app>/`.

| Concern               | XDG var           | Default                 |
| --------------------- | ----------------- | ----------------------- |
| Config                | `XDG_CONFIG_HOME` | `~/.config/<app>/`      |
| Data                  | `XDG_DATA_HOME`   | `~/.local/share/<app>/` |
| State (logs, history) | `XDG_STATE_HOME`  | `~/.local/state/<app>/` |
| Cache                 | `XDG_CACHE_HOME`  | `~/.cache/<app>/`       |
| Runtime sockets       | `XDG_RUNTIME_DIR` | `/run/user/$UID/`       |

Use your language's XDG library (`directories` in Rust, `platformdirs` in Python, `xdg` in Go,
`XDG_*` env-var probes in Bash). Don't reimplement the lookup.

References:
[XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/index.html).

## Env-var conventions

- Prefix all app-specific env vars with `<APP>_` (uppercased).
- Use `<APP>_*` for top-level keys, `<APP>_NESTED__KEY` (double underscore) for nested keys to avoid
  collisions with naturally underscored key names.
- Example: `MYAPP_TIMEOUT_SECS=60`, `MYAPP_LOG__FORMAT=json`.
- For logging level, reuse the ecosystem standard (`RUST_LOG`, `PYTHONLOGLEVEL`) — do not invent
  `<APP>_LOG`. Users have muscle memory.
- For paths overrides, support both `<APP>_CONFIG_FILE` and the standard XDG vars (`XDG_CONFIG_HOME`
  is a base directory; your `<APP>_CONFIG_FILE` is a full path to a specific file).

## Schema discipline

The resolved `Config` is **immutable after construction**. It is built in `main` (before
`AppContext`), then handed to `AppContext` and never modified.

- **Config holds user-facing knobs.** What the user can tune.
- **Config does NOT hold domain invariants.** Those live in `domain/`. (E.g. "widget IDs must be
  1..=64 chars" is a domain invariant, not a config knob.)
- **Config is serializable both ways.** It deserializes from the file/env layers and can be
  re-serialized for a `--print-config` debug subcommand.

## Loader-library choices

| Language | Recommended                                                                         | Why                                                                               |
| -------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Rust     | [`figment`](https://docs.rs/figment/)                                               | Per-key provenance; clean provider model matching the 5-layer chain.              |
| Python   | [`pydantic-settings`](https://docs.pydantic.dev/latest/concepts/pydantic_settings/) | Layered loading + validation in one. Or: hand-roll with `lru_cache` (small CLIs). |
| Go       | [`viper`](https://github.com/spf13/viper)                                           | Mature, but verbose. Lightweight: stdlib `flag` + `os.Getenv` + `encoding/toml`.  |
| Bash     | Sourced env-file + `${VAR:-default}` fallback ladder                                | Keep it simple.                                                                   |

Skip:

- `confy` in Rust — can't layer multiple files.
- Raw `os.environ` walks in Python without a schema — typo-prone.
- Hand-rolled JSON parsers for config in any language — use the ecosystem.

### Why provenance matters

A loader that can answer _"where did this value come from?"_ lets your errors say:

```
config: invalid value
  where: /home/user/.config/app/config.toml (line 12, [defaults] timeout_secs)
  why:   timeout_secs must be a positive integer, got -1
  hint:  set timeout_secs = 30 and retry
```

A loader that can't say which file/key was responsible forces you into messages like _"some config
value was invalid"_, which costs the user a debugging session.

## Example layouts

### Single-file config

```toml
# ~/.config/myapp/config.toml

editor       = "nvim"
timeout_secs = 30

[log]
format = "text"
file   = "~/.local/state/myapp/myapp.log"
```

### Per-repo override

```toml
# ./.myapp/config.toml — wins over the user file for this directory
timeout_secs = 60
```

### Env override (one invocation)

```sh
MYAPP_TIMEOUT_SECS=90 myapp sync
```

### CLI override (this single call)

```sh
myapp sync --timeout-secs 5
```

Order of precedence (high → low): the flag wins; the env wins over files; project file wins over
user file; user file wins over default.

## Minimal Python loader pattern

```python
from functools import lru_cache
from pathlib import Path
from typing import Optional
import os

DEFAULT_USER_CONFIG_PATH = Path("~/.config/myapp/config.toml").expanduser()

@lru_cache(maxsize=1)
def get_config_path(cli_config_path: Optional[Path] = None) -> Path:
    env = os.getenv("MYAPP_CONFIG_FILE")
    env_path = Path(env) if env else None

    for path in (cli_config_path, env_path, DEFAULT_USER_CONFIG_PATH):
        if path and path.expanduser().is_file():
            return path.expanduser()

    raise FileNotFoundError(
        "No configuration file found. Checked: "
        f"CLI={cli_config_path}, env={env_path}, default={DEFAULT_USER_CONFIG_PATH}"
    )
```

The pattern: a single fallback chain, an `lru_cache` for the duration of the process, and an error
that names every location checked. This generalizes to most languages.

For full Python guidance see
[`python/cli-spec/config-precedence-python.md`](../../languages/python/cli-spec/config-precedence-python.md).

## Anti-patterns

- **Implicit precedence**: different keys with different ordering rules ("for `timeout`, env wins;
  for `editor`, file wins"). Pick one global rule and apply it to every key.
- **Mutating config at runtime**: makes behavior unrepeatable. Resolve once at startup.
- **Mixing config and CLI parser definitions**: keep them separate. The CLI parser knows about
  flags; the config knows about persistent settings.
- **No way to inspect the resolved config**: add a `--print-config` (or `config show`) subcommand
  that dumps the resolved value with source annotations. Indispensable for support.
- **Silent unknown-key acceptance** at the file layer. Typos like `timeut_secs = 30` should fail
  loudly.
- **App-specific env vars for ecosystem concerns**: don't invent `MYAPP_LOG_LEVEL` when
  `RUST_LOG`/`PYTHONLOGLEVEL` already exists.
- **Reading from `~/.<app>/`** instead of XDG: surprises users and breaks tooling that scans XDG
  dirs.

## References

- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/index.html)
- AWS CLI precedence:
  [Configuration and credential file settings](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)
- OCI CLI configuration:
  [SDK and CLI configuration file](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/sdkconfig.htm)
- `figment` (Rust): per-key source tracking — [docs](https://docs.rs/figment/)
- `pydantic-settings` (Python): [docs](https://docs.pydantic.dev/latest/concepts/pydantic_settings/)

## See also

- [00 — Architecture](00-architecture.md) — where `config/` and `context.rs` sit in the tree.
- [01 — Logging & Output](01-logging-and-output.md) — log-file path resolution uses the same
  precedence.
- Language-specific: [`rust/cli-spec/05-config.md`](../../languages/rust/cli-spec/05-config.md).
