# cog Machine-Facing Contract & Python Spec Uplift

> Complexity: L (override) | Rounds: 4 | Generated: 2026-06-19 | Repo: /workspaces/cog

## Problem Statement

A prior working session that hardened `cog`'s machine-facing output contract (ADR-0009) and refreshed
the Claude Code skill orchestration docs surfaced four follow-up gaps. They are independent of one
another but share a theme: making `cog` fully live up to the machine-facing, self-documenting CLI
standard it now documents, and bringing the cross-repo CLI specs up to parity.

1. **Python CLI-spec gap.** In the `docs-n-notes` repo, the Rust CLI spec
   (`tech/languages/rust/cli-spec/`) has dedicated `02-subcommand-pattern.md` and
   `03-error-handling.md` chapters. The Python CLI spec (`tech/languages/python/cli-spec/`) was
   recently given `logging-python.md` but still has no subcommand-pattern or error-handling chapters,
   so it is thinner than Rust and Bash. Python needs equivalent chapters and a refreshed digest.

2. **`cog init` subcommand is target-state only.** `docs/reference/cli-commands.md` and ADR-0009 both
   name `init` as the remaining self-documenting setup surface, but no `cmd_init.sh` exists. `cog`
   does not yet satisfy the machine-facing self-documenting-surfaces standard it documents. `init`
   must be implemented DRY against `doctor` (doctor is the source of truth for prerequisite/XDG
   checks).

3. **`cmd_msg.sh` human-UX leakage.** ADR-0009 records the emoji (`❌`/`▶`) and `ui_human` output in
   `cmd_msg.sh` and `doctor` as *acknowledged leakage*. `cog` has no present need to emit any
   human-facing content — it is machine-facing end to end. The leakage should be **removed** (not
   gated behind an opt-in), leaving only the universal stderr error/warning contract, and ADR-0009's
   acknowledgement updated to record closure.

4. **Digest drift.** Four `AGENTS.md` digests in `docs-n-notes` (rust/python/bash `cli-spec` +
   `tools/claude-code/plan-rounds`) are hand-maintained with no tooling. They carry frontmatter
   (`digest-of`, `last-synced`, `source-files`, `token-estimate`) that silently goes stale. The
   *clearly deterministic* parts of keeping them fresh — detecting drift and stamping the frontmatter
   — belong in `cog`; regenerating the human-written prose body is judgment work that stays in a
   skill or manual step (per ADR-0008, the skill/script boundary).

## Strategy

Four independent deliverables, one per round, each sized for a single `/prex` session. The work is
split by deliverable boundary, not by complexity: bundling unrelated changes into one prex run
degrades quality (see `plan-lifecycle.md` § "Executor capacity model"). Rounds have **no
dependencies** on one another and may be executed in any order; the queue order below is a suggested
sequence, not a hard chain.

Round 1 (Python chapters) targets the **`docs-n-notes` repo** (a separate working tree); Rounds 2–4
target the **`cog` repo**. Rounds 2 and 4 add new commands, so each must also update the command
self-documentation mirrors (`completions/cog.bash`, `man/cog.1.scd`, `docs/reference/cli-commands.md`,
and the generated-help snapshots) — the same mirrors the in-flight `man-page-sync-precommit-hook`
plan automates.

## Rounds

The authoritative order and status live in `queue-rounds.yaml`; this list is a readable mirror.

1. `python-cli-spec-chapters.md` — Author Python `subcommand-pattern` + `error-handling` chapters in
   `docs-n-notes`, wire them into the README, refresh the Python `AGENTS.md` digest.
2. `cog-init-subcommand.md` — Implement `cog init` DRY against `doctor` by extracting a shared
   prerequisite-check helper; add tests + self-doc mirrors.
3. `msg-machine-facing-cleanup.md` — Remove human-UX leakage (emoji + decorative `ui_human`) from
   `cmd_msg.sh`/`doctor`/etc.; keep the stderr error/warning contract; update ADR-0009.
4. `digest-drift-tooling.md` — Add `cog digest-check` (drift detection) and `cog digest-stamp`
   (deterministic frontmatter refresh); prose regen stays out of `cog`.

## Execution Commands

