# Python CLI-Spec: Subcommand-Pattern & Error-Handling Chapters

> Plan: cog-contract-and-spec-uplift | Round: 1 of 4 | Complexity: L (override) | Generated: 2026-06-19 |
> Repo: /workspaces/cog (this round targets the docs-n-notes repo)

## Context

The `docs-n-notes` repo (`$DOCS_NOTES_REPO`, e.g. `/home/gbasso/DocsNNotes`) holds language CLI specs
under `tech/languages/<lang>/cli-spec/`. The **Rust** spec is the most complete: it has numbered
chapters including `02-subcommand-pattern.md` (the "four-edit rule", clap derive, help rendering) and
`03-error-handling.md` (thiserror/anyhow layered errors, exit-code matrix). The **Python** spec was
recently given `logging-python.md` but still lacks dedicated subcommand-pattern and error-handling
chapters, leaving it thinner than both Rust and Bash. This round closes that gap by authoring the two
missing Python chapters — translating the language-agnostic principles and the Rust idioms into the
Python stack (Typer/Click + Pydantic) — and refreshing the Python `AGENTS.md` digest to index them.

This is documentation authoring in a **separate repo** from `cog`. No `cog` code changes.

## Previous Rounds

This is the first round — no prior rounds. (Rounds are independent; order is not enforced.)

## Scope of This Round

IN scope:

- Author `tech/languages/python/cli-spec/subcommand-pattern-python.md` (Typer/Click subcommand
  structure, parse-shape → runtime-shape projection, handler signatures, help rendering).
- Author `tech/languages/python/cli-spec/error-handling-python.md` (Python exception hierarchy,
  exit-code mapping to BSD sysexits, `Result`-style vs raise conventions, Typer error surfacing).
- Wire both files into `tech/languages/python/cli-spec/README.md` (the "Files" table and "See also").
- Refresh `tech/languages/python/cli-spec/AGENTS.md` (frontmatter `source-files`, `last-synced`,
  `token-estimate`; add Key Points + Source Map rows for the new chapters).

OUT of scope:

- Any `cog` repo changes (this round is docs-n-notes only).
- Building the digest tooling (that is Round 4 `digest-drift-tooling`). Refresh the Python digest
  **manually** here; if Round 4 has already landed, `cog digest-check` / `cog digest-stamp` may be
  used as a convenience but is not required.
- Renumbering existing Python files to `NN-` prefixes — Python uses topic-named files
  (`logging-python.md`, `typer-patterns.md`), not numbered chapters. Match that convention; do **not**
  copy Rust's `02-`/`03-` numbering.

## Current State

### Key Files

- `$DOCS_NOTES_REPO/tech/languages/python/cli-spec/README.md` — Python spec index. Its "Files" table
  currently lists `typer-patterns.md`, `parse-cli-options-examples.py`, `config-precedence-python.md`,
  `logging-python.md`. The "See also" block links the general `cli-design/` chapters
  (`00-architecture.md` … `04-coding-style-rust-zig.md`).
- `$DOCS_NOTES_REPO/tech/languages/python/cli-spec/typer-patterns.md` — existing Python patterns
  (path options, Pydantic validators, multi-value parsing, RootModel custom types). The new
  subcommand-pattern chapter should reference, not duplicate, these.
- `$DOCS_NOTES_REPO/tech/languages/python/cli-spec/AGENTS.md` — the digest to refresh. Current
  frontmatter:

  ```yaml
  ---
  digest-of: tech/languages/python/cli-spec
  last-synced: 2026-06-18
  source-files:
    - README.md
    - logging-python.md
    - typer-patterns.md
    - config-precedence-python.md
    - parse-cli-options-examples.py
  token-estimate: 900
  ---
  ```

### Existing Patterns (mirror the Rust chapters, translate to Python)

- `$DOCS_NOTES_REPO/tech/languages/rust/cli-spec/02-subcommand-pattern.md` — model for the Python
  subcommand chapter. Rust's "four-edit rule" (`cli/<name>.rs`, `cli/mod.rs`, `commands/<name>.rs`,
  `main.rs` dispatch) translates to Python's "one file per subcommand under `cli/`, one handler under
  `commands/`" (already stated in the Python README TL;DR — expand it into a full chapter).
- `$DOCS_NOTES_REPO/tech/languages/rust/cli-spec/03-error-handling.md` — model for the Python error
  chapter. Rust's `thiserror` per-layer + `AppError::exit_code() -> u8` (BSD sysexits) translates to a
  Python exception hierarchy (a base `AppError`, per-layer subclasses) with an `exit_code` property and
  a top-level Typer handler that maps exceptions to sysexits.
