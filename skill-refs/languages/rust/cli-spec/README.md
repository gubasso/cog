# Rust CLI Spec

Canonical reference for every Rust CLI project. The source of truth for directory layout, module boundaries, error handling, logging, config, testing, dependencies, and coding style **in Rust**.

For the language-agnostic principles these chapters apply, see **[`tech/cli-design/`](../../../cli-design/)**. Every chapter here links back to its general counterpart.

Use this spec as a template at project bootstrap and as a tie-breaker during code review.

## How to use

1. **Read [the general principles](../../../cli-design/) first** if you haven't. The vocabulary (parse-shape vs runtime-shape, `AppContext`, the four-edit rule) lives there.
2. Start a new CLI from `templates/` (copy the files, rename the crate, prune unused modules).
3. When a design question comes up, search the chapter that owns it.
4. When the spec itself needs to change, add an ADR under `adr/` and edit the chapter.

## Index

| #  | Chapter                                                | One-line hook                                                                      | General principle                                                           |
| -- | ------------------------------------------------------ | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| 0  | [Directory tree](./00-directory-tree.md)               | Canonical `src/` layout, with "what does NOT go here" per directory.               | [00-architecture](../../../cli-design/00-architecture.md)                   |
| 1  | [Crate layout](./01-crate-layout.md)                   | Single-crate vs workspace; when to add `lib.rs`.                                   | [00-architecture](../../../cli-design/00-architecture.md)                   |
| 2  | [Subcommand pattern](./02-subcommand-pattern.md)       | The four-edit rule — one file per subcommand on both sides.                        | [00-architecture](../../../cli-design/00-architecture.md)                   |
| 3  | [Error handling](./03-error-handling.md)               | `thiserror` inside, `anyhow` only at the edge; BSD sysexits.                       | [02-error-messages](../../../cli-design/02-error-messages.md)               |
| 4  | [Logging](./04-logging.md)                             | `tracing` + `tracing-subscriber` + file sink to `$XDG_STATE_HOME`.                 | [01-logging-and-output](../../../cli-design/01-logging-and-output.md)       |
| 5  | [Config](./05-config.md)                               | `figment` layered loader; `directories` for XDG paths.                             | [03-config-precedence](../../../cli-design/03-config-precedence.md)         |
| 6  | [Testing & quality](06-testing-and-quality/)           | `assert_cmd` + `insta` + `nextest` + `proptest` + `cargo-mutants` + `cargo-bloat`. | [09-testing-and-quality](../../../cli-design/08-testing-and-quality/)       |
| 7  | [Dependencies](./07-dependencies.md)                   | Curated default crate list with justification.                                     | —                                                                           |
| 8  | [Naming and visibility](./08-naming-and-visibility.md) | `pub(crate)` by default; `foo.rs + foo/` over `mod.rs`.                            | [08-naming-and-docs](../../../cli-design/07-naming-and-docs.md)             |
| 9  | [Coding style](./09-coding-style.md)                   | Rust idioms: newtypes, FromStr, lints, LazyLock.                                   | [04-coding-style-rust-zig](../../../cli-design/04-coding-style-rust-zig.md) |
| 10 | [Reference projects](./10-reference-projects.md)       | Layouts to study (ripgrep, fd, bat, jj, cargo, helix).                             | [09-reference-projects](../../../cli-design/09-reference-projects.md)       |

## Supporting material

| Path                       | Hook                                                                                        |
| -------------------------- | ------------------------------------------------------------------------------------------- |
| [`templates/`](templates/) | Bootstrap skeleton for a new Rust CLI: starter files, module layout, and template comments. |
| [`adr/`](adr/)             | Architecture decision records for changes to this Rust spec and its defaults.               |

## Templates

`templates/` holds the bootstrap skeleton:

```text
templates/
├─ Cargo.toml.template
└─ src/
   ├─ main.rs.template
   ├─ main.rs.machine.template
   ├─ error.rs.template
   ├─ logging.rs.template
   ├─ cli/
   │  ├─ mod.rs.template
   │  └─ example.rs.template
   └─ commands/
      ├─ mod.rs.template
      └─ example.rs.template
```

Copy the tree, drop the `.template` suffixes, rename `app_template` → your crate name.

## TL;DR

- Single crate by default; workspace only at ~8k LOC or when a real second consumer appears.
- `cli/` holds clap parsers (parse-shape). `commands/` holds handlers (runtime-shape). One file per subcommand on **both** sides.
- `domain/` is pure (no I/O, no async). `adapters/` is the only place that touches the outside world. `services/` is optional — add it only when orchestration is reused.
- Error stack: `thiserror` per-layer typed enums → top-level `AppError` → `exit_code()` mapped to BSD sysexits.
- `tracing` + `tracing-subscriber` with `RUST_LOG`. **Default destination: `$XDG_STATE_HOME/<app>/<app>.log`** (file sink via `tracing-appender`). Terminal mirror is opt-in.
- `figment` for layered config: defaults → user file → project file → env → CLI.
- Tests: `assert_cmd` + `predicates` + `insta` + `tempfile`. Run with `cargo nextest`.
- One `AppContext` built once in `main`, passed by `&AppContext`. Single shared tokio runtime.
- No `println!` outside `ui/`. No `panic!` outside `main`. (clap's auto-generated `--help` / `--version` output doesn't count — it's the parser's output, not yours.)
- `--help` is parser-generated. Authored prose lives in `src/ui/help_extras.txt`, wired via `#[command(after_long_help = include_str!(...))]`. Never hand-maintain a parallel flag table. See [02 — Subcommand Pattern · Help rendering](./02-subcommand-pattern.md#help-rendering-with-clap).

## Sources

External references the spec relies on:

- [Rust CLI Book](https://rust-cli.github.io/book/)
- [clap derive tutorial](https://docs.rs/clap/latest/clap/_derive/_tutorial/)
- [BurntSushi: Error handling in Rust](https://burntsushi.net/rust-error-handling/)
- [anyhow](https://docs.rs/anyhow/) · [thiserror](https://docs.rs/thiserror/)
- [tracing](https://docs.rs/tracing/) · [tracing-subscriber](https://docs.rs/tracing-subscriber/) · [tracing-appender](https://docs.rs/tracing-appender/)
- [figment](https://docs.rs/figment/) · [directories](https://docs.rs/directories/)
- [Alexis King: Parse, don't validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)
- [Rust newtype pattern](https://rust-unofficial.github.io/patterns/patterns/behavioural/newtype.html)
- [assert_cmd](https://docs.rs/assert_cmd/) · [insta](https://insta.rs/docs/)
- [BSD sysexits(3)](https://man.freebsd.org/cgi/man.cgi?query=sysexits&sektion=3)
- [Rust API Guidelines: Naming](https://rust-lang.github.io/api-guidelines/naming.html)
- [Visibility & privacy](https://doc.rust-lang.org/reference/visibility-and-privacy.html)
- [Killercup: Elegant APIs in Rust](https://deterministic.space/elegant-apis-in-rust.html)