```bash
# Execute the next todo round (executor reads queue-rounds.yaml, runs the first `todo` round, then stops):
/prex -ar @.implementation-plans/plans/cog-contract-and-spec-uplift/

# Or target a specific round file directly (rounds are independent — any order is valid):
/prex -ar .implementation-plans/plans/cog-contract-and-spec-uplift/python-cli-spec-chapters.md
/prex -ar .implementation-plans/plans/cog-contract-and-spec-uplift/cog-init-subcommand.md
/prex -ar .implementation-plans/plans/cog-contract-and-spec-uplift/msg-machine-facing-cleanup.md
/prex -ar .implementation-plans/plans/cog-contract-and-spec-uplift/digest-drift-tooling.md
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for a
single `/prex` session. Do not implement multiple rounds in one session.

When `/prex` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh `/prex` session is launched for any subsequent round.

**Why:** Fresh sessions prevent context contamination between rounds, keep token usage predictable,
and let you review intermediate results before proceeding. Because these four rounds are independent,
you may also choose the order freely — but still one round per session.

## Decisions & Constraints

- **Executor: prex (EF 1.5).** This sized each round individually; every round is S/M and fits one
  prex session.
- **Grade override: M → L (directory, 4 rounds).** Per-axis: files:4 cross-cut:3 deps:2 novelty:3
  risk:3 → raw 15 ÷ EF 1.5 → adjusted 10.0 → formula M as a descriptive grade; overridden to a 4-round directory because the items are four *independent cohesive deliverables*, not one feature. The round
  count is driven by deliverable independence, **not** complexity absorption, so the prex "recompute
  if 4+ rounds" guard (which targets over-split single features) does not apply.
- **Round 3 closes leakage rather than gating it** (user direction): `cog` emits no human-facing
  content today, so introducing a `--human`/`COG_UI_HUMAN` opt-in would add an unused surface. Remove
  the decorative output instead. The universal Unix stream contract is untouched — errors and warnings
  still go to stderr with non-zero exit codes per ADR-0009.
- **Round 4 keeps prose regen out of `cog`** (ADR-0008): `cog` owns only the clearly deterministic
  mechanics — drift detection and frontmatter stamping. Summarizing source files into digest prose is
  judgment work that stays in a skill or manual step.
- **Round 2 is DRY against `doctor`**: extract the shared prerequisite/XDG checks into a
  `cog::fn::*` helper consumed by both `doctor` and `init`, rather than duplicating doctor's logic.
- **New commands update the self-doc mirrors** (Rounds 2, 4): `completions/cog.bash`,
  `man/cog.1.scd`, `docs/reference/cli-commands.md`, generated-help snapshots.

## Rejected Alternatives

- **Four separate single-file plans via `/plan-writer-multi`.** The cleanest match to the
  independence, but a different command than the one invoked; the user chose a single directory plan.
- **One single-file M plan bundling all four** (what the raw formula implies). Rejected: one prex run
  handling four loosely-related changes degrades quality (lifecycle spec).
- **Gating human-UX behind `COG_UI_HUMAN`/`--human` (Round 3).** Rejected per user direction —
  `cog` has no human-UX need, so an opt-in surface would be dead weight. Removal is simpler and fully
  machine-facing.
- **`cog digest-regen` that generates the prose body (Round 4).** Rejected per ADR-0008 — probabilistic
  summarization must stay in skills/prose, not `cog`.

## Risks & Edge Cases

- **Round 3 touches shared `lib/functions/fn_ui_print.sh`** — used by error/log plumbing. The
  error/warning-to-stderr path (`ui_warn`, `ui_error_line` via `fn_error_raise.sh`/`fn_log.sh`) must
  be preserved; only decorative/progress output is removed. Verify `cog msg` callers in the gc skills
  (`skills/claude/gc/SKILL.md`, `skills/codex/gc/SKILL.md`) still work.
- **ADR-0009 is Accepted and never deleted.** Round 3 updates a *consequence/acknowledgement*
  paragraph (the decision — machine-facing — is unchanged, in fact completed), so an in-place dated
  amendment is appropriate rather than a superseding ADR. If the executor judges the change to be a
  decision reversal, it should instead add a superseding ADR.
- **Rounds 2 and 4 add commands** — the man/completion/cli-commands mirrors must stay in sync or the
  drift checks fail. Coordinate with the in-flight `man-page-sync-precommit-hook` plan if it lands
  first (its `cog man-build` would regenerate `man/cog.1` from the `.scd`).
- **Round 1 is in a different repo** (`$DOCS_NOTES_REPO`). The executor must confirm the path resolves
  and run that repo's own lint/pre-commit, not `cog`'s.

## Completion

When all rounds are done, set each round `done` in this plan's `queue-rounds.yaml` and set this plan `done`
in the top-level `.implementation-plans/queue-plans.yaml`. Nothing moves on disk.