- The general principles both chapters apply:
  `$DOCS_NOTES_REPO/tech/programming/cli-design/02-error-messages.md` and
  `00-architecture.md` (facing-category taxonomy). Reference them with relative links exactly as the
  existing Python `README.md` "See also" does.
- Markdown rules: fenced code blocks must declare a language (MD040); use `text` when none applies.
  Match the existing Python files' heading style and table formatting.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`
(`.implementation-plans/plans/cog-contract-and-spec-uplift/queue-rounds.yaml`), set this round's
(`item: python-cli-spec-chapters`) `status` to `doing`.

### Step 1: Author `subcommand-pattern-python.md`

Create `$DOCS_NOTES_REPO/tech/languages/python/cli-spec/subcommand-pattern-python.md`. Cover, as a
full chapter (mirroring the structure and depth of Rust `02-subcommand-pattern.md`):

- Directory layout: `cli/<name>.py` (Typer command definition) and `commands/<name>.py` (handler).
- The Python equivalent of the four-edit rule: add command file, register it on the Typer app
  (`app.add_typer` / `@app.command`), add the handler, wire dispatch.
- Handler signature convention: a free `run(ctx, request)` function; parse-shape (Typer params) →
  runtime-shape (Pydantic request model) projection at the top of the handler, not in the parser.
- Help rendering: `help=`/`rich_help_panel` for human addenda; keep machine-facing
  `help`/`--json`/`doctor`/`init`/completion terse and parseable.
- Cross-link `typer-patterns.md` for the parameter-level patterns instead of repeating them.

### Step 2: Author `error-handling-python.md`

Create `$DOCS_NOTES_REPO/tech/languages/python/cli-spec/error-handling-python.md`. Cover (mirroring
Rust `03-error-handling.md`):

- A layered exception hierarchy: base `AppError`, per-layer subclasses (`DomainError`,
  `<Sys>AdapterError`, `ServiceError`), each carrying a kind/context.
- `exit_code` mapping to BSD sysexits (mirror the Rust exit-code matrix; reference the same sysexits
  values `cog` uses, e.g. `EX_USAGE=64`, `EX_SOFTWARE=70`, `EX_CONFIG=78`, `EX_UNAVAILABLE=69`).
- Where to raise vs. where to catch: handlers raise typed errors; a single top-level Typer
  error-boundary maps them to exit codes and emits the machine-facing error shape (structured to
  stderr), prose only under explicit human-UX.
- Conventions on `try/except` granularity, chaining (`raise ... from`), and never swallowing.

### Step 3: Wire the new chapters into the Python README

Edit `$DOCS_NOTES_REPO/tech/languages/python/cli-spec/README.md`:

- Add two rows to the "Files" table for `subcommand-pattern-python.md` and `error-handling-python.md`
  with one-line hooks.
- Add a "See also" link for the new error chapter alongside the existing
  `[Python — Logging](logging-python.md)` entry.

### Step 4: Refresh the Python `AGENTS.md` digest

Edit `$DOCS_NOTES_REPO/tech/languages/python/cli-spec/AGENTS.md`:

- Frontmatter: add `subcommand-pattern-python.md` and `error-handling-python.md` to `source-files`;
  update `last-synced` to the date of this change; re-estimate `token-estimate`.
- Body: add Key Points bullets summarizing the two new chapters; add their rows to the Source Map
  table.
- Keep the digest faithful to the source files (this is the manual prose-regen step that Round 4's
  `cog` tooling deliberately does **not** automate).

### Step 5: Validate in the docs-n-notes repo

Run that repo's own markdown lint / pre-commit (not `cog`'s). Confirm no MD040 (unlabeled fence)
violations and that relative links resolve.

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: python-cli-spec-chapters`) `status` to
   `done`.

(This is not the final round — do not touch the top-level ledger.)

## Acceptance Criteria

- [ ] `subcommand-pattern-python.md` exists, is a complete chapter, and matches Python conventions
      (topic-named, not `NN-` prefixed).
- [ ] `error-handling-python.md` exists with a Python exception hierarchy and a sysexits exit-code
      mapping.
- [ ] The Python `README.md` "Files" table and "See also" reference both new chapters.
- [ ] The Python `AGENTS.md` frontmatter `source-files` lists the two new files, `last-synced` is
      updated, and the body indexes them.
- [ ] docs-n-notes markdown lint passes (no MD040 violations; links resolve).
- [ ] This plan's `queue-rounds.yaml` shows round `python-cli-spec-chapters` as `done`.

## Next Round

`cog-init-subcommand` — implement the `cog init` self-documenting setup surface in the `cog` repo,
DRY against `doctor`. Independent of this round.
