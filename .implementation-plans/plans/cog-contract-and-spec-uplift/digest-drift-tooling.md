# `cog digest-check` and `cog digest-stamp` (Deterministic Digest Tooling)

> Plan: cog-contract-and-spec-uplift | Round: 4 of 4 | Complexity: L (override) | Generated: 2026-06-19 |
> Repo: /workspaces/cog

## Context

The `docs-n-notes` repo keeps `AGENTS.md` "digest" files that summarize a directory of spec docs for
agents. Four exist today: `tech/languages/{rust,python,bash}/cli-spec/AGENTS.md` and
`tech/tools/claude-code/plan-rounds/AGENTS.md`. Each carries YAML frontmatter:

```yaml
---
digest-of: tech/languages/rust/cli-spec
last-synced: 2026-06-18
source-files:
  - README.md
  - 00-directory-tree.md
  # ...
token-estimate: 2200
---
```

These are hand-maintained with no tooling, so they drift silently: a source file changes but
`last-synced` and the prose are stale; a file is added/removed but `source-files` is not updated. The
fix is to put the **clearly deterministic** mechanics in `cog` (per ADR-0008, the skill/script
boundary): detecting drift and stamping the frontmatter. Regenerating the prose body
(Scope / Key Points / Source Map) is summarization — judgment work — and stays in a skill or a manual
step. `cog` must never write digest prose.

`cog` is a Bash CLI, so `date` and content hashing are available (unlike the JS workflow sandbox);
`last-synced` and `token-estimate` are therefore deterministic to compute.

## Previous Rounds

Rounds are independent and may run in any order. Round 1 (`python-cli-spec-chapters`) manually
refreshes the Python digest; if Round 4 lands first, Round 1 may use `cog digest-stamp` as a
convenience, but neither round depends on the other.

## Scope of This Round

IN scope (two new `cog` commands, both machine-facing):

- `cog digest-check <digest-file-or-dir>` — compare the frontmatter against the actual source
  directory and report drift; exit non-zero when drift is found. `--json` output.
- `cog digest-stamp <digest-file-or-dir>` — deterministically rewrite **only** the frontmatter
  (`last-synced`, `source-files`, `token-estimate`), leaving the human-written body byte-untouched.
  Honor `--dry-run`.
- Unit tests (bats) and the self-documentation mirrors for the two new commands.

OUT of scope:

- Generating or editing the digest **body** prose (Scope/Key Points/Source Map) — explicitly excluded
  per ADR-0008.
- Running against the `docs-n-notes` repo as part of this round (the commands are repo-agnostic; they
  operate on whatever path the caller passes). Refreshing the actual four digests is a follow-up
  skill/manual task.
- Items 1–3 (other rounds).

## Current State

### Key Files

- The four digest files (read-only references for designing the format the commands parse):
  `$DOCS_NOTES_REPO/tech/languages/rust/cli-spec/AGENTS.md` (10 source files, est. 2200),
  `.../python/cli-spec/AGENTS.md` (5 files, 900), `.../bash/cli-spec/AGENTS.md` (2 files, 800),
  `$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/AGENTS.md` (3 files, 950). All share the
  `digest-of` / `last-synced` / `source-files` / `token-estimate` frontmatter keys.
- `lib/commands/cmd_refactor_scan_drift.sh` — prior art for a **byte-stable fingerprint** computed in
  Bash; model the source-content hashing on it (stable ordering, deterministic output).
- `lib/commands/cmd_plan_init.sh` — model for the idempotent + `--json` + `created`/`existing` output
  shape; `cog::fn::json_emit` for validated JSON emission.
- `lib/functions/fn_json_write.sh` (`cog::fn::json_emit '<filter>' "$json"`), `lib/functions/fn_ui_print.sh`
  (`ui_data`, `COG_UI_JSON`). Reuse both.
- `lib/loader.sh` — filename-based dispatch: `cog digest-check` → `lib/commands/cmd_digest_check.sh` →
  `cog::cmd::digest_check`; `cog digest-stamp` → `cmd_digest_stamp.sh` → `cog::cmd::digest_stamp`.

### Existing Patterns

- Command conventions (`AGENTS.md`): `cmd_<slug>.sh` + `cog::cmd::<slug>` + mandatory line-2
  `: 'desc: ...'` sentinel + `cog::fn::*` shared helpers + `__cog_` private helpers.
- Machine-facing contract (ADR-0009): stdout = result; drift/errors → stderr + non-zero exit; JSON when
  requested. No human decoration.
