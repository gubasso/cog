# 04 — Logging (Rust)

> Prerequisite: [General principles — Logging & Output](../../../cli-design/01-logging-and-output.md) for the XDG default destination, LLM-token-friendly schema, and channel matrix. Facing-category consequences follow [General — Facing category & message types](../../../cli-design/00-architecture.md#facing-category--message-types).

## Crate stack

Always:

| Concern                       | Crate                                      |
| ----------------------------- | ------------------------------------------ |
| Emission API (libs + bin)     | `tracing`                                  |
| Subscriber install (bin only) | `tracing-subscriber` (`env-filter`, `fmt`) |
| Non-blocking file sink        | `tracing-appender`                         |

Human-UX only:

| Concern                           | Crate                                       |
| --------------------------------- | ------------------------------------------- |
| Pretty error formatter (optional) | `color-eyre` (dev builds)                   |
| Color                             | `anstream`, `owo-colors`, or `nu-ansi-term` |
| Tables                            | `comfy-table`, `tabled`                     |
| Progress / spinners               | `indicatif`                                 |
| Prompts                           | `inquire`, `dialoguer`                      |

## Rules

- Libraries depend on `tracing` only. They emit events; they never install a subscriber.
- The binary depends on `tracing-subscriber` and installs **exactly one subscriber** in `main`.
- Honor `RUST_LOG`. Do not invent app-specific env vars like `APP_LOG` — users have muscle memory for `RUST_LOG`.
- The CLI exposes `-v` / `-vv` / `-vvv` for `info` / `debug` / `trace`. `RUST_LOG` overrides if set.
- File destination by default: `$XDG_STATE_HOME/<app>/<app>.log` via `directories::ProjectDirs::state_dir()`. Resolve the path in `main` before installing the subscriber.
- File-first logging is universal. Default `mirror_stderr` to `false` for machine-facing CLIs; for human-facing CLIs, set it from `--log-stderr`, verbosity policy, or config.

## `src/logging.rs`

```rust
//! tracing-subscriber installation. Called once from `main`.

use std::path::Path;
use tracing_appender::non_blocking::WorkerGuard;
use tracing_subscriber::{EnvFilter, fmt, layer::SubscriberExt, util::SubscriberInitExt};

pub struct LogInit {
    /// Hold this until shutdown to flush the file sink.
    pub _guard: WorkerGuard,
}

pub fn init(verbosity: u8, log_file: &Path, mirror_stderr: bool) -> anyhow::Result<LogInit> {
    let default_directive = match verbosity {
        0 => "warn",
        1 => "info",
        2 => "debug",
        _ => "trace",
    };
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(default_directive));

    // File sink: always on, non-blocking.
    let (file_writer, guard) = {
        let dir = log_file.parent().unwrap_or(Path::new("."));
        let name = log_file.file_name().unwrap_or_default();
        let appender = tracing_appender::rolling::never(dir, name);
        tracing_appender::non_blocking(appender)
    };

    let registry = tracing_subscriber::registry().with(filter);

    let registry = registry.with(
        fmt::layer()
            .with_writer(file_writer)
            .with_ansi(false)              // never ANSI in the file
            .with_target(true)
            .json(),                       // structured, LLM-friendly
    );

    if mirror_stderr {
        registry
            .with(fmt::layer().with_writer(std::io::stderr).with_target(false))
            .try_init()
            .map_err(|e| anyhow::anyhow!("install tracing subscriber: {e}"))?;
    } else {
        registry
            .try_init()
            .map_err(|e| anyhow::anyhow!("install tracing subscriber: {e}"))?;
    }

    Ok(LogInit { _guard: guard })
}
```

Hold the returned `LogInit` for the lifetime of the program so the appender's background worker flushes on shutdown.

The minimum level mapping is `error!`, `warn!`, `info!`, and `debug!`; `trace!` is optional for deep internals.

### Variant: human-readable text format

For the file sink, prefer JSON (LLM-friendly). For the optional terminal mirror, keep the default pretty formatter, _but_ disable colors if `NO_COLOR` is set:

```rust
fmt::layer()
    .with_writer(std::io::stderr)
    .with_ansi(std::env::var("NO_COLOR").is_err())
    .with_target(false)
```

### File rotation

Use `tracing_appender::rolling::Builder` for size- or time-based rotation:

```rust
let appender = tracing_appender::rolling::Builder::new()
    .rotation(tracing_appender::rolling::Rotation::DAILY)
    .filename_prefix(name)
    .max_log_files(7)
    .build(dir)?;
```

For most CLIs, "never rotate but truncate at N MB" is enough — wire that with a one-shot truncation in `main` before installing.

## What to log at each level

- `error!` — the operation failed in a way the user needs to know about. Always paired with a returned `Err`.
- `warn!` — recoverable problem; we proceeded but the user might care.
- `info!` — high-level progress (e.g. "synced 12 widgets in 1.2s"). One per top-level operation.
- `debug!` — call boundaries with arg summaries. Read by developers, not users.
- `trace!` — deep internals, hot loops. Off by default even at `-vvv` unless explicitly filtered in.

## Spans

Open a span per top-level operation and per adapter call:

```rust
let _span = tracing::info_span!("widget.sync", id = %id).entered();
```

`AppContext` carries the root span; `commands/*` open child spans named `<command>.<phase>`.

Prefer the **exit-only** emission style: open a span, do work, log a single `info` record on exit with `dur_ms` and `status`. Avoid emitting `enter` + `exit` pairs — they double token count for LLM consumers.

## Anti-patterns specific to Rust

- Calling `tracing_subscriber::fmt::init()` (the convenience installer) without an `EnvFilter`. It ignores `RUST_LOG`.
- Installing the subscriber inside a library. Libraries emit only.
- Using `env_logger` or `log` directly. Both lack span support and structured fields.
- Color in the JSON layer (`with_ansi(true)`). Bloats the file and confuses parsers.
- Forgetting the `_guard` — the appender worker exits before the buffer flushes, and tail-end logs disappear.

## See also

- [General principle — Logging & Output](../../../cli-design/01-logging-and-output.md)
- [05 — Config (Rust)](./05-config.md) — log destination resolution
- [03 — Error Handling](./03-error-handling.md) — how errors flow into log records (`err.kind`, `err.msg`)

## References

- [`tracing`](https://docs.rs/tracing/) · [`tracing-subscriber`](https://docs.rs/tracing-subscriber/) · [`tracing-appender`](https://docs.rs/tracing-appender/)
- [`directories::ProjectDirs::state_dir`](https://docs.rs/directories/) — XDG_STATE_HOME resolution
