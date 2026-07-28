# 08 — Naming and Visibility (Rust)

> Prerequisite: [General principles — Naming & Documentation](../../../cli-design/07-naming-and-docs.md) for the verb/noun naming table, doc-comment strategy, and "comment why not what" rule. This chapter is the Rust implementation.

Boring is good. Predictability beats cleverness. Pick the convention once and apply it everywhere.

## Visibility

**Default: `pub(crate)`.** Use `pub` only on items that form the deliberate library API surface (re-exported from `lib.rs`). Use private (no modifier) inside a module when no sibling module needs it.

| Item lives in                                      | Default visibility    |
| -------------------------------------------------- | --------------------- |
| `lib.rs` re-export                                 | `pub`                 |
| Anywhere else in the crate, used by another module | `pub(crate)`          |
| Used only within its own module                    | private (no modifier) |
| `mod tests` items                                  | private               |

Why `pub(crate)` and not `pub`: it tells the next reader _"this is not an API"_, lets `cargo doc` skip it from the public docs, and lets you refactor freely without breaking external consumers.

### Anti-pattern: blanket `pub`

```rust
// don't
pub mod cli;
pub mod commands;
pub mod domain;
pub mod adapters;
```

If you don't have a real consumer of these modules outside the crate, mark them `pub(crate)` (or leave them as bare `mod` in `main.rs`). `riptask/src/lib.rs:1-16` is `pub mod` across the board — the right move is `pub(crate) mod`.

### When to add `pub` to a module

Only when **one** of:

- Another crate in your workspace needs to import it.
- Integration tests (`tests/*.rs`) need access (`tests/` can only see `pub`).

For #2, prefer adding a focused `pub use` re-export from `lib.rs` rather than making whole modules public.

## File and module naming

- Files: `snake_case.rs`. Module path mirrors the directory path exactly.
- Types: `UpperCamelCase`. Acronyms count as one word: `HttpClient`, not `HTTPClient`.
- Functions, methods, variables: `snake_case`.
- Constants and statics: `SCREAMING_SNAKE_CASE`.
- Lifetimes: short, meaningful. `'a` for a single anonymous one; `'src`, `'cfg`, `'ctx` when there are multiple and meaning matters. Avoid `'b`, `'c`, etc.
- Generic type parameters: single uppercase letter (`T`, `U`, `K`, `V`) for fully generic; descriptive when meaningful (`Ctx`, `Out`).

## `foo.rs` + `foo/` over `mod.rs`

**Pick the post-2018 form.** Given a module `foo` that contains submodules:

```text
# preferred
src/
├─ foo.rs              # `foo`'s public surface + `pub mod bar; pub mod baz;`
└─ foo/
   ├─ bar.rs
   └─ baz.rs

# avoid
src/
└─ foo/
   ├─ mod.rs           # `foo`'s surface
   ├─ bar.rs
   └─ baz.rs
```

Why:

- Editor file pickers and recent-files lists show `foo.rs` instead of yet another `mod.rs`. With twenty `mod.rs` files in a project, finding the one you want is friction.
- Renaming `foo/` to `foo_bar/` doesn't require touching `mod.rs` inside it.
- The `foo.rs` is _the_ file that owns the module's contract; submodules under `foo/` are implementation details. The file structure mirrors that hierarchy.

Both projects in our reference set (`riptask`, `ripwork`) currently use `mod.rs` — that's the inherited 2015-edition habit. Switch.

## Subcommand / struct naming

| Concept                               | Name pattern                      | Example                                                     |
| ------------------------------------- | --------------------------------- | ----------------------------------------------------------- |
| Clap arg struct (parse-shape)         | `<Verb>Args`                      | `WidgetArgs`, `InitArgs`                                    |
| Service request (runtime-shape input) | `<Verb>Request`                   | `WidgetRequest`                                             |
| Service response                      | `<Verb>Report` or `<Verb>Outcome` | `WidgetReport`                                              |
| Domain newtype                        | the concept itself, no suffix     | `WidgetId`, `BranchName`, `ProjectKey`                      |
| Error enum                            | `<Layer>Error`                    | `DomainError`, `GitError`, `WidgetServiceError`, `AppError` |
| Trait                                 | a noun describing the role        | `GitBackend`, `Clock`, `PromptBackend`                      |
| Adapter implementation                | `<System><Trait>`                 | `LocalClock`, `RealGitBackend`, `MockGitBackend`            |