- `jq` is a hard dependency (see `doctor`'s dep list) and is the right tool to parse/emit the YAML-ish
  frontmatter via a small extraction helper (or parse the frontmatter block with `sed`/`awk` and build
  JSON with `jq`). `token-estimate` is a deterministic heuristic (e.g. word/char count ÷ a fixed
  divisor) — define the formula once in a shared helper so check and stamp agree.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: digest-drift-tooling`) `status` to `doing`.

### Step 1: Shared digest helper

Create `lib/functions/fn_<name>.sh` (e.g. `fn_digest.sh`) with `cog::fn::*` helpers to: locate a
digest file (accept either the `AGENTS.md` path or its directory), parse the frontmatter into JSON
(`digest_of`, `last_synced`, `source_files[]`, `token_estimate`), resolve the source directory from
`digest-of` (or the digest's own directory), enumerate the **actual** candidate source files, compute
a deterministic content fingerprint per file, and compute the `token-estimate` via a fixed formula.
Define the candidate-file rule explicitly (e.g. all tracked docs in the dir except `AGENTS.md` itself;
match the existing digests' `source-files` membership). Unit-test the helper.

### Step 2: Implement `cog digest-check`

`lib/commands/cmd_digest_check.sh` / `cog::cmd::digest_check`:

- Compare `source-files` in the frontmatter against the actual directory: report `missing` (listed but
  absent), `extra` (present but not listed), and `changed` (content fingerprint differs from a stored
  baseline, or — minimally — any source file whose mtime is newer than `last-synced`).
- Report whether `token-estimate` is materially off from the recomputed value (with a tolerance).
- `--json` emits a validated document (own `schema:`, e.g. `cog.digest-check.v1`) with the drift
  arrays and a boolean `stale`. Default plain output emits a terse machine summary.
- Exit non-zero (choose a stable code, e.g. `EX_DATAERR`) when drift is found, 0 when clean — so a
  pre-commit hook or CI can gate on it.

### Step 3: Implement `cog digest-stamp`

`lib/commands/cmd_digest_stamp.sh` / `cog::cmd::digest_stamp`:

- Rewrite **only** the frontmatter block: set `last-synced` to today (`date` in a fixed format,
  matching the existing `YYYY-MM-DD`), regenerate `source-files` from the actual directory (sorted
  deterministically), and recompute `token-estimate`. Leave everything after the closing `---`
  byte-for-byte unchanged.
- Honor `--dry-run` (print the diff/intended frontmatter, write nothing). `--json` reports what
  changed.
- Idempotent: stamping an already-current digest is a no-op (no body touch, frontmatter byte-stable).

### Step 4: Tests

`test/unit/digest_check.bats` and `test/unit/digest_stamp.bats` using bats + temp fixtures (a fake
digest dir under `mktemp`): clean digest → check passes / exit 0; added/removed/changed source →
correct drift arrays + non-zero exit; stamp updates frontmatter only and is idempotent; `--dry-run`
writes nothing; `--json` documents validate.

### Step 5: Self-documentation mirrors

Add `digest-check` and `digest-stamp` rows to `docs/reference/cli-commands.md`; add both to
`completions/cog.bash` and `man/cog.1.scd` (regenerate `man/cog.1` via `cog man-build` if the
`man-page-sync-precommit-hook` plan has landed, else by the repo's current method); refresh the
generated-help snapshot(s).

### Step 6: Run the gates

Run `just lint` and `just test`. Resolve any completion/man/help drift introduced by the two new
commands.

### Final Step: Update the queue

Record completion — status lives in YAML; nothing moves on disk:

1. In this plan's `queue-rounds.yaml`, set this round's (`item: digest-drift-tooling`) `status` to `done`.
2. All rounds are now done, so in the top-level `.implementation-plans/queue-plans.yaml` set this plan's
   (`item: cog-contract-and-spec-uplift`) `status` to `done`. Leave the plan directory in place.

## Acceptance Criteria

- [ ] `cog digest-check` reports `missing`/`extra`/`changed` source files and a `stale` flag, emits
      valid `--json`, and exits non-zero on drift / 0 when clean.
- [ ] `cog digest-stamp` rewrites only the frontmatter (`last-synced`, `source-files`,
      `token-estimate`), leaves the body byte-identical, honors `--dry-run`, and is idempotent.
- [ ] Neither command writes digest **body** prose (ADR-0008 boundary respected).
- [ ] Both command modules carry the line-2 `desc:` sentinel; `test/unit/digest_check.bats` and
      `test/unit/digest_stamp.bats` pass; `just lint` and `just test` green.
- [ ] `cli-commands.md`, `completions/cog.bash`, `man/cog.1.scd`/`man/cog.1`, and the help snapshot all
      list both commands; no drift checks fail.
- [ ] This plan's `queue-rounds.yaml` shows round `digest-drift-tooling` as `done`, and the top-level
      `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

This is the final round.
