# 07 — Naming and Documentation

Boring is good. Predictability beats cleverness. Pick the convention once and apply it everywhere.

## Visibility defaults

The least-public modifier that works. Promotion to a more public level is a deliberate API decision.

| Item is                                                               | Default visibility                                              |
| --------------------------------------------------------------------- | --------------------------------------------------------------- |
| Used only within its own module                                       | private (no modifier / `_name` convention)                      |
| Used by sibling modules in the same crate                             | crate-private (`pub(crate)`, package-private, internal package) |
| Part of the deliberate public API (re-exported from the library root) | `pub` / public                                                  |

A blanket `pub mod foo;` / `export *` across every module is an anti-pattern. It says "everything is
API" when nothing actually is. Promote individual items as their consumers appear.

### When to promote a module to fully public

Only when:

- Another crate / package in your workspace needs to import it.
- Integration tests need access that's not reachable from a binary-only target.

For the second case, prefer adding a focused `pub use` re-export of the specific items the tests
need, not making whole modules public.

## File and module naming

- **Files**: `snake_case.<ext>`. The module path mirrors the directory path exactly.
- **Types**: `UpperCamelCase`. Acronyms count as one word: `HttpClient`, not `HTTPClient`.
- **Functions, methods, variables**: `snake_case` (or your language's idiom).
- **Constants / statics**: `SCREAMING_SNAKE_CASE`.
- **Lifetimes / generic parameters**: short and meaningful. Single uppercase letter (`T`, `K`, `V`)
  for fully generic; descriptive (`Ctx`, `Out`) when meaning matters.

## Module-file vs module-dir

When a module has submodules, prefer the **module-as-file-with-sibling-dir** form over the
**dir-with-init-file** form, where the language supports both.

```
# preferred (Rust 2018+, modern Python with __init__.py acting as a router):
src/
├─ foo.rs                # foo's public surface + `pub mod bar; pub mod baz;`
└─ foo/
   ├─ bar.rs
   └─ baz.rs

# avoid:
src/
└─ foo/
   ├─ mod.rs             # foo's surface
   ├─ bar.rs
   └─ baz.rs
```

Reasons:

- Editor file pickers show `foo.rs` instead of yet another `mod.rs` / `__init__.py`. With twenty
  `mod.rs` files in a project, finding the one you want is friction.
- Renaming `foo/` doesn't require touching its contents.
- The `foo.rs` is _the_ file that owns the module's contract; submodules under `foo/` are
  implementation details.

## Type and struct naming

Use the same vocabulary across every CLI you build. The reader who learns it once should recognize
it everywhere.

| Concept                               | Name pattern                            | Example                                                     |
| ------------------------------------- | --------------------------------------- | ----------------------------------------------------------- |
| Parser argument struct (parse-shape)  | `<Verb>Args`                            | `WidgetArgs`, `InitArgs`                                    |
| Service request (runtime-shape input) | `<Verb>Request`                         | `WidgetRequest`                                             |
| Service response                      | `<Verb>Report` or `<Verb>Outcome`       | `WidgetReport`                                              |
| Domain newtype                        | the concept itself, no suffix           | `WidgetId`, `BranchName`, `ProjectKey`                      |
| Error enum                            | `<Layer>Error`                          | `DomainError`, `GitError`, `WidgetServiceError`, `AppError` |
| Trait / interface                     | noun describing the role                | `GitBackend`, `Clock`, `PromptBackend`                      |
| Adapter implementation                | `<System><Trait>` or `<Quality><Trait>` | `LocalClock`, `RealGitBackend`, `MockGitBackend`            |

### Avoid

- **Suffix collisions with standard library types** (`Path`, `Command`, `Result`). If the domain
  wants `Command`, namespace it (`commands::Command`) or pick a different word.
- **Meaningless suffixes**: `Manager`, `Helper`, `Utils`, `Handler`, `Wrapper`. Replace with a verb
  (`Renderer`, `Resolver`) or a noun (`Cache`, `Registry`).
- **`_cmd` / `_struct` / `_impl` suffixes**. They dodge a name collision; rename the command
  instead.

## Function naming

| Purpose                       | Pattern                                                                        | Example                                  |
| ----------------------------- | ------------------------------------------------------------------------------ | ---------------------------------------- |
| Constructor                   | `new`, `with_<thing>`, `from_<source>`, `try_new`                              | `WidgetId::try_new`, `Config::from_file` |
| Getter                        | drop `get_`; just the field name                                               | `widget.id()`, not `widget.get_id()`     |
| Setter                        | `set_<field>` (or prefer making the field directly accessible if no invariant) | `config.set_log_level(...)`              |
| Conversion (consuming)        | `into_<x>`                                                                     | `s.into_string()`                        |
| Conversion (cheap borrow)     | `as_<x>`                                                                       | `path.as_str()`                          |
| Conversion (owned, expensive) | `to_<x>`                                                                       | `id.to_string()`                         |
| Predicate                     | `is_<adj>` / `has_<noun>` → returns `bool`                                     | `widget.is_active()`                     |
| Fallible variant              | `try_<verb>` returns `Result`                                                  | `try_parse`, `try_new`                   |
| I/O                           | `read_<x>` / `write_<x>`                                                       | `read_config`, `write_report`            |
| Pure transform                | `parse_<x>` / `render_<x>` / `format_<x>`                                      | `parse_id`, `render_table`               |

See [Rust API Guidelines: Naming](https://rust-lang.github.io/api-guidelines/naming.html) for the
canonical reference.

## Documentation strategy

### Doc comments

- **Every public and crate-public item has a doc comment.** Even if it just restates the name —
  that's the seed for future docs.
- **Doc comments on CLI flag fields double as `--help` text.** Write them for the user, not for the
  developer. See [`--help` is generated, not authored](#--help-is-generated-not-authored) below for
  the rule against hand-authoring a parallel flag table.
- **Use a stable cross-link syntax** (`[OtherType]` in rustdoc, `:py:class:` in Sphinx) — link rot
  is real, but link discipline is doable.

### `--help` is generated, not authored

The argument parser's derivation of `--help` from your command definitions is the **single source of
truth** for the flag table, usage line, and subcommand list. The moment you hand-author a parallel
copy in a static file, the two start drifting — every new flag or subcommand has to be added in two
places, and the static copy silently rots.

**Rule:** doc comments on parser fields and `#[command(about = ...)]`-style attributes are the only
authored shape data. Hand-written prose lives **around** the generated body via the parser's
intro/epilog hooks (`before_help`, `after_help`, `long_about` in clap; `epilog=` in argparse;
equivalents in every modern parser).

**What belongs in the authored prose (the addendum):**

- Wrapper-specific narrative: passthrough semantics (`--` sentinel), forwarding rules, "any
  unrecognized subcommand is passed to `<child>`".
- Environment variables the parser doesn't see (`<APP>_CONFIG_PATH`, `<APP>_<TOOL>_BIN`).
- Worked examples and `SEE ALSO` lists.
- Cross-references to ADRs, online docs, or related commands.

**What does NOT belong in the addendum:**

- The flag table, usage line, or subcommand list. The parser owns those.
- Re-statements of per-flag descriptions. Those live on the field's doc comment.

**Default recipe (any language with a derive-style parser):**

```text
[parser-generated about / usage / flags / subcommands]
[+ before_help: short orientation, optional]
[+ after_help / after_long_help: passthrough narrative, env vars, examples, see also]
```

Reach for a fully-overridden help (`override_help` / equivalent) only when the parser genuinely
cannot express the layout you need — almost never in practice. If you're tempted, it's usually a
sign the _commands_ are mis-organized, not that the help renderer is too rigid.

**Wrapper-CLI corollary** (see [06 — CLI Wrapper Design](06-cli-wrapper-design/)): when migrating a
wrapper from bash to a typed language, preserve **functional fidelity** (env vars, passthrough
rules, examples) in the addendum, not **implementation-detail fidelity** (the manually-formatted
flag table from the old script). The new project's flag table is whatever the new project's commands
are.

**Prior art and rationale**

The same three-tier shape recurs across ecosystems. Read the table as "what they picked, and the
reason that picked tier was justified":

| Project                                               | Language / parser                                               | Pattern                                                                                                   | Why                                                                                                                                                                          |
| ----------------------------------------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`cargo`](https://github.com/rust-lang/cargo)         | Rust / clap                                                     | Derive + `after_help` pointer to `cargo help <cmd>`                                                       | Subcommands have man-page-scale docs; the short `--help` stays terse and points at a long-form reader. The flag table is never hand-maintained.                              |
| [`jj`](https://github.com/jj-vcs/jj)                  | Rust / clap                                                     | Derive + `long_about` literals per subcommand                                                             | Scales fine to 40+ subcommands. Prose lives next to the parser definition — no separate `help.txt` to drift.                                                                 |
| [`rustup`](https://github.com/rust-lang/rustup)       | Rust / clap                                                     | Derive + `after_help = include_str!(...)` per command                                                     | Wrapper CLI: hand-authored prose covers proxy/toolchain semantics (the wrapper-narrative analog of passthrough rules and env vars). Closest reference model for any wrapper. |
| [`astral-sh/uv`](https://github.com/astral-sh/uv)     | Rust / clap                                                     | `disable_help_flag` + custom `uv help` subcommand ([PR #4906](https://github.com/astral-sh/uv/pull/4906)) | Escalated only when the _renderer_ (theming, pagination, cross-refs) outgrew what clap can produce. The command tree is still derive-based.                                  |
| [`bacon`](https://github.com/Canop/bacon)             | Rust / clap + [`clap-help`](https://github.com/Canop/clap-help) | Drop-in third-party renderer                                                                              | Same motivation as `uv` solved with a reusable crate. If you're escalating for _presentation_, evaluate this before owning a custom renderer.                                |
| [`ripgrep`](https://github.com/BurntSushi/ripgrep)    | Rust / hand-rolled                                              | No clap; help text authored alongside flag definitions in `crates/core/flags/`                            | Driven by startup-time, binary-size, and man-page-generation constraints. The upper bound of "fully custom". Don't copy unless you have ripgrep-scale distribution pressure. |
| [`kubectl`](https://github.com/kubernetes/kubectl)    | Go / cobra                                                      | `Long:` + `Example:` blocks on each command                                                               | The cobra equivalent of clap's `long_about` + `after_help`. Cobra renders the flag table; teams author only the narrative.                                                   |
| [`gh`](https://github.com/cli/cli)                    | Go / cobra                                                      | Same — `Long` + `Example`, plus `HelpFunc` override on the root for the "topics" landing screen           | The root override is _only_ for the topic-grouping landing page; per-command help is still cobra-generated. Tier-2 escalation done at the right level.                       |
| [`pip`](https://github.com/pypa/pip)                  | Python / argparse                                               | `description=` + `epilog=` per subcommand                                                                 | The argparse equivalent of `long_about` + `after_help`. Same shape, different syntax.                                                                                        |
| [`oclif` apps (e.g. `heroku` CLI)](https://oclif.io/) | TypeScript / oclif                                              | `description`, `examples`, `flags` decorators                                                             | Framework derives `--help` from class fields; `examples` is the narrative addendum.                                                                                          |

**Reading the table.** The default (Tier 1 — parser-generated structure + narrative addendum) wins
across every ecosystem and at every project scale. Tier-3 escalations cluster into two distinct
reasons: **presentation** (`uv`, `bacon` — colors, pagination, theming) and **parser-level
constraints** (`ripgrep` — startup time, binary size). Most CLIs, including wrappers, sit at Tier 1.
If your reason to escalate doesn't match one of those two buckets, treat the urge as a smell — it
usually means the _commands_ need reorganizing, not the help renderer.

**Reference docs.** [clap `Command` attrs](https://docs.rs/clap/latest/clap/struct.Command.html) ·
[argparse `ArgumentParser`](https://docs.python.org/3/library/argparse.html#argumentparser-objects)
· [cobra `Command` fields](https://pkg.go.dev/github.com/spf13/cobra#Command) ·
[oclif command authoring](https://oclif.io/docs/commands/).

### Module headers — "what it is, what it isn't"

Every file opens with a brief header stating **purpose** and **non-purpose**:

```rust
//! `widget` subcommand: parse-shape.
//!
//! Holds clap derive structs only. No I/O, no business logic.
```

```python
"""`widget` subcommand: parse-shape.

Holds Typer command definitions only. No I/O, no business logic.
"""
```

The "isn't" sentence is load-bearing. It lets a future reader see at a glance whether their new code
belongs here, and pushes back on creep.

### Crate-level / package-level docs

The library root (or `main`'s entry file) starts with:

1. A one-sentence statement of the crate's purpose.
1. A bullet list of the major modules with one-line summaries.
1. A link to the architecture spec that governs the layout.

```rust
//! `my-cli`: synchronizes widgets between local and remote stores.
//!
//! Architecture follows the CLI design spec (see `tech/programming/cli-design/`).
//!
//! - `cli`        — clap parse-shape, one file per subcommand.
//! - `commands`   — handlers, one `run()` per subcommand.
//! - `domain`     — pure types and invariants.
//! - `adapters`   — I/O at the edges.
//! - `error`      — `AppError` enum + sysexits mapping.
```

### "Comment why, not what"

The code says what. Comments say why. See [04 — Coding Style](04-coding-style-rust-zig.md), rule 11.

Bad:

```python
counter += 1  # increment counter
```

Good:

```python
# Counter resets to 0 on rollover (24h); see ADR-0014.
counter += 1
```

Link to ADRs, issues, or specs by **stable identifier**. Don't reference variables by name in
comments — renames rot the comment.

### What not to write

- "What" comments that restate the code.
- References to the current task / PR / fix ("added for the X migration", "handles the case from
  issue #123"). Those belong in commit messages and PR descriptions, not in code.
- Long "TODO" essays. Convert them into issues or ADRs; leave a short pointer in the code.

## Curated public APIs

If the codebase has a library boundary, **curate the re-exports**. Don't make every internal module
fully public.

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

Re-export individual types at the crate root when you want them at the top of the surface. Keep
modules public only when consumers must reach into them.

## Anti-patterns

- **Blanket public visibility** across all modules in a binary crate. There's no consumer — it's
  just noise.
- **Inconsistent casing**: mixing `HTTPClient` and `HttpClient`. Pick one (the Rust API Guidelines
  say one-word, lowercase acronyms — `HttpClient`).
- **Missing module headers**: makes "where does this code belong?" expensive to answer.
- **Variable-name comments**: `counter += 1  # increment counter`. The code already says that.
- **Stale TODO comments**: pile up, never get done. Convert to issues or delete.
- **"Manager / Handler / Wrapper" suffix soup**: drains type names of meaning.

## See also

- [00 — Architecture](00-architecture.md) — the directory roles whose names this chapter governs.
- [04 — Coding Style](04-coding-style-rust-zig.md) — module size cap, "comment why not what".
- Language-specific spec:
  [`rust/cli-spec/08-naming-and-visibility.md`](../../languages/rust/cli-spec/08-naming-and-visibility.md).

## References

- [Rust API Guidelines: Naming](https://rust-lang.github.io/api-guidelines/naming.html)
- [Rust Visibility & Privacy reference](https://doc.rust-lang.org/reference/visibility-and-privacy.html)
- [PEP 8: Naming Conventions](https://peps.python.org/pep-0008/#naming-conventions)
