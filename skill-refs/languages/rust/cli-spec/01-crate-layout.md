# 01 — Crate Layout (Rust)

> Prerequisite: [General principles — Architecture](../../../cli-design/00-architecture.md) (Crate organization section) for the "stay single-crate until..." rule and the workspace migration triggers. This chapter is the Rust implementation. Facing-category consequences follow [General — Facing category & message types](../../../cli-design/00-architecture.md#facing-category--message-types).

When to ship one crate, when to ship a workspace, and when (if ever) to split `lib.rs` from `main.rs`.

## Default: single crate

Start every CLI as a single Cargo package with one binary. This is what `fd`, `gitui`, `ouch`, `starship` do. It compiles faster, has zero workspace ceremony, and is the lowest-friction shape for the first months of a project.

```text
my-cli/
├─ Cargo.toml          # [package] only, no [workspace]
└─ src/
   ├─ main.rs
   └─ ...
```

## When to add `src/lib.rs`

Only when one of these is true:

1. **Another crate consumes the logic.** A daemon, a Tauri app, a build tool, or a sibling crate in your workspace needs to call into the same code. `bat` does this — `src/lib.rs` exposes the rendering engine; `src/bin/bat/main.rs` is a thin CLI on top.
2. **Integration tests need internals.** `tests/*.rs` files can't reach `pub(crate)` items in a binary-only crate. If you want to integration-test a parser or a service directly, you need a library.

If neither is true, don't create `lib.rs`. A no-op `lib.rs` that only declares private modules (e.g. `ripwork/src/lib.rs:1-13`) is dead weight — it shows up in `cargo doc`, adds an extra compile unit, and confuses readers about what the public API is.

**When you do add `lib.rs`**, follow the Hertleif pattern: `main.rs` is a 30-line shim that calls `lib::run(args)` and maps errors to exit codes. All logic lives in `lib`. This sample uses simple human-facing prose error reporting on stderr; machine-facing templates emit structured (JSON) errors to stderr instead. Both report errors on stderr with a non-zero exit code — only the format differs.

```rust
// src/main.rs
fn main() -> std::process::ExitCode {
    let args = app_template::cli::Cli::parse();
    match app_template::run(args) {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("app: {e}");
            std::process::ExitCode::from(e.exit_code())
        }
    }
}
```

## When to migrate to a Cargo workspace

Stay single-crate until **any one** of these triggers fires. Don't migrate proactively.

1. **Second binary sharing ≥30% of code.** A daemon, a helper, an `xtask`, a TUI variant. Split into `app-core` (library) + `app-cli` (binary) + the new consumer.
2. **A subsystem is publishable on its own.** Ripgrep extracted `grep-matcher`, `grep-regex`, `grep-searcher`, `grep-printer` precisely because each is reusable. If a subsystem has zero dependencies on app-specific concerns, it earns its own crate.
3. **Compile time exceeds tolerance.** `cargo check` on a warm cache over ~10s **and** the slow code is structurally separable. Splitting moves slow code into its own compilation unit that doesn't get rebuilt on every iteration.
4. **Plugins/adapters need independent dep trees.** Helix splits `helix-lsp` so the LSP client's deps don't bloat the core.

**Hard threshold**: at ~8k LOC, take a serious look. Below that, the cost of workspace navigation (multiple `Cargo.toml`s, multiple `target/` outputs in your IDE, cross-crate refactor friction) outweighs the wins.

## Workspace shape when you do migrate

Two common patterns. Pick by your trigger.

### Pattern A — core lib + thin bin (the `bat` pattern)

```text
Cargo.toml                # [workspace] root
crates/
├─ app-core/              # library — all logic, all types
│  ├─ Cargo.toml          # [package]; no [[bin]]
│  └─ src/lib.rs
└─ app-cli/               # binary — clap, main, exit-code mapping
   ├─ Cargo.toml          # depends on app-core
   └─ src/main.rs
```

Use when trigger 1 fires (second consumer).

### Pattern B — domain crates + glue (the `ripgrep` pattern)

```text
Cargo.toml                # [workspace] root
crates/
├─ app-domain/            # pure types, no I/O
├─ app-adapter-git/       # one crate per adapter family
├─ app-adapter-http/
├─ app-service/           # use-case layer
└─ app-cli/               # clap + main
```

Use when trigger 2 fires (publishable subsystems) or when build-time pain is the driver.

## Cargo.toml skeleton

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

[dependencies]
# see chapter 05

[dev-dependencies]
# see chapter 05

[profile.release]
lto         = "thin"
codegen-units = 1
strip       = "symbols"
```

Pin `edition = "2024"` and a concrete `rust-version` so users get a clean error instead of a confusing compile failure on older toolchains.

## Pinning the toolchain

`rust-toolchain.toml` at the repo root:

```toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy"]
```

Pin to a specific version (e.g. `"1.85"`) when reproducibility matters more than getting free improvements. For most CLIs, `stable` is right.
