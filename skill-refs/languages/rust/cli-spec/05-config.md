# 05 — Config (Rust)

> Prerequisite: [General principles — Config Precedence](../../../cli-design/03-config-precedence.md) for the `CLI > env > project > user > defaults` rule and XDG paths. This chapter is the Rust implementation.

## Crate stack

| Concern               | Crate                           |
| --------------------- | ------------------------------- |
| Layered config loader | `figment` (`env`, `toml`)       |
| Serialization         | `serde` + `serde_derive`        |
| TOML format           | `toml` (transitive via figment) |
| XDG path resolution   | `directories`                   |
| UTF-8 paths           | `camino`                        |

## Rust-specific rules

(The 5-layer precedence chain, provenance contract, and XDG path semantics are canonical in the [general chapter](../../../cli-design/03-config-precedence.md). This file is the Rust implementation.)

- One `Config` struct represents the resolved, merged config. **Immutable after construction.**
- Use `figment` for the merge — its per-key provenance satisfies the general contract.
- Use `directories` for XDG paths. Never hand-roll `$XDG_CONFIG_HOME` logic.

## `src/config/mod.rs`

```rust
//! Config loading. Figment merges defaults < user < project < env < CLI.

use figment::{Figment, providers::{Env, Format, Serialized, Toml}};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    pub log_format: LogFormat,
    pub editor: String,
    pub timeout_secs: u64,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            log_format: LogFormat::Text,
            editor: std::env::var("EDITOR").unwrap_or_else(|_| "vi".into()),
            timeout_secs: 30,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogFormat { Text, Json }

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("config error: {0}")]
    Figment(#[from] figment::Error),
}

pub fn load(
    cli_overrides: &impl Serialize,
    project_config: Option<&Path>,
) -> Result<Config, ConfigError> {
    let user_path = user_config_path();
    let project_path = project_config.map(PathBuf::from);

    let mut fig = Figment::new()
        .merge(Serialized::defaults(Config::default()));

    if let Some(p) = user_path.as_ref() {
        fig = fig.merge(Toml::file(p));
    }
    if let Some(p) = project_path.as_ref() {
        fig = fig.merge(Toml::file(p));
    }

    fig.merge(Env::prefixed("APP_").split("__"))
        .merge(Serialized::defaults(cli_overrides))
        .extract::<Config>()
        .map_err(Into::into)
}

fn user_config_path() -> Option<PathBuf> {
    directories::ProjectDirs::from("com", "you", "app")
        .map(|d| d.config_dir().join("config.toml"))
}
```

`deny_unknown_fields` makes typos in TOML fail loudly — a developer who writes `timeut_secs` gets an error instead of a silently-ignored value.

## Canonical-layer → Rust mapping

| Canonical layer (general chapter) | Rust source                                                      |
| --------------------------------- | ---------------------------------------------------------------- |
| Defaults                          | `Config::default()`                                              |
| User file                         | `directories::ProjectDirs::config_dir().join("config.toml")`     |
| Project file                      | `./.<app>/config.toml` (or your convention)                      |
| Env vars                          | `Env::prefixed("APP_").split("__")` (double-underscore = nested) |
| CLI flags                         | `clap` `GlobalArgs` serialized into `figment`                    |

## XDG path resolution

```rust
use directories::ProjectDirs;

let dirs = ProjectDirs::from("com", "you", "app")
    .ok_or_else(|| anyhow::anyhow!("no home directory"))?;

let config_dir = dirs.config_dir();   // $XDG_CONFIG_HOME/app
let state_dir  = dirs.state_dir().unwrap_or(dirs.data_dir());  // $XDG_STATE_HOME/app or fallback
let cache_dir  = dirs.cache_dir();    // $XDG_CACHE_HOME/app
let data_dir   = dirs.data_dir();     // $XDG_DATA_HOME/app
```

The `state_dir()` call returns `None` on platforms without a distinct state dir (older Windows / macOS) — fall back to `data_dir()`.

## CLI overrides via clap

```rust
#[derive(Debug, clap::Parser, serde::Serialize)]
pub struct GlobalArgs {
    #[arg(long, global = true)]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub timeout_secs: Option<u64>,

    #[arg(long, value_name = "PATH", global = true)]
    #[serde(skip)]
    pub config: Option<std::path::PathBuf>,
}
```

The `Serialize` impl on the args struct lets you feed it directly into figment's `Serialized::defaults` at the top of the merge chain. `skip_serializing_if` ensures `None` values don't override real config — only the flags the user passed are merged.

## Why `figment` over `config-rs` or `confy`

- `figment` tracks per-key source provenance — errors say _"`timeout_secs` from `./app.toml` (line 12) was negative"_, not just _"invalid value"_.
- `config-rs` works but its error messages are vaguer.
- `confy` can't layer multiple files; it's fine for tiny CLIs and nothing else.

## `--print-config`

A debug subcommand that dumps the resolved value with source annotations is indispensable for support:

```rust
pub fn run(ctx: &AppContext) -> Result<(), AppError> {
    let toml = toml::to_string_pretty(&*ctx.config)?;
    println!("{toml}");
    Ok(())
}
```

For real source-tracking output, walk figment's `Metadata` directly.

## Anti-patterns specific to Rust

- Storing `Config` in a `static`. Build it in `main`; thread `&Config` (or `Arc<Config>` on `AppContext`) everywhere.
- Mutating `Config` after construction. Make every field non-public and expose getters if you must — but better: make the type `Clone` and reconstruct if you need a derived version.
- Using `dirs` instead of `directories`. `dirs` is deprecated; the maintenance moved to `directories`.
- Bringing in `serde_yaml`. The crate is unmaintained — prefer TOML, or use `serde_yaml_ng`.

## See also

- [General principle — Config Precedence](../../../cli-design/03-config-precedence.md)
- [04 — Logging (Rust)](./04-logging.md) — log destination uses the same precedence
- [07 — Dependencies (Rust)](./07-dependencies.md) — figment + directories rationale

## References

- [`figment`](https://docs.rs/figment/) · [`directories`](https://docs.rs/directories/) · [`camino`](https://docs.rs/camino/)
- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/index.html)
