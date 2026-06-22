# 09 — Reference Projects (Organizational Patterns)

Organizational patterns extracted from well-studied CLIs, framed as language-agnostic structural
decisions. Each section is a _pattern_, not a project tour — see the language-specific reference
docs for the implementation in each language.

## Pattern 1 — single-crate, single-binary

The default shape: one package, one binary, one `src/` tree. No workspace ceremony, fast compile,
lowest cognitive load for new contributors.

**When**: starting a new CLI; under ~8k LOC of application code; no second binary or external
consumer in sight.

**Examples**:

- `fd` (Rust, ~10k LOC) — single crate, per-feature subdirectories (`exec/`, `filter/`, `fmt/`).
- `ouch` (Rust, ~10k LOC) — `cli/` + `commands/` matching the architecture spec.
- `gitui` (Rust, ~30k LOC, TUI) — single crate, components / tabs / popups split.
- `starship` (Rust, ~40k LOC) — single crate with `context.rs` + plugin-like `modules/`.

**Copy**: per-feature subdirs (`exec/`, `filter/`, `fmt/`) once you outgrow a flat `src/`. Dedicated
`exit_codes.rs` (or equivalent) for the error-code matrix.

## Pattern 2 — core library + thin binary (`bat`)

```
src/
├─ lib.rs               public API: the rendering engine
├─ printer.rs
├─ assets.rs
└─ bin/
   └─ <name>/
      ├─ main.rs
      └─ app.rs         CLI parser
```

The binary is a thin wrapper around the library. **When the library's logic is independently
useful** (rendered into a Tauri app, called from a daemon, embedded into another tool), this is the
right shape.

**Examples**: `bat`, `delta`, the Rust-side of many Tauri apps.

**Copy**: the library/binary split when you have or expect a second consumer. Resist the temptation
otherwise — a no-op `lib.rs` adds compile cost without buying anything.

## Pattern 3 — domain crates + glue (`ripgrep`)

```
crates/
├─ matcher/           grep-matcher  (matcher trait)
├─ regex/             grep-regex    (regex impl)
├─ searcher/          grep-searcher (search runner)
├─ printer/           grep-printer  (output formats)
├─ globset/           globbing
├─ ignore/            gitignore traversal
└─ core/              binary + flags + glue
```

Each subsystem is a published library, reusable independently. The binary crate is thin.

**When**: a subsystem has clear value independent of the binary. Don't pre-split — wait for the
second consumer or the publishable subsystem to emerge.

**Examples**: `ripgrep` (`globset` and `ignore` are used by dozens of other projects),
`helix-editor` (`helix-core` is dep-free of view/runtime concerns).

**Copy**: extract a subsystem only when (a) it's reusable, or (b) compile time pain is solved by
isolating it. The first rule of workspace migration is "don't migrate proactively."

## Pattern 4 — bin + client + server + common (`atuin`)

```
crates/
├─ <app>/              CLI binary (the one the user runs)
├─ <app>-client/       client-side logic
├─ <app>-server/       server-side logic
└─ <app>-common/       shared types
```

**When**: the project ships both a client and a server (sync, daemon, hub). The four-way split keeps
the type system honest about which code runs where.

**Examples**: `atuinsh/atuin`, many P2P/sync tools.

**Copy**: the directional dependency rule — `client` and `server` depend on `common`; `common`
depends on neither. If `common` ever needs to import from the others, the abstraction is in the
wrong place.

## Pattern 5 — plugin ABI as a separate crate (`zellij`)

```
zellij-server/
zellij-client/
zellij-utils/
zellij-tile/            <-- the plugin ABI
default-plugins/
```

Plugins compile against `<app>-tile` (or `<app>-plugin-api`). The plugin ABI is small, stable, and
versions independently of the host.

**When**: the app supports user-extensible features (plugins, themes, addons).

**Copy**: keep the plugin surface in its own crate even if you don't yet ship third-party plugins.
It's the smallest investment that earns you the ability to add them later without a breaking-change
marathon.

## Pattern 6 — uniform `exec()` per subcommand (`cargo`)

```
src/bin/<name>/commands/
├─ build.rs            pub fn cli() -> Command; pub fn exec(gctx, args) -> CliResult;
├─ check.rs
├─ run.rs
└─ ...
```

