# CLI Design — General Principles

Language-agnostic principles for designing command-line programs: architecture, logging, errors,
config, coding style, agent-aware design, and wrapper patterns. Use this tree as the source of truth
when bootstrapping a new CLI, and the language-specific `cli-spec/` directories for implementation
details.

## How to use this tree

1. Read [00 — Architecture](00-architecture.md) first. It defines the vocabulary the other chapters
   assume (parse-shape vs runtime-shape, `cli/` vs `commands/` vs `domain/`, etc.).
1. When a design question comes up, search the chapter that owns it.
1. Cross-link to the appropriate language-specific spec for code-level patterns.

## Index

| #  | Chapter                                                           | One-line hook                                                                                                                                 |
| -- | ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 0  | [Architecture](00-architecture.md)                                | Directory roles, parse-shape vs runtime-shape, one `AppContext` built once.                                                                   |
| 1  | [Logging & output](01-logging-and-output.md)                      | Category-aware human-UX, machine-output, and log-messages (XDG state file, LLM-friendly).                                                     |
| 2  | [Error messages](02-error-messages.md)                            | Expressive errors with stable `err.kind` keys, BSD sysexits, AI- and human-friendly.                                                          |
| 3  | [Config precedence](03-config-precedence.md)                      | `CLI > env > project file > user file > defaults`. Source-tracking loaders.                                                                   |
| 4  | [Coding style (Rust/Zig flavor)](04-coding-style-rust-zig.md)     | Explicit errors, parse-don't-validate, newtypes, composition over inheritance.                                                                |
| 5  | [Designing for LLM coding agents](05-designing-for-llm-agents.md) | `--help`, `--json`, doctor commands, evaluation harnesses.                                                                                    |
| 6  | [CLI wrapper design](06-cli-wrapper-design/)                      | Wrapping/orchestrating _other_ CLI binaries: typed builders + POSIX process model.                                                            |
| 7  | [Naming & documentation](07-naming-and-docs.md)                   | Visibility defaults, doc-comment strategy, "comment why, not what".                                                                           |
| 8  | [Testing & quality](08-testing-and-quality/)                      | Testing pyramid, per-language tooling, regression safeguards, code quality gates. Strategy, tools, AI-agent verification, complexity metrics. |
| 9  | [Reference projects](09-reference-projects.md)                    | Organizational patterns from well-studied CLIs (language-agnostic takeaways).                                                                 |
| 99 | [Checklist](99-checklist.md)                                      | One-page sanity check before shipping a CLI.                                                                                                  |

## Language-specific implementation

These chapters apply the general principles in a specific language. They assume you've read the
matching general chapter.

- [`tech/languages/rust/cli-spec/`](../../languages/rust/cli-spec/) — clap, thiserror + anyhow,
  tracing, figment, assert_cmd + insta.
- [`tech/languages/python/cli-spec/`](../../languages/python/cli-spec/) — Typer, Pydantic,
  structlog/rich.
- [`tech/languages/bash/cli-spec/`](../../languages/bash/cli-spec/) — strict mode, lib/ + bin/
  layout, shellcheck, bats.

## TL;DR (the irreducible defaults)

- **Declare the facing category and message types.** Use
  [human-facing or machine-facing](00-architecture.md#facing-category--message-types); keep
  human-UX, machine-output, and log-messages distinct.
- **Default-log to `$XDG_STATE_HOME/<app>/<app>.log`** in structured `key=value` (or JSON), no ANSI.
  Terminal mirror is opt-in.
- **`CLI > env > project file > user file > defaults`** for every knob.
- **Typed errors with stable `err.kind` per variant.** BSD sysexits exit codes. Unit-test the
  matrix.
- **Parse, don't validate.** At every boundary (CLI, file, network), strings → precise types once.
- **One `AppContext`, built in `main`, passed by reference.** No globals.
- **`pub`/`pub(crate)`/private discipline.** Default to the least visibility that works.
- **`--help` is documentation.** Treat `--help` and `man` pages as part of the API.
- **`--json` for everything machine-readable.** LLM agents, CI scripts, and pipes will thank you.
