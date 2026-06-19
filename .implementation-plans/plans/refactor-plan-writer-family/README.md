# Refactor the plan-writer / plan-writer-multi skill family

> Complexity: L (override: 6 rounds) | Rounds: 6 | Generated: 2026-06-19 | Repo: /workspaces/cog |
> Satellite repo: /home/gbasso/DocsNNotes | Executor: prex (EF 1.5)

## Problem Statement

The `plan-writer` skill family — Claude `plan-writer`, its read-only Codex twin, and the Claude-only
`plan-writer-multi` coordinator — generates implementation plans under `.implementation-plans/`,
which `/runner-queue` then drives. Four capability/naming changes are needed:

1. **Retire single-file plans.** Today S/M-grade plans are written as a single file
   `plans/<slug>.md` and L/XL plans as a directory `plans/<slug>/`. **Every implementation plan must
   now be a directory** — even a one-round plan is a directory with its own inner queue. The
   single-file format ("Template E") is removed.
2. **Remove the round cap.** Round count is currently bounded: the complexity grade derives the round
   count (S/M=1, L=2–3, XL=4–8), and under the default `prex` executor the Executor Factor (1.5)
   caps the reachable grade at **L** (the 5-axis score saturates at 20; 20 ÷ 1.5 = 13.3), so a `prex`
   plan tops out at **3 rounds**. A plan directory may now have **as many rounds as the work needs**.
   Round count is driven by scope/cohesion, not by the grade or the EF ceiling. Each round stays a
   good `/prex` chunk: never so small that spinning up a `/prex` session is wasteful, never so big it
   exceeds one Codex 600s session / one cohesive write session (~under 300 lines of plan text).
3. **Two-layer decomposition (new model).** Layer 1 groups the requested tasks by **domain/scope**
   into cohesive groups; each group becomes ONE implementation dir (one domain → one dir; N domains →
   N **flat sibling** dirs under `plans/`, related via the top-level queue's `depends_on` plus a
   shared slug prefix). Layer 2 grades the difficulty of each group (keep S/M/L/XL and the 5 scoring
   axes) and splits it into rounds — as many as needed, **uncapped**. The grade is **retained** but
   is now per-dir and descriptive: it informs round sizing/reasoning; it no longer selects a format
   (everything is a dir) and no longer caps round count.
4. **Hard queue rename.** Root `.implementation-plans/QUEUE.yaml` → `queue-plans.yaml`; inner
   `plans/<slug>/QUEUE.yaml` → `queue-rounds.yaml`. **Hard cut** everywhere the product references
   the filename (skills, cog commands, tests, the external spec). No dual-read shim in the product.
   The live on-disk `.implementation-plans/` data is **migrated by this plan's final round**
   (`migrate-live-plans`) — after all product code is renamed — not left to a manual step.

The complexity heuristic, lifecycle spec, and templates are the **single source of truth** for the
grade table, round rules, grade→format mapping, and templates — and they live in a **separate repo**
(`$DOCS_NOTES_REPO` = `/home/gbasso/DocsNNotes`, under `tech/tools/claude-code/plan-rounds/`). So
features #1–#3 are primarily edits THERE. This makes the work a **two-repo change**: the plan repo is
`/workspaces/cog`; the satellite spec repo is `/home/gbasso/DocsNNotes`.

## Strategy

Split bottom-up so foundations land before consumers, in six cohesive `prex` rounds:

1. **`spec-rewrite`** (satellite repo) — rewrite the three external plan-rounds references (the source
   of truth all skills + cog README text point at): directory-only, two-layer model, uncapped rounds,
   retire single-file/Template E, and the queue rename in the spec/templates.
2. **`cog-mechanics-rename`** — rename the hardcoded queue filename + generalize error strings in
   cog's deterministic mechanics; update the reserved-slug guard for the new meta stems.
3. **`skills-rewrite`** — update the producer skills (`plan-writer`, the Codex twin,
   `plan-writer-multi`) to the directory-always / uncapped / two-layer model and the new filenames;
   **remove the `plan-writer-multi` EF-sanity gate** that auto-rejects 4+ prex rounds.
