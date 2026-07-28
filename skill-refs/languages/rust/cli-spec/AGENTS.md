---
digest-of: languages/rust/cli-spec
last-synced: 2026-07-10
source-files:
  - 00-directory-tree.md
  - 01-crate-layout.md
  - 02-subcommand-pattern.md
  - 03-error-handling.md
  - 04-logging.md
  - 05-config.md
  - 07-dependencies.md
  - 08-naming-and-visibility.md
  - 09-coding-style.md
  - 10-reference-projects.md
  - README.md
token-estimate: 800
---

# AGENTS

## Scope

Rust-specific CLI implementation spec applying the general principles from `cli-design/`. Covers directory layout, crate organization, subcommand patterns, error handling, logging, config, dependencies, naming, coding style, and reference projects. The spec references the general facing-category taxonomy and records only Rust idioms.

## Key Points

### Crate Stack Defaults

- Parser: `clap` (derive, env, wrap_help). Config: `figment` (env, toml). XDG: `directories`. Errors: `thiserror` + `anyhow`. Logging: `tracing` + `tracing-subscriber` + `tracing-appender`. Serialization: `serde` + `serde_json` + `toml`. Self-documentation: `clap_complete` and `clap_mangen`. Paths: `camino`. Async: `tokio` (rt, macros). Tests: `assert_cmd` + `predicates`
  - `insta` + `tempfile`. Runner: `cargo nextest`.
- Human-UX crates (`anstream`/`owo-colors`, `comfy-table`, `indicatif`, `inquire`/`dialoguer`) are human-facing-only additions.

### Directory Tree

- `src/main.rs` (<=120 LOC), `cli/` (clap derive only), `commands/` (handlers), `domain/` (pure, no I/O), `adapters/` (traits + impls), `services/` (optional), `config/`, `context.rs`, `error.rs`, `logging.rs`, conditional `ui/` for human-facing CLIs or `output/`/`protocol/` for machine-facing CLIs, `util/`.
- `tests/cmd_<name>.rs` per subcommand. Unit tests inline in `#[cfg(test)]`.
- Templates include a human-facing `main.rs.template` and a machine-facing `main.rs.machine.template`.

### Subcommand Pattern (Four-Edit Rule)

- `cli/<name>.rs` (clap Args), `cli/mod.rs` (register variant), `commands/<name>.rs` (free `run` fn), `main.rs` (dispatch arm).
- Handler signature: `pub fn run(ctx: &AppContext, args: <Verb>Args) -> Result<(), AppError>`.
- Parse-shape to runtime-shape projection at top of handler via `Request::from_cli(args)`.
- Help: `about` + `after_long_help = include_str!(...)` for human-facing narrative addenda. Keep machine-facing `help`/usage, `doctor`, `init`, completion, and man surfaces terse and parseable.

### Error Handling

- `thiserror` per layer: `DomainError` (invariants only), `<Sys>AdapterError` (I/O), `ServiceError`, `AppError` (top-level with `#[from]` arms + `Other(anyhow::Error)`).
- `AppError::exit_code() -> u8` mapped to BSD sysexits. Unit-test every arm.
- No `unwrap`/`expect` outside main, tests, build scripts, `LazyLock`.

### Logging

- `tracing` for emission. `tracing-subscriber` with `EnvFilter` and `tracing-appender` for file sink.
- Honor `RUST_LOG`. File: JSON, no ANSI. `mirror_stderr=false` is the machine-facing default; human-facing CLIs set mirroring from flags, verbosity policy, or config.
- Hold the `WorkerGuard` for program lifetime.

### Config

- `figment` layered: defaults -> user file -> project file -> env (`APP_*`) -> CLI (serialized GlobalArgs).
- `directories::ProjectDirs` for XDG. `deny_unknown_fields` on Config struct. Immutable after construction.

### Dependencies

- Manage deps through Cargo's CLI only: `cargo add`/`cargo remove`/`cargo update`. Never hand-edit dependency names/versions/features in `Cargo.toml`. Commit `Cargo.lock` for binaries. (ADR-0001)
- Current majors: `thiserror` 2, `toml` 1 (TOML spec 1.1), `anstream` 1.0.
- Avoid: `env_logger`, `log`, `structopt`, `failure`, `confy`, `dirs`, `lazy_static`, `serde_yaml`.
- Prefer: `std::sync::LazyLock` over `once_cell`. `time` over `chrono` when possible.

### Naming and Visibility

- Default `pub(crate)`. `foo.rs + foo/` over `mod.rs`. `<Verb>Args`, `<Verb>Request`, `<Layer>Error`.
- Every `pub`/`pub(crate)` item has a `///` doc comment. Module headers with purpose and non-purpose.

### Coding Style

- No `.unwrap()` outside safe zones. Trait objects only when justified. Closures via `impl Fn`. No crate-root `#![allow(dead_code)]`.
- Clippy pedantic + nursery as warn. `unwrap_used` and `expect_used` as warn.
- CI lint: `rg 'println!|eprintln!' src/ --glob '!src/ui/**' --glob '!src/main.rs'`.

## Source Map

| Topic                                       | File                          |
| ------------------------------------------- | ----------------------------- |
| Canonical `src/` tree                       | `00-directory-tree.md`        |
| Single-crate vs workspace triggers          | `01-crate-layout.md`          |
| Four-edit rule, clap derive, help rendering | `02-subcommand-pattern.md`    |
| thiserror + anyhow stack, exit-code matrix  | `03-error-handling.md`        |
| tracing setup, file sink, verbosity         | `04-logging.md`               |
| figment layered config, XDG, CLI overrides  | `05-config.md`                |
| Curated dependency list, always vs UX-only  | `07-dependencies.md`          |
| Visibility, naming tables, doc comments     | `08-naming-and-visibility.md` |
| Rust-specific style deltas                  | `09-coding-style.md`          |
| fd, bat, ripgrep, jj, cargo, helix patterns | `10-reference-projects.md`    |

## Maintenance Notes

- Chapter 06 (testing) is a subdirectory; load directly when reviewing test strategy.
- Templates in `templates/` provide bootstrap skeletons; not digested here.
- Regenerate when any chapter file changes or crate ecosystem shifts.
