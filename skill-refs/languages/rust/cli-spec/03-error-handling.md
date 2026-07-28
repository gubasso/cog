# 03 — Error Handling (Rust)

> Prerequisite: [General principles — Error Messages](../../../cli-design/02-error-messages.md) for the four-part anatomy (what/where/why/hint), stable `err.kind`, BSD sysexits, and audience matrix. This chapter is the Rust implementation using `thiserror` + `anyhow`.

`thiserror` per layer for typed errors, `anyhow` only at the binary boundary, one top-level `AppError` enum with `exit_code()` mapped to BSD sysexits.

## The layer table

| Layer       | Returns                             | Crate                                  | Rule                                                                                                                           |
| ----------- | ----------------------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `domain/`   | `enum DomainError` per module       | `thiserror`                            | Invariant violations only. No I/O variants.                                                                                    |
| `adapters/` | `enum <Sys>AdapterError`            | `thiserror` + `#[from] std::io::Error` | One error type per adapter. Wrap upstream errors with `#[source]`.                                                             |
| `services/` | `enum ServiceError`                 | `thiserror`                            | `#[from]` domain + adapter errors. Do NOT recursively `#[from]` peer service errors.                                           |
| `commands/` | `Result<(), AppError>`              | `thiserror`                            | `AppError` `#[from]`s every service and `std::io::Error`. Plus an `Other(#[from] anyhow::Error)` arm for ad-hoc `.context(…)`. |
| `main`      | `Result<(), AppError>` → `ExitCode` | `anyhow` allowed                       | `AppError::exit_code() -> u8`. Unit-test the matrix.                                                                           |

## Why both `thiserror` and `anyhow`

- `thiserror` builds **named, matchable** errors. Code that needs to react to a specific failure can `match` on the variant.
- `anyhow` is for **opaque, context-rich** errors at the application boundary — you don't care which exact variant fired, you care about printing a useful chain to the user.

Inside the crate, every error has a name. At the boundary, you optionally lose the name in exchange for cheap `.context("while doing X")` chains.

**Never** return `anyhow::Error` from a library crate or a public API. Inside a binary's `commands/` and `main`, it's fine — and the typed `AppError::Other(#[from] anyhow::Error)` variant lets you mix the two without ceremony.

## Skeleton: `src/error.rs`

```rust
//! Crate-level error type and exit-code mapping.

use thiserror::Error;

/// Top-level error type returned from `commands::*::run`.
#[derive(Debug, Error)]
pub enum AppError {
    #[error("usage: {0}")]
    Usage(String),

    #[error("config: {0}")]
    Config(#[from] crate::config::ConfigError),

    #[error("io: {0}")]
    Io(#[from] std::io::Error),

    #[error(transparent)]
    Domain(#[from] crate::domain::DomainError),

    #[error(transparent)]
    Adapter(#[from] crate::adapters::AdapterError),

    #[error(transparent)]
    Service(#[from] crate::services::ServiceError),

    #[error(transparent)]
    Other(#[from] anyhow::Error),
}

impl AppError {
    /// Map to a BSD sysexits exit code. See sysexits(3).
    pub fn exit_code(&self) -> u8 {
        match self {
            AppError::Usage(_)                                 => 64, // EX_USAGE
            AppError::Config(_)                                => 78, // EX_CONFIG
            AppError::Domain(_)                                => 65, // EX_DATAERR
            AppError::Adapter(crate::adapters::AdapterError::NotFound) => 66, // EX_NOINPUT
            AppError::Adapter(crate::adapters::AdapterError::Unavailable) => 69, // EX_UNAVAILABLE
            AppError::Adapter(_)                               => 74, // EX_IOERR
            AppError::Service(_)                               => 70, // EX_SOFTWARE
            AppError::Io(e) if e.kind() == std::io::ErrorKind::NotFound        => 66,
            AppError::Io(e) if e.kind() == std::io::ErrorKind::PermissionDenied => 77, // EX_NOPERM
            AppError::Io(_)                                    => 74,
            AppError::Other(_)                                 => 70,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn usage_is_64() {
        assert_eq!(AppError::Usage("bad flag".into()).exit_code(), 64);
    }

    #[test]
    fn permission_denied_is_77() {
        let e = AppError::Io(std::io::Error::from(std::io::ErrorKind::PermissionDenied));
        assert_eq!(e.exit_code(), 77);
    }
    // ... one test per arm
}
```