4. **`consumer-and-docs`** — update the consumer `runner-queue` + cog docs, and record a new
   superseding ADR.
5. **`tests-and-gates`** — update the 24-reference test blast radius, sweep for stale references, and
   prove the change green via `just lint` + `just test`.
6. **`migrate-live-plans`** — with all product code now on the new convention, migrate the live
   `.implementation-plans/` data to the new format (rename root + inner queues, convert single-file
   plans to directories) and reconcile the sibling plans' text to the new code state. Run **directly**
   (not the dir-runner); self-migrate this plan + the root ledger last.

This order keeps the self-referencing tooling coherent: spec → mechanics → producers → consumer/docs
→ tests → live-data migration. The live migration is deliberately isolated to the final round so the
live data stays old-format (and the in-flight runner keeps working) until every product round lands.

## Rounds

The authoritative order and status live in this plan's `queue-rounds.yaml`. Overview:

1. `spec-rewrite.md` — rewrite the external plan-rounds spec (satellite repo `/home/gbasso/DocsNNotes`).
2. `cog-mechanics-rename.md` — rename queue filename literals + generalize error strings in cog; update the reserved-slug guard.
3. `skills-rewrite.md` — update `plan-writer`, the Codex twin, and `plan-writer-multi` to the new model and filenames.
4. `consumer-and-docs.md` — update `runner-queue` + cog docs; record a superseding ADR.
5. `tests-and-gates.md` — update the test blast radius; stale-reference sweep; `just lint` + `just test`.
6. `migrate-live-plans.md` — migrate the live `.implementation-plans/` data + reconcile sibling plans; run directly.

## Execution Commands

```bash
# Execute the next todo round (executor reads this plan's queue-rounds.yaml, runs the first `todo` round, then stops):
/prex -ar @.implementation-plans/plans/refactor-plan-writer-family/

# Or target a specific round file directly (robust to the queue rename mid-execution — see Risks):
/prex -ar .implementation-plans/plans/refactor-plan-writer-family/spec-rewrite.md
```

The **final round (`migrate-live-plans`) MUST be run directly** with `/prex -ar
.implementation-plans/plans/refactor-plan-writer-family/migrate-live-plans.md` — it renames the queue
files a directory-level `/runner-queue` pins at setup, so driving it through the dir-runner would
break the runner's post-round status read.

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for a
single `/prex` session. Do not implement multiple rounds in one session.

When `/prex` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh `/prex` session is launched for any subsequent round.

Rounds 1–5 may be driven by `/runner-queue` (it pins the queue path at setup and passes it
explicitly, so it keeps working even after Round 2 renames the cog literals). **Round 6
(`migrate-live-plans`) must instead be invoked directly** with `/prex -ar
.implementation-plans/plans/refactor-plan-writer-family/migrate-live-plans.md`, because it renames
this plan's own inner queue and the root ledger as its final act — the files the dir-runner would
pin. Commit it with `/gc -a` afterward (the round body runs no git).

## Scaffolding vs. deliverable (READ THIS — prevents a self-rename mistake)

This plan's OWN scaffolding deliberately started on the **old** convention — through Rounds 1–5 this
plan's inner queue was `QUEUE.yaml` and it was registered in the then-old-format root ledger
`.implementation-plans/QUEUE.yaml` — because the plan runs under the **pre-refactor** tooling and
shares the live root ledger with other in-flight plans. The **deliverable** (what the rounds install)
is the **new** convention (`queue-plans.yaml` / `queue-rounds.yaml`) in the spec, cog code, skills,
docs, and tests.

Therefore: when **Rounds 1–5** say "rename `QUEUE.yaml` → `queue-rounds.yaml`", they mean **in the cog
product / spec / tests** — **NOT** this plan's own (then) `.implementation-plans/.../QUEUE.yaml` and
**NOT** the live root ledger. Rounds 1–5 do NOT rename or move any live `.implementation-plans/`
queue/status file; the live tree stays old-format so the in-flight runner keeps working.

