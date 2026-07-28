# 02 — Subcommand Pattern (Rust)

> Prerequisite: [General principles — Architecture](../../../cli-design/00-architecture.md) (the four-edit rule, parse-shape vs runtime-shape, when to extract a service). This chapter is the Rust implementation using `clap`. Facing-category consequences follow [General — Facing category & message types](../../../cli-design/00-architecture.md#facing-category--message-types).

## The four files (Rust + clap)

For the four-edit rule's rationale and anti-patterns, see the general chapter. In Rust with `clap`, the four files are:

1. **`src/cli/widget.rs`** — parse-shape (clap struct).
2. **`src/cli/mod.rs`** — register the variant in the `Commands` enum.
3. **`src/commands/widget.rs`** — handler (free `run` function).
4. **`src/main.rs`** — dispatch arm.

Real-world reminder of what this prevents: a 1500-line `cli.rs` (`riptask/src/cli.rs:1-1558`).

## File-by-file skeleton

### 1. `src/cli/widget.rs` (parse-shape)

```rust
//! `widget` subcommand: parse-shape.
//!
//! Holds clap derive struct only. No I/O, no business logic.

#[derive(Debug, clap::Args)]
pub struct WidgetArgs {
    /// Optional widget ID to operate on. If omitted, operates on all widgets.
    pub id: Option<String>,

    /// Print what would happen without modifying anything.
    #[arg(short = 'n', long)]
    pub dry_run: bool,

    /// Limit to widgets matching this glob pattern.
    #[arg(long, value_name = "PATTERN")]
    pub filter: Option<String>,
}
```

Rules:

- One file per subcommand.
- One `pub struct <Verb>Args` deriving `clap::Args`.
- All arg-level docs go on fields as `///` comments — clap renders them in `--help`.
- No `impl` blocks beyond what clap demands. The args-to-domain projection lives in `commands/widget.rs`.

### 2. `src/cli/mod.rs` (register the variant)

```rust
//! Root CLI parser.

pub mod widget;
// ... other subcommand modules

#[derive(Debug, clap::Parser)]
#[command(name = "app", version, about, long_about = None)]
// `long_about = None` is the minimal starting point. See "Help rendering with
// clap" below for when to add `after_long_help = include_str!(...)`.
pub struct Cli {
    #[command(flatten)]
    pub global: GlobalArgs,

    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Debug, clap::Args)]
pub struct GlobalArgs {
    /// Increase log verbosity (-v info, -vv debug, -vvv trace). Overridden by RUST_LOG.
    #[arg(short, long, action = clap::ArgAction::Count, global = true)]
    pub verbose: u8,

    /// Path to an alternate config file.
    #[arg(long, value_name = "PATH", global = true)]
    pub config: Option<std::path::PathBuf>,
}

#[derive(Debug, clap::Subcommand)]
pub enum Commands {
    /// Operate on widgets.
    Widget(widget::WidgetArgs),
    // ... other variants
}
```

### 3. `src/commands/widget.rs` (handler)

```rust
//! `widget` subcommand: runtime-shape.
//!
//! Projects CLI args into the service-layer call, renders output via `ctx.ui`,
//! returns a typed error.

use crate::cli::widget::WidgetArgs;
use crate::context::AppContext;
use crate::error::AppError;

pub fn run(ctx: &AppContext, args: WidgetArgs) -> Result<(), AppError> {
    let request = Request::from_cli(args)?;
    let report = execute(ctx, request)?;
    ctx.ui.render_widget(&report);
    Ok(())
}

struct Request {
    id: Option<crate::domain::widget::WidgetId>,
    dry_run: bool,
    filter: Option<glob::Pattern>,
}

impl Request {
    fn from_cli(args: WidgetArgs) -> Result<Self, AppError> {
        let id = args.id.map(|s| s.parse()).transpose()?;
        let filter = args.filter.map(|p| glob::Pattern::new(&p)).transpose()?;
        Ok(Self { id, dry_run: args.dry_run, filter })
    }
}

struct Report { /* ... */ }

fn execute(ctx: &AppContext, req: Request) -> Result<Report, AppError> {
    // delegate to services / adapters
    todo!()
}

#[cfg(test)]
mod tests {
    use super::*;
    // unit tests for the CLI-args → Request projection live here.
}
```

Rules:

- Handler is a **free function** named `run`, not a method.
- Signature: `pub fn run(ctx: &AppContext, args: <Verb>Args) -> Result<(), AppError>`.
- The first thing `run` does is project `args` into a domain `Request` — this is where "parse, don't validate" applies. After projection, downstream code never sees raw strings from clap.
- `run` is sync. If it needs async, use `ctx.runtime.block_on(async { … })`. **Do not** build a new tokio runtime per command.
- Direct I/O is forbidden. Call into `services::*` or `adapters::*`.
- Tests for the projection live inline in `mod tests`.

### 4. `src/main.rs` (dispatch arm)

```rust
match cli.command {
    Commands::Widget(args) => commands::widget::run(&ctx, args),
    // ... other arms
}
```

Explicit `match`, one arm per subcommand. No macros. The `match` is exhaustive — clippy will yell if you forget an arm.

## Parse-shape → runtime-shape, in Rust

See [General — parse-shape vs runtime-shape](../../../cli-design/00-architecture.md#parse-shape-vs-runtime-shape). The Rust-specific mapping:

- `WidgetArgs` is constrained by clap derive limitations (`String`, `Option<String>`, `bool`).
- `Request` is constrained by the domain (newtypes, compiled `glob::Pattern`, validated enums).
- The projection lives in `Request::from_cli` and calls things like `WidgetId::from_str` and `glob::Pattern::new`.

## When to extract a service

See [General — When to extract a service](../../../cli-design/00-architecture.md#when-to-extract-a-service). The triggers are language-agnostic; no Rust-specific overrides.

## Rust-specific anti-patterns

Add these to the general anti-patterns:

- **Runtime per command** — every `run` builds its own tokio runtime. See `riptask/src/main.rs:95-159`. Build one runtime in `main`, share via `AppContext`.
- **`Box<dyn Command>` registry** — feels clever, loses exhaustive-match safety on `Commands`, breaks clap-derived help. Use the plain enum.

## Help rendering with clap

> Prerequisite: [General — `--help` is generated, not authored](../../../cli-design/07-naming-and-docs.md#--help-is-generated-not-authored). The rule (parser owns the structure, hand-authored prose goes in the intro/epilog) is canonical. This section is the clap-specific implementation.

### Default recipe

```rust
#[derive(Debug, clap::Parser)]
#[command(
    name = "app",
    version,
    about = "One-line summary that shows in --help and `app help`.",
    // Optional: multi-paragraph orientation, shown before USAGE on --help.
    // long_about = "...",
    // Wrapper-specific narrative (passthrough, env vars, examples, see also).
    // `after_long_help` is shown only on the long form (`--help`), keeping
    // `-h` terse. Use `after_help` if you want it on both.
    after_long_help = include_str!("../ui/help_extras.txt"),
)]
pub struct Cli { /* ... */ }
```

`src/ui/help_extras.txt` is the **only** authored help file. It must not contain a flag table, a usage line, or a subcommand list — clap generates those from the derive structs. It contains only:

- Passthrough semantics (`-- [<child args>]`, "unknown subcommands are forwarded to `<child>`").
- Env vars the parser doesn't see (`<APP>_CHILD_BIN`, `<APP>_LOG_FILE`, `<APP>_CONFIG_PATH`).
- Examples and `SEE ALSO`.

When you add a new subcommand or flag, you touch the derive struct and clap's `--help` updates automatically. `help_extras.txt` rarely changes after the first cut.

For human-facing CLIs, the authored addendum can carry narrative examples and orientation. For machine-facing CLIs, keep generated `help`/usage, `doctor`, `init`, completion, and man surfaces terse, parseable, and self-documenting for agents. Use `clap_complete` for completions and `clap_mangen` for man pages; expose man-page text through a subcommand when agents need to read it from the CLI.

### The clap mechanisms (when to use which)

| Attribute                  | Effect                                                                       | Reach for it when                                                            |
| -------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `about = "..."`            | Short one-liner shown in `-h` and at the top of `--help`                     | Always.                                                                      |
| `long_about = "..."`       | Multi-paragraph description shown only on `--help` (long form)               | The short `about` isn't enough to orient a new reader.                       |
| `before_help = "..."`      | Free-form text shown **before** the auto-generated USAGE block               | Rare. Use only for a banner / deprecation warning.                           |
| `after_help = "..."`       | Free-form text appended after flags                                          | Examples and env vars on **both** `-h` and `--help`.                         |
| `after_long_help = "..."`  | Like `after_help`, but only on `--help`                                      | Anything longer than ~5 lines — keeps `-h` terse.                            |
| `help_template = "..."`    | Reshape clap's output via `{usage}` `{all-args}` `{after-help}` placeholders | You need a non-default _layout_ (e.g. moving DESCRIPTION above USAGE). Rare. |
| `override_help = "..."`    | Replace clap's help entirely with a literal string                           | Almost never. See escalation tier below.                                     |
| `disable_help_flag = true` | Turn off auto `--help` so you can wire your own                              | Only when pairing with a fully-custom `help` subcommand.                     |

Default to `about` + `after_long_help = include_str!(...)`. Reach for the others only when that combination is genuinely insufficient.

### Escalation tiers

1. **Tier 1 (default).** `about` + `after_long_help = include_str!("../ui/help_extras.txt")`. clap owns USAGE / flags / subcommands; you own the narrative addendum.
2. **Tier 2.** Add `help_template` if you need to reorder sections or hide one of clap's blocks. Still clap-driven.
3. **Tier 3 (rare).** `disable_help_flag = true` + a custom `help` subcommand that reads `include_str!("../ui/help.txt")` and prints it through `Ui`. Justified only when you have dynamically-discovered passthrough subcommands (cargo-plugin-style) clap can't enumerate, or other narrative the parser fundamentally can't express. Document the choice in an ADR — every new flag now has to be added in two places.

`override_help` exists but is almost always the wrong call: it gives you Tier 3's maintenance cost without Tier 3's reason.

### Reconciling with the "no `println!` outside `ui/`" rule

The rule in [09 — Coding Style §7](./09-coding-style.md#7-ci-lint-for-the-no-println-rule) governs **your** code's writes to stdout/stderr. clap's auto-generated help is the parser's output — it goes through `clap_builder::output::fmt` and is not subject to the lint. You don't need to route Tier 1 help through `Ui`.

For Tier 3 (custom `help` subcommand), the printing lives in `src/ui/help.rs` and calls `ctx.ui.print_help(...)`. That keeps the lint honest and centralizes formatting if you later add ANSI / pager support.

### Prior art — what each project picked, and why

Each entry names the project, the file you can read, the tier they sit at, and the reason that escalation (or lack of it) is justified.

| Project                                                                                                   | Pattern                                                                | Where to read                                                                                                        | Why they chose it                                                                                                                                                                                                                                                                                                                                                     |
| --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| clap's own [`examples/git-derive.rs`](https://github.com/clap-rs/clap/blob/master/examples/git-derive.rs) | **Tier 1** — derive + `about` / `long_about` only                      | `examples/git-derive.rs`                                                                                             | The canonical "what clap recommends out of the box". No addendum needed when the command surface is self-explanatory.                                                                                                                                                                                                                                                 |
| [`cargo`](https://github.com/rust-lang/cargo)                                                             | **Tier 1** — `.after_help(...)` pointing at `cargo help <cmd>`         | e.g. [`src/bin/cargo/commands/add.rs`](https://github.com/rust-lang/cargo/blob/master/src/bin/cargo/commands/add.rs) | Cargo subcommands have huge man-page-style docs that don't belong in the short `--help`. The addendum is a one-liner pointer (`Run \`cargo help <cmd>\` for more detailed information.`); the real long-form lives in the`cargo help\` subcommand which loads pre-built man pages. Keeps clap-derived structure intact while routing long-form to a different reader. |
| [`astral-sh/uv`](https://github.com/astral-sh/uv)                                                         | **Tier 3** — `disable_help_flag` + custom `uv help` subcommand         | PR [#4906](https://github.com/astral-sh/uv/pull/4906)                                                                | Title literally "Implement `uv help` manually instead of using Clap default". They needed paginated, colorized, themed help with cross-references that clap's renderer couldn't produce. The escalation is justified by the _renderer_, not by the content shape — they still derive the underlying command tree.                                                     |
| [`Canop/bacon`](https://github.com/Canop/bacon)                                                           | **Tier 2** via [`clap-help`](https://github.com/Canop/clap-help) crate | [`src/`](https://github.com/Canop/bacon/tree/main/src) (CLI args definition)                                         | Same motivation as `uv` (richer presentation) but solved with a reusable renderer crate instead of bespoke code. If you find yourself wanting Tier 3 _for formatting reasons_, evaluate `clap-help` first — it gets you 80% of what `uv` did without owning the renderer.                                                                                             |
| [`BurntSushi/ripgrep`](https://github.com/BurntSushi/ripgrep)                                             | **Tier 3 extreme** — hand-rolled parser & help, no clap derive         | [`crates/core/flags/`](https://github.com/BurntSushi/ripgrep/tree/master/crates/core/flags)                          | Andrew Gallant moved off clap entirely to control startup time, binary size, and to produce a hand-tuned man page from the same source of truth. Worth studying as the upper bound of what "fully custom" costs — every flag is defined in code _and_ in help text. Don't copy unless you have ripgrep-scale distribution constraints.                                |
| [`jj-vcs/jj`](https://github.com/jj-vcs/jj) (Jujutsu)                                                     | **Tier 1** — derive + `long_about` per subcommand                      | [`cli/src/commands/`](https://github.com/jj-vcs/jj/tree/main/cli/src/commands)                                       | Each subcommand attaches a multi-paragraph `long_about` literal at the derive site. No external `help.txt`. Demonstrates that Tier 1 scales fine to a 40+ subcommand surface as long as the prose lives next to the parser definition.                                                                                                                                |
| [`rustup`](https://github.com/rust-lang/rustup)                                                           | **Tier 1+** — `after_help` with `include_str!` per command             | [`src/cli/help.rs`](https://github.com/rust-lang/rustup/blob/master/src/cli/help.rs)                                 | Wrapper for `cargo`/`rustc` toolchains. Hand-authored prose (proxy semantics, toolchain selection rules — the analog of your passthrough/env-var narrative) lives in small text files, wired in per subcommand via `after_help`. Closest model for a wrapper CLI that doesn't want to escalate to Tier 3.                                                             |

### Reference documentation

- [clap 4.x — `Command::after_help` / `after_long_help` / `long_about` / `before_help` / `help_template` / `override_help` / `disable_help_flag`](https://docs.rs/clap/latest/clap/struct.Command.html)
- [clap derive tutorial](https://docs.rs/clap/latest/clap/_derive/_tutorial/)
- [`clap-help` crate](https://github.com/Canop/clap-help) — drop-in renderer for richer presentation.
- [clap discussion #3715 — disabling help flag and custom help](https://github.com/clap-rs/clap/discussions/3715)

### Reading the table

- **Tier 1 covers the vast majority.** `cargo`, `jj`, `rustup`, and clap's own examples all sit here. If your reason for escalating isn't on this list — different _renderer_ (uv, bacon) or different _parser_ (ripgrep) — you almost certainly want Tier 1.
- **Escalation reasons cluster into two buckets:** (a) presentation — colors, pagination, theming → reach for `clap-help` first, then `disable_help_flag`; (b) parser-level constraints — startup time, binary size, dynamic plugin discovery → ripgrep-style hand-rolling. Wrappers like `codex-session` rarely hit either.

## Variant: async handlers

If most commands are async, the cleanest pattern is to keep `run` sync but have it block on an async body:

```rust
pub fn run(ctx: &AppContext, args: WidgetArgs) -> Result<(), AppError> {
    ctx.runtime.block_on(async {
        let request = Request::from_cli(args)?;
        let report = execute(ctx, request).await?;
        ctx.ui.render_widget(&report);
        Ok(())
    })
}
```

The shared runtime on `AppContext` is built once with `tokio::runtime::Builder::new_current_thread().enable_all().build()`. Multi-thread runtime is only justified if the workload genuinely benefits — for most CLIs, current-thread is faster (no work-stealing overhead, smaller binary).
