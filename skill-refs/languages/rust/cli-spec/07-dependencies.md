# 07 — Dependencies (Rust)

> Prerequisite: the canonical principles each crate implements live in [`cli-design/`](../../../cli-design/) — specifically [`01-logging-and-output`](../../../cli-design/01-logging-and-output.md) (`tracing`, `tracing-subscriber`, `tracing-appender`), [`02-error-messages`](../../../cli-design/02-error-messages.md) (`thiserror`, `anyhow`), [`03-config-precedence`](../../../cli-design/03-config-precedence.md) (`figment`, `directories`), and [`08-testing-and-quality`](../../../cli-design/08-testing-and-quality/testing-strategy.md) (`assert_cmd`, `insta`, `tempfile`, `nextest`). This chapter is the curated default crate list with one-line justifications. Facing-category consequences follow [General — Facing category & message types](../../../cli-design/00-architecture.md#facing-category--message-types).

Opinionated default dependency list. Each entry has a one-line justification and a "skip if" condition. Pick deliberately; resist the urge to add "useful-looking" crates without a concrete need.

## Adding dependencies

**Manage every dependency through Cargo's CLI — never hand-edit dependency names, versions, or features in `Cargo.toml`.**

- Add or change a crate with `cargo add <crate>` (e.g. `cargo add clap --features derive,env,wrap_help`). `cargo add` fetches the latest SemVer-compatible version, resolves the whole graph, writes the entry into `Cargo.toml`, and updates `Cargo.lock` in one step.
- Remove a crate with `cargo remove <crate>`.
- Bump the lockfile with `cargo update` — deliberately, and read the changelog first.
- Add a dev-dependency with `cargo add --dev <crate>`; add a feature to a crate you already depend on with `cargo add <crate> --features <feat>`.
- Do **not** type version strings or feature lists into `Cargo.toml` by hand. Hand-edits drift from the resolver, skip the lockfile update, and pin stale versions. Agents and contributors change dependencies only through these commands.
- Commit `Cargo.lock` for binaries (not for libraries); `cargo add`/`cargo update` keep it in sync.

The [pinning policy](#pinning-policy) below still governs the resulting entries: majors in `Cargo.toml`, exact versions in `Cargo.lock`.

## Runtime defaults

Always:

| Crate                | Features                     | Why                                                                                           | Skip if                                                                            |
| -------------------- | ---------------------------- | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `clap`               | `derive`, `env`, `wrap_help` | Standard parser; `env` lets flags fall back to env vars; `wrap_help` makes `--help` readable. | Never.                                                                             |
| `clap_complete`      | —                            | Generates shell completions via a subcommand.                                                 | The CLI is dev-internal and shell completions aren't needed.                       |
| `clap_mangen`        | —                            | Generates man pages; expose them through a subcommand when useful.                            | The CLI is dev-internal and man pages aren't needed.                               |
| `anyhow`             | —                            | Ad-hoc context-rich errors at the binary edge.                                                | You're writing a pure library (use only `thiserror`).                              |
| `thiserror`          | —                            | Typed error enums in `domain/`, `adapters/`, `services/`, `error.rs`.                         | Never.                                                                             |
| `tracing`            | —                            | Structured logging primitive. Emitted everywhere.                                             | Never.                                                                             |
| `tracing-subscriber` | `env-filter`, `fmt`          | Installs the subscriber in `main`.                                                            | Never (in a binary).                                                               |
| `tracing-appender`   | —                            | Non-blocking file sink.                                                                       | Only for a throwaway dev-internal CLI.                                             |
| `serde`              | `derive`                     | Universal serialization.                                                                      | Never.                                                                             |
| `serde_json`         | —                            | JSON I/O.                                                                                     | No JSON I/O anywhere.                                                              |
| `toml`               | —                            | Config file parsing (via figment).                                                            | No config files.                                                                   |
| `figment`            | `env`, `toml`                | Layered config with source provenance.                                                        | Trivial single-file config (use `toml` + `serde` directly).                        |
| `directories`        | —                            | XDG/Windows/macOS config-path resolution.                                                     | No cross-platform config paths needed.                                             |
| `camino`             | `serde1`                     | UTF-8-only paths; kills `Path::to_string_lossy()` boilerplate.                                | The CLI only operates on user-supplied paths it never round-trips through strings. |
| `tokio`              | `rt`, `macros`               | Single current-thread runtime for async.                                                      | Fully sync CLI.                                                                    |

Human-UX only:

| Crate                                    | Why                                                      |
| ---------------------------------------- | -------------------------------------------------------- |
| `anstream`, `owo-colors`, `nu-ansi-term` | Color handling through established terminal conventions. |
| `comfy-table`, `tabled`                  | Human-readable table rendering.                          |
| `indicatif`                              | Progress bars and spinners.                              |
| `inquire`, `dialoguer`                   | Interactive prompts.                                     |

## Dev-dependencies

| Crate        | Features | Why                                    | Skip if                                      |
| ------------ | -------- | -------------------------------------- | -------------------------------------------- |
| `assert_cmd` | —        | Process-level CLI tests.               | No integration tests (you should have them). |
| `predicates` | —        | Assertion helpers for `assert_cmd`.    | Same.                                        |
| `insta`      | `yaml`   | Snapshot tests for structured output.  | No structured output to snapshot.            |
| `tempfile`   | —        | Isolated temp dirs per test.           | Same.                                        |
| `trybuild`   | —        | Compile-fail tests for typestate APIs. | No typestate.                                |

## Conditional adds

Add only when a specific concrete need arises.

| Crate                               | When                                                                                                                                  |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `color-eyre`                        | Pretty `anyhow`-style error chains in dev builds. Gate behind a `dev` feature; skip in release for binary size.                       |
| `chrono` or `time`                  | Real date/time handling. Prefer `time` (smaller, no globally-mutable timezone state). Use `chrono` only if dep tree already pulls it. |
| `glob`                              | Glob pattern matching (e.g. `*.txt`).                                                                                                 |
| `regex`                             | Regular expressions. Heavyweight; consider whether `str::contains` suffices first.                                                    |
| `reqwest`                           | HTTP client. Use `rustls` backend, not `native-tls`, to keep static builds working.                                                   |
| `rusqlite` or `sqlx`                | SQL persistence. Pick `sqlx` only if you need async or compile-time query checking.                                                   |
| `crossterm`                         | Human-UX TUI input handling. Reach for it only if you need raw mode.                                                                  |
| `indicatif`                         | Human-UX progress bars.                                                                                                               |
| `dialoguer`                         | Human-UX interactive prompts.                                                                                                         |
| `dirs`                              | Old XDG helper. **Don't use**; `directories` supersedes it.                                                                           |
| `walkdir`                           | Filesystem traversal with depth/symlink controls.                                                                                     |
| `ignore`                            | `.gitignore`-aware traversal. Bigger than `walkdir`; use only if you actually need gitignore semantics.                               |
| `which`                             | Locate executables on PATH.                                                                                                           |
| `tempfile` (runtime, not dev)       | If your CLI creates real tempfiles (not just tests).                                                                                  |
| `parking_lot`                       | Faster mutex/rwlock than std. Only if profiling shows lock contention.                                                                |
| `rayon`                             | Data parallelism. Use only when the workload is genuinely parallelizable and the CLI isn't I/O-bound.                                 |
| `once_cell` / `std::sync::LazyLock` | Prefer std `LazyLock` (1.80+) over `once_cell::sync::Lazy` for new code.                                                              |

## Avoid by default

Deprecated, dead, or superseded:

| Crate                           | Why avoid                              | Use instead                   |
| ------------------------------- | -------------------------------------- | ----------------------------- |
| `env_logger`                    | Old; doesn't integrate with spans.     | `tracing-subscriber`.         |
| `log` (directly)                | Lacks structured fields and spans.     | `tracing`.                    |
| `structopt`                     | Merged into clap; deprecated.          | `clap` derive.                |
| `failure`                       | Unmaintained.                          | `thiserror` + `anyhow`.       |
| `error-chain`                   | Unmaintained.                          | Same.                         |
| `confy`                         | Can't layer multiple files.            | `figment`.                    |
| `dirs`                          | Maintenance moved to `directories`.    | `directories`.                |
| `chrono` (if you have a choice) | Global timezone state, larger surface. | `time`.                       |
| `lazy_static`                   | Older, macro-based.                    | `std::sync::LazyLock`.        |
| `rustc-serialize`               | Pre-`serde`.                           | `serde`.                      |
| `serde_yaml`                    | Unmaintained.                          | `serde_yaml_ng` or skip YAML. |

## Cargo.toml skeleton

Hand-author only the non-dependency tables — `[package]`, `[[bin]]`, `[profile.release]`. Everything under `[dependencies]`/`[dev-dependencies]` is installed with `cargo add` (see [Adding dependencies](#adding-dependencies)); never type crate versions in by hand.

```toml
[package]
name        = "app-template"
version     = "0.1.0"
edition     = "2024"
rust-version = "1.85"
license     = "MIT OR Apache-2.0"
description = "One-line description."
repository  = "https://github.com/you/app-template"

[[bin]]
name = "app"
path = "src/main.rs"

[profile.release]
lto           = "thin"
codegen-units = 1
strip         = "symbols"
```

Install the default runtime stack — each command resolves the latest SemVer-compatible version, writes it into `[dependencies]`, and updates `Cargo.lock`:

```sh
cargo add clap --features derive,env,wrap_help
cargo add clap_complete clap_mangen
cargo add anyhow thiserror
cargo add tracing
cargo add tracing-subscriber --features env-filter,fmt
cargo add tracing-appender
cargo add serde --features derive
cargo add serde_json toml
cargo add figment --features env,toml
cargo add directories
cargo add camino --features serde1
cargo add tokio --features rt,macros

# Human-UX-only additions (add when the CLI is human-facing):
cargo add anstream owo-colors comfy-table indicatif inquire

# Dev-dependencies:
cargo add --dev assert_cmd predicates tempfile
cargo add --dev insta --features yaml
```

The resolved `[dependencies]` block will look roughly like the following. **Illustrative only — install via `cargo add`; do not hand-copy these versions.** As of 2026-07 the current majors are `thiserror` 2, `toml` 1 (TOML spec 1.1), and `anstream` 1.0:

```toml
[dependencies]
clap                = { version = "4", features = ["derive", "env", "wrap_help"] }
clap_complete       = "4"
clap_mangen         = "0.2"
anyhow              = "1"
thiserror           = "2"
tracing             = "0.1"
tracing-subscriber  = { version = "0.3", features = ["env-filter", "fmt"] }
tracing-appender    = "0.2"
serde               = { version = "1", features = ["derive"] }
serde_json          = "1"
toml                = "1"
figment             = { version = "0.10", features = ["env", "toml"] }
directories         = "5"
camino              = { version = "1", features = ["serde1"] }
tokio               = { version = "1", features = ["rt", "macros"] }

# Human-UX-only additions:
# anstream      = "1"
# owo-colors    = "4"
# comfy-table   = "7"
# indicatif     = "0.17"
# inquire       = "0.7"

[dev-dependencies]
assert_cmd  = "2"
predicates  = "3"
insta       = { version = "1", features = ["yaml"] }
tempfile    = "3"
```

Trim aggressively for very small CLIs (drop `tokio`, `figment`, `directories` if you don't need them). Add to taste from the conditional list above.

## Pinning policy

- Pin to **major versions** in `Cargo.toml` (`"4"`, `"0.3"`). Let `Cargo.lock` pin exact versions.
- Commit `Cargo.lock` for binaries. Don't for libraries.
- Run `cargo update` deliberately, not as a default `just` task. Read the changelog.
- Use `cargo deny` (configured in `deny.toml`) to enforce a license allowlist and ban yanked or vulnerable versions.

## Justification: figment over config-rs

Both work. Pick figment because:

- It tracks per-key source provenance. Errors say _"`timeout` in `./app.toml` (line 12) was negative"_ instead of _"invalid config"_.
- Its provider model maps cleanly onto our layered precedence (defaults → user → project → env → CLI).
- `config-rs` requires more glue for the same outcome and has noisier errors.

If you're committed to `serde_path_to_error` and don't need source tracking, `config-rs` is fine.