The **live migration is the job of Round 6 (`migrate-live-plans`)**, run last and directly: it
migrates every live plan to the new format and, as its final act, self-migrates this plan's own queue
(`QUEUE.yaml` → `queue-rounds.yaml`) and the root ledger (`.implementation-plans/QUEUE.yaml` →
`queue-plans.yaml`). This supersedes the original Q4 stance that the user migrates live data manually.

## Decisions & Constraints

- **`Executor: prex (EF 1.5)`.**
- **Queue filenames (settled, supersedes the orientation):** root = `queue-plans.yaml`, inner =
  `queue-rounds.yaml`. The orientation's `queue.yaml` / `in-queue.yaml` was superseded in interview
  Q1.
- **Every plan is a directory.** Single-file format (Template E) is removed entirely. Even a
  one-round plan is a directory with `README.md`, round file(s), and an inner `queue-rounds.yaml`.
- **Rounds uncapped.** Round count is driven by scope/cohesion. The grade no longer caps rounds and
  no longer selects a format. Remove the per-grade round ceiling and the "XL unreachable under prex /
  recompute if 4+ rounds" mechanic from the spec.
- **Two-layer decomposition.** Layer 1 = domain/scope split → one or more flat sibling dirs under
  `plans/`, related via top-level `depends_on` + shared slug prefix. Layer 2 = per-dir grade + round
  split. (Q2/Q3.)
- **Hard cut rename (Q4, revised):** rename everywhere the **product** references the filename; no
  dual-read shim. The live `.implementation-plans/` data is migrated by the final round
  (`migrate-live-plans`), run directly and status-preserving, after all product rounds land — it is
  no longer a manual user step. (This revises the original Q4 stance.)
- **Multiple dirs are flat siblings** under `plans/` (no nested program/epic folder); reuse the
  existing top-level `plans:` queue machinery — it already supports multiple entries with
  dependencies (Q3).
- **Skills in scope:** `skills/claude/plan-writer`, `skills/codex/plan-writer` (read-only twin),
  `skills/claude/plan-writer-multi`, plus the coupled consumer `skills/claude/runner-queue`.
  There is NO `skills/codex/plan-writer-multi` (the multi coordinator is Claude-only).
- **Repo conventions (CLAUDE.md / AGENTS.md):** skills keep judgment/sequencing in prose;
  deterministic mechanics live in `cog` subcommands and `cog::fn::*` helpers (ADR 0008). Validate
  skill edits against `docs/reference/skill-contract.md` and run `cog skill-lint` on touched
  SKILL.md files. Pre-commit is the quality gate (`just lint` = `pre-commit run --all-files`;
  `just test` = unit + integration). Accepted ADRs are never deleted — record the changed decision
  with a NEW superseding ADR. Markdown fenced code blocks must declare a language. **Do not run git
  commands.**
- **Round-count override for THIS plan:** raw 18 ÷ EF 1.5 = 12.0 → grade **L**. The legacy L cap of 3
  rounds is intentionally **NOT** applied — removing that cap is the work itself. 6 cohesive rounds
  are used (the five product rounds plus the live-data migration), each sized as a good `/prex` chunk;
  6 > 3 dogfoods the headline uncap. (Per `complexity-heuristic.md` override guidance: documented here
  with reason.)

## Rejected Alternatives

