# 00 — Directory Tree (Rust)

> Prerequisite: [General principles — Architecture](../../../cli-design/00-architecture.md). That chapter is canonical for directory roles, "does NOT belong here" rules, parse-shape vs runtime-shape, the four-edit rule, and the `AppContext` pattern. This file translates the skeleton to Rust file names, module conventions, and crate-stack choices. Facing-category consequences follow [General — Facing category & message types](../../../cli-design/00-architecture.md#facing-category--message-types).

## Canonical tree

```text
crate/
├─ Cargo.toml                  # edition = "2024", single bin
├─ rust-toolchain.toml         # pinned channel (stable by default)
├─ justfile                    # check / lint / test / fmt tasks
├─ deny.toml                   # cargo-deny policy
├─ src/
│  ├─ main.rs                  # ≤120 LOC. parse → init logging → AppContext → dispatch → exit-code map.
│  ├─ lib.rs                   # OPTIONAL. Only when truly reusable.
│  ├─ cli/                     # clap derive structs ONLY.
│  │  ├─ mod.rs                # root Cli + Commands enum + GlobalArgs
│  │  └─ <subcommand>.rs       # `#[derive(Args)] pub struct <Verb>Args`
│  ├─ commands/                # one handler per subcommand.
│  │  ├─ mod.rs
│  │  └─ <subcommand>.rs       # `pub fn run(ctx: &AppContext, args: <Verb>Args) -> Result<(), AppError>`
│  ├─ domain/                  # pure types + invariants + newtypes.
│  │  └─ <concept>.rs
│  ├─ services/                # OPTIONAL. Add only when orchestration is reused.
│  ├─ adapters/                # I/O at the edges. Each defines a trait + default impl.
│  │  └─ <external_system>.rs
│  ├─ config/                  # figment loader + layered merge.
│  ├─ context.rs               # AppContext struct.
│  ├─ error.rs                 # AppError enum + exit_code().
│  ├─ logging.rs               # tracing-subscriber init helper.
│  ├─ exit.rs                  # OPTIONAL. Move exit-code mapping here if error.rs grows.
│  ├─ ui/                      # human-facing terminal output only; machine-facing uses output/ or protocol/.
│  └─ util/                    # truly generic helpers.
├─ tests/
│  ├─ cmd_<name>.rs            # one integration test per subcommand (assert_cmd)
│  ├─ fixtures/
│  ├─ snapshots/
│  └─ support/mod.rs           # shared test helpers
└─ benches/                    # criterion benches; only when needed
```

## Rust-specific concretizations

For each directory's _role_ and "does NOT belong here" rule, defer to the [general principles directory roles](../../../cli-design/00-architecture.md#directory-roles). The notes below are Rust-only deltas.

### `src/main.rs`

- Size budget: ≤120 LOC.
- The one tokio runtime constructor lives here; the resulting `Handle` goes onto `AppContext`.
- Use `templates/src/main.rs.template` for human-facing CLIs and `templates/src/main.rs.machine.template` for machine-facing CLIs.

### `src/lib.rs`

- Only create when a second crate (or integration tests that need internals) needs the surface. A no-op `lib.rs` declaring private modules is dead weight; keep modules `mod` inside `main.rs`.

### `src/cli/`

- Each subcommand `<name>` has exactly one file `cli/<name>.rs` with a single `pub struct <Verb>Args` deriving `clap::Args`.
- `mod.rs` exposes the root `Cli` (derives `clap::Parser`), the `Commands` enum (derives `clap::Subcommand`), and any shared `GlobalArgs`.

### `src/commands/`

- Signature: `pub fn run(ctx: &AppContext, args: <Verb>Args) -> Result<(), AppError>`. Free function, not a method on the args struct. See [`02-subcommand-pattern.md`](./02-subcommand-pattern.md).

### `src/domain/`

- A `#[derive(Serialize, Deserialize)]` on a domain struct is fine; calling `serde_json::from_reader` is not — that goes to `adapters/`.
- Forbidden in this module: `std::io`, `tokio`, `reqwest`, file/network readers.

### `src/services/`

- A service is a free function or a struct with a single public `execute` method, taking adapter traits as parameters so tests can swap fakes.

### `src/adapters/`

- Each adapter file defines a trait (`GitBackend`, `Clock`, …) and a default implementation. Services depend on the trait, not the impl.
- Each adapter defines its own error enum; `AppError` aggregates them via `#[from]`. See [`03-error-handling.md`](./03-error-handling.md).

### `src/config/`

- Uses `figment` for the merge chain. See [`05-config.md`](./05-config.md).

### `src/context.rs`

- Holds resolved `Config`, computed `Paths`, the shared `tokio::Runtime` handle, the tracing root span, and either the `Ui` instance for human-facing CLIs or a structured-output/protocol facility for machine-facing CLIs.

### `src/error.rs`

- `AppError` is a `thiserror` enum aggregating per-layer errors via `#[from]`. Includes `impl AppError { pub fn exit_code(&self) -> u8 }`. See [`03-error-handling.md`](./03-error-handling.md).

### `src/logging.rs`

- `pub fn init(verbosity: u8) -> anyhow::Result<()>` helper that installs `tracing-subscriber` with `EnvFilter`. See [`04-logging.md`](./04-logging.md).

### `src/ui/`

- Human-facing CLIs use a single `Ui` struct with methods like `render_widget`, `confirm`, and `progress`.
- Machine-facing CLIs omit `src/ui/` unless they have explicit opt-in human-UX; default output lives in `src/output/` or `src/protocol/`.
- **No `println!` / `eprintln!` outside this module, the structured-output boundary, or `main.rs`** — enforce as a CI lint (see [`09-coding-style.md`](./09-coding-style.md)).

### `src/util/`

- ≤ 200 LOC per file.

### `tests/`

- One `tests/cmd_<name>.rs` per subcommand using `assert_cmd::Command::cargo_bin("<bin>")`. Pure unit tests stay inline under `#[cfg(test)] mod tests` in their owning module.

### `benches/`

- Criterion only. Throwaway timing scripts go to `examples/`.

## Optional extras (Rust)

Add when you actually need them — not preemptively:

- `examples/` — small runnable examples that double as docs.
- `xtask/` — workspace-internal CLI for build tasks. Only at workspace scale.
- `docs/adr/` — Architecture Decision Records for spec deviations.

## Reading order for new contributors

1. `Cargo.toml` — see the dependency footprint.
2. `src/main.rs` — see the dispatch surface.
3. `src/cli/mod.rs` — see the user-facing command set.
4. Pick one `commands/<name>.rs` — trace it down through `services/` → `adapters/`.
5. `src/error.rs` — understand the failure model.