Avoid:

- Suffix collisions with std types (`Path`, `Command`, `Result`). If your domain wants `Command`, namespace via `commands::Command` or pick a different word.
- `Manager`, `Helper`, `Utils`, `Handler`, `Wrapper` — they mean nothing. Replace with a verb (`Renderer`, `Resolver`) or a noun (`Cache`, `Registry`).
- `_cmd` / `_struct` / `_impl` suffixes. `riptask/src/commands/clone_cmd.rs` is dodging a name collision; renaming the command (`adopt_remote.rs`) is cleaner.

## Function naming

- Constructors: `new`, `with_<thing>`, `from_<source>`, `try_new`. Never `make_`, `create_`.
- Getters: drop `get_`. `widget.id()` not `widget.get_id()`. ([Rust API Guidelines C-GETTER](https://rust-lang.github.io/api-guidelines/naming.html))
- Setters: `set_<field>` is fine but prefer making the field public if it has no invariants, or returning a new value if the type is immutable.
- Conversions: `into_<x>` (consumes), `as_<x>` (cheap borrow), `to_<x>` (expensive borrow → owned). ([C-CONV](https://rust-lang.github.io/api-guidelines/naming.html))
- Predicates: `is_<adj>`, `has_<noun>`. Return `bool`.
- Fallible variants: `try_<verb>` returns `Result`.
- I/O methods: `read_<x>`, `write_<x>`. Pure transforms: `parse_<x>`, `render_<x>`, `format_<x>`.

## Doc comments

- Every `pub` and `pub(crate)` item carries a `///` comment. Even if it just restates the name — that's the seed for future docs.
- Every file starts with a `//!` header stating the module's purpose **and** non-purpose:

```rust
//! `widget` subcommand: parse-shape.
//!
//! Holds clap derive structs only. No I/O, no business logic.
```

The non-purpose sentence is load-bearing: it lets a future reader see at a glance whether their new code belongs here. Both `ripwork/src/main.rs:1-10` and `ripwork/src/cli/gen_request.rs:1-10` do this well.

- Doc comments on clap fields double as `--help` text. Write them for the user, not for the developer.
- Cross-link with `[Other]` syntax; rustdoc resolves it.

## Crate-level docs

`src/lib.rs` (or `src/main.rs` if there's no lib) starts with a top-of-file `//!` that:

1. Names the crate's purpose in one sentence.
2. Lists the major modules with one-line summaries.
3. Links to the spec doc that governs the architecture.

```rust
//! `app-template` CLI.
//!
//! Architecture follows the Rust CLI spec
//! (see `tech/languages/rust/cli-spec/`):
//!
//! - `cli`        — clap parse-shape, one file per subcommand.
//! - `commands`   — handlers, one `run()` per subcommand.
//! - `domain`     — pure types and invariants.
//! - `adapters`   — I/O at the edges (git, http, fs, process).
//! - `services`   — orchestration reused across commands.
//! - `error`      — `AppError` enum + sysexits mapping.
//! - `logging`    — tracing-subscriber installation.
//! - `config`     — figment-layered configuration.
//! - `ui`         — the only place allowed to write to stdout.
```

## Re-exports

If you do have a `lib.rs`, curate the public API explicitly:

```rust
// src/lib.rs

pub use error::AppError;
pub use cli::Cli;
pub use config::Config;

pub mod cli;
pub mod error;
pub mod config;
pub(crate) mod commands;
pub(crate) mod domain;
pub(crate) mod adapters;
```

Public modules are part of the API. Private modules are implementation details. Re-export individual types (not whole modules) when you want them at the crate root — keeps the surface clean.