- **`queue.yaml` / `in-queue.yaml` filenames (the orientation's first proposal).** Rejected in Q1 in
  favor of `queue-plans.yaml` / `queue-rounds.yaml`, which name the schema, are self-describing, and
  sort together.
- **Dual-read compatibility shim in the product.** Rejected — hard cut; the product reads only the new
  names. (A runtime shim stays rejected; the live data is instead brought forward by the one-time
  scripted final round.)
- **Manual user migration of live `.implementation-plans/` data (original Q4 stance).** Superseded by
  this revision: the final round `migrate-live-plans` performs the migration deterministically, run
  directly and status-preserving, so the repo is never left half-migrated.
- **Nested program/epic folder for multiple plan dirs.** Rejected in Q3 — flat sibling dirs related
  via the top-level queue's `depends_on` reuse existing machinery and avoid a new hierarchy that
  would break the one-level `plans/<slug>/` path assumption in `runner-queue` and `/prex`.
- **Keeping single-file plans for S/M.** Rejected — every plan is a directory now; uniform structure
  simplifies the consumer (`runner-queue` always reads an inner queue) and the two-layer model.
- **Splitting this refactor into two plan dirs by repo boundary.** Considered (it isolates the
  satellite `repos:` cleanly and dogfoods multi-dir) but rejected: this is one cohesive refactor of
  one subsystem; the spec change is not independently shippable; and a single 5-round dir both keeps
  execution to one runner invocation and demonstrates the headline uncap (5 > 3). (Confirmed in the
  Phase-8 re-interview.)
- **Forcing this plan down to ≤3 rounds to satisfy the legacy prex cap.** Rejected — that cap is what
  this work removes; honoring it here would contradict the brief.

## Risks & Edge Cases

- **Self-reference / bootstrap hazard (accepted, handled).** This plan is executed by
  `/runner-queue` + `/prex`, which read THIS plan's own queue *by filename*. Round 2 edits the
  cog code that resolves the inner-queue filename, and Round 6 renames the live queue files
  themselves. Mitigations: (a) through Rounds 1–5 this plan's own queue stays `QUEUE.yaml` and the
  live root ledger is untouched (see "Scaffolding vs. deliverable"); (b) the loop pins `QUEUE_PATH` at
  runner setup, so a runner already in flight keeps working after Round 2; (c) if you RESTART the
  dir-level runner after Round 2 lands with updated cog, run remaining rounds directly with `/prex -ar
  <round-file>.md` (selection does not depend on the queue filename); (d) **Round 6 is always run
  directly**, never via the dir-runner — it renames this plan's own queue and the root ledger as its
  final act, so there is no pinned-path post-round read left to break. Round 6 writes its two `done`
  flips into the already-renamed files.
- **Two repos (handled).** Round 1 edits `/home/gbasso/DocsNNotes` (satellite-repo work). This plan's
  inner queue declares `repos: [/home/gbasso/DocsNNotes]` so `/runner-queue`'s clean-tree guard
  and `/gc -a --repo /home/gbasso/DocsNNotes` cover the satellite. Rounds 2–5 do not touch the
  satellite; `/gc` on its clean tree is a no-op for those rounds. Keep `/home/gbasso/DocsNNotes`
  clean at the start of every round (the startup guard requires it).
- **Dependency order (handled).** External spec edits are foundational to skill/cog edits — Round 1
  precedes Rounds 2–5 via `depends_on`.
- **Reserved-slug collision (handled in Round 2).** New meta filename stems are `queue-plans` /
  `queue-rounds`; the reserved-slug guard (currently `readme`, `queue`, `strategy`) is extended so a
  plan slug or round topic cannot collide with the new meta files.
- **Live on-disk plans (in scope via Round 6, status-preserving).** The live root ledger
  `.implementation-plans/queue-plans.yaml` and existing plans (including single-file `.md` plans like
  `man-page-sync-precommit-hook.md`) keep the old name/format through Rounds 1–5, then Round 6
  migrates them: rename the root + inner queues, convert the two single-file plans to directories, and
  reconcile sibling-plan text (mechanical + targeted) to the new code state. Round 6 preserves every
  existing round/plan status; the already-`done` `skills-under-skills-env-first` is renamed but its
  narrative is left as history.

## Completion

The plan is complete when Round 6 (`migrate-live-plans`) finishes. By then the live tree has been
migrated, so the final bookkeeping lands in the **renamed** files: set `migrate-live-plans` `done` in
this plan's `queue-rounds.yaml` and set this plan (`item: refactor-plan-writer-family`) `done` in the
top-level `.implementation-plans/queue-plans.yaml`. (Rounds 1–5 each flip only their own round status
in this plan's then-current `QUEUE.yaml`; the plan-level `done` flip is Round 6's, in the renamed
ledger.) The only on-disk movement is the Round-6 renames.