The matrix test isn't optional. Treat exit codes as part of the user-facing API and lock them down.

## BSD sysexits cheat sheet

The full code/constant/when matrix lives in [`cli-design/02-error-messages.md#exit-codes--bsd-sysexits`](../../../cli-design/02-error-messages.md#exit-codes--bsd-sysexits). Map every `AppError` variant onto a constant from that table.

Don't use codes outside that set without writing them down. Shell scripts read your exit code.

## Per-layer error type examples

### Domain error (`src/domain/widget.rs`)

```rust
#[derive(Debug, thiserror::Error)]
pub enum DomainError {
    #[error("widget id must be 1..=64 chars, got {len}")]
    IdLength { len: usize },

    #[error("widget id contains invalid char: {0:?}")]
    IdInvalidChar(char),

    #[error("widget cannot transition from {from:?} to {to:?}")]
    InvalidTransition { from: WidgetState, to: WidgetState },
}
```

Pure: no `std::io::Error`, no `reqwest::Error`. Only states the domain cares about.

### Adapter error (`src/adapters/git.rs`)

```rust
#[derive(Debug, thiserror::Error)]
pub enum GitError {
    #[error("git binary not found in PATH")]
    NotFound,

    #[error("git invocation failed: {0}")]
    Spawn(#[from] std::io::Error),

    #[error("git exited {code}: {stderr}")]
    Failed { code: i32, stderr: String },
}
```

Wraps the external system's failure modes. One enum per adapter family.

### Service error (`src/services/widget.rs`)

```rust
#[derive(Debug, thiserror::Error)]
pub enum WidgetServiceError {
    #[error(transparent)]
    Domain(#[from] crate::domain::widget::DomainError),

    #[error(transparent)]
    Git(#[from] crate::adapters::git::GitError),

    #[error("widget {0} is locked by another process")]
    Locked(crate::domain::widget::WidgetId),
}
```

Composes domain and adapter errors. **Do not** add `#[from]` arms for peer services (e.g. `OtherServiceError`) — recursive `#[from]` graphs cause ambiguous `?` inference and force you to disambiguate at call sites. Instead, lift shared infrastructure into adapters or domain.

## The `Other(#[from] anyhow::Error)` arm

Inside `commands/`, sometimes you want `.context("while loading user prefs")` on a one-off call without inventing a whole error variant. Add this arm to `AppError`:

```rust
#[error(transparent)]
Other(#[from] anyhow::Error),
```

Now this works:

```rust
use anyhow::Context;
let prefs = std::fs::read_to_string(&path)
    .with_context(|| format!("loading prefs from {path:?}"))?;  // -> AppError via #[from]
```

This is `riptask`'s approach (`src/error.rs:48-49`) and it's a good escape hatch.

## Printing errors in `main`

```rust
fn main() -> std::process::ExitCode {
    let cli = app_template::cli::Cli::parse();
    let ctx = match app_template::context::AppContext::new(&cli) {
        Ok(c) => c,
        Err(e) => {
            eprint_error(&e);
            return std::process::ExitCode::from(e.exit_code());
        }
    };
    if let Err(e) = app_template::dispatch(&ctx, cli) {
        eprint_error(&e);
        return std::process::ExitCode::from(e.exit_code());
    }
    std::process::ExitCode::SUCCESS
}

fn eprint_error(e: &app_template::error::AppError) {
    eprintln!("app: {e}");
    let mut source = std::error::Error::source(e);
    while let Some(cause) = source {
        eprintln!("  caused by: {cause}");
        source = cause.source();
    }
}
```

The chain walk surfaces `#[source]` and `#[from]` causes. For prettier output in dev builds, gate `color-eyre` behind a feature flag.

## Rules

- No `panic!`, `.unwrap()`, `.expect()` outside `main`, tests, build scripts, and `LazyLock` initializers.
- No catch-all `_ => 1` in `exit_code()`. Map every variant explicitly.
- Every public function returning `Result` documents the error variants it can produce.
- Don't wrap `String` errors. If you find yourself reaching for `anyhow!("...")`, ask whether a named variant would be clearer — for one-offs at the binary edge, `anyhow!` is fine; in libs, name it.