Every subcommand exposes the same two functions. The dispatch table is generated mechanically; new
commands slot in without touching any central registry.

**When**: many subcommands (>20), uniform structure expected, parser shape is stable.

**Examples**: `cargo` (uses imperative clap, not derive, but the discipline is identical),
`kubectl`, `git` itself.

**Copy**: the uniform exec signature. Resist macro-magic registries — the explicit `match` dispatch
in `main` is fine; it's grep-able and the compiler tells you when you forgot a branch.

## Pattern 7 — focused `command_error.rs` + bounded `ui.rs` (`jj`)

```
cli/src/
├─ main.rs
├─ cli_util.rs
├─ command_error.rs    <-- one file for all error mapping
├─ commands/
└─ ui.rs               <-- the only file that prints
```

**Copy**:

- A single `command_error.rs` (or `error.rs`) that owns the top-level error enum and exit-code
  mapping. Not spread across every command.
- A single `ui.rs` (or `ui/` module) that owns _every_ call that writes to stdout/stderr. Every
  other module emits through it.

`jj` does both well. The `ui.rs` bound is what makes "no print outside ui/" a teachable, enforceable
rule (see [04 — Coding Style, rule 12](04-coding-style-rust-zig.md)).

## Pattern 8 — `options/` vs `output/` separation (`eza`)

```
src/
├─ main.rs
├─ options/            CLI parsing + flag resolution
├─ output/             rendering (grid, table, tree, color)
├─ fs/
└─ theme/
```

**When**: the CLI has substantial formatting logic — multiple output formats, themes, layouts.
Splitting _what_ you computed from _how_ you display it keeps both halves manageable.

**Copy**: the dual split. Putting rendering inside command handlers turns them into spaghetti;
pulling it into `output/` (or `ui/`) keeps handlers focused on orchestration.

## Pattern 9 — `context.rs` + `modules/` (`starship`)

```
src/
├─ context.rs          one struct holding everything modules need
├─ module.rs           trait + helpers
├─ modules/            one file per prompt module
└─ configs/
```

**When**: the CLI has many small, similar features (prompt segments, output formatters, filters).
Each lives in its own `modules/<name>.rs`, implements a trait, takes the context, returns a result.

**Copy**: a single `Context` struct, threaded into every module by reference. Modules don't talk to
globals or each other.

## Pattern 10 — dependency-direction workspace (`helix`)

```
helix-core/             pure types: rope, position, syntax
helix-view/             view layer
helix-term/             the binary
helix-tui/              TUI primitives
helix-lsp/              LSP client
helix-loader/           config + assets
helix-event/            event bus
xtask/                  build automation
```

Crates are ordered by dependency direction: lower-level crates _never_ depend on higher-level ones.
`helix-core` doesn't know about the terminal or the editor; `helix-term` knows about everything.

**Copy**: the discipline, even in a single-crate project — modules form the same DAG. `domain/`
depends on nothing app-specific; `commands/` depends on everything below it; never the reverse.

## Comparison table

| Project  | Shape                     | Key takeaway                    |
| -------- | ------------------------- | ------------------------------- |
| fd       | single crate              | per-feature subdirs             |
| bat      | lib + bin                 | reusable lib + thin bin         |
| gitui    | single crate (TUI)        | components / tabs / popups      |
| ouch     | single crate              | cli/ + commands/ split          |
| starship | single crate              | context.rs + modules/           |
| eza      | single crate              | options/ vs output/             |
| jj       | workspace (cli subcrate)  | command_error.rs + ui.rs        |
| cargo    | workspace + bin/commands/ | uniform `exec()` signature      |
| ripgrep  | workspace (subsystems)    | publishable libraries           |
| helix    | workspace (8 crates)      | dependency-direction boundaries |
| atuin    | workspace (4 crates)      | bin + client + server + common  |
| zellij   | workspace + plugin ABI    | separate plugin-API crate       |

## See also

- [00 — Architecture](00-architecture.md) — the directory roles these patterns map onto.
- Language-specific deep dives:
  - [`rust/cli-spec/10-reference-projects.md`](../../languages/rust/cli-spec/10-reference-projects.md)
    — Rust-specific takeaways from the same projects.
- [01 — Crate Layout (Rust spec)](../../languages/rust/cli-spec/01-crate-layout.md) —
  single-crate-vs-workspace triggers.
