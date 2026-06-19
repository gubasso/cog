# Migrate the live `.implementation-plans/` data to the new format and reconcile the sibling plans

> Plan: refactor-plan-writer-family | Round: 6 of 6 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Rounds 1–5 land the new convention in the **product** (spec, cog mechanics, producer skills, the
`plan-queue-runner` consumer, docs, and tests): every plan is a directory, rounds are uncapped, the
two-layer decomposition is in effect, and the queue files are `queue-plans.yaml` (root) /
`queue-rounds.yaml` (inner). Through Rounds 1–5 the **live** `.implementation-plans/` data is left in
the OLD format on purpose, so the in-flight runner driving this plan keeps working (it pins its queue
path once and passes it explicitly — see the plan README "Why a dedicated final round").

This final round brings the live data into alignment with the now-migrated product and reconciles the
text of the sibling plans so they describe the new code state. It is **status-preserving** (no
round/plan status is lost or changed except the two flips this round itself owns).

**Run this round DIRECTLY**, not via `/plan-queue-runner`:

```bash
/prex -ar .implementation-plans/plans/refactor-plan-writer-family/migrate-live-plans.md
```

This round renames the very queue files a directory-level runner pins at setup (this plan's own inner
queue and the root ledger), so driving it through `plan-queue-runner` would break the runner's
post-round status read. The plan README documents this direct-invocation path as robust to the
rename. The round body runs **no git commands**; commit afterward with `/gc -a` (mirroring the
dir-runner's commit step).

## Previous Rounds

Round 1 rewrote the external spec; Round 2 renamed the cog mechanics (`cmd_plan_init.sh`,
`cmd_plan_queue_runner_setup.sh`, `fn_queue.sh`, the reserved-slug guard in `cmd_plan_slug.sh`); Round
3 rewrote the producer skills (and removed the EF-sanity gate); Round 4 updated the
`plan-queue-runner` consumer + docs + a superseding ADR; Round 5 updated the tests and proved the
product green. The product now reads/writes `queue-plans.yaml` / `queue-rounds.yaml` and knows only
directory plans. The live `.implementation-plans/` data is the last thing still on the old format.

## Scope of This Round

- **IN scope:** the live `.implementation-plans/` tree only — the root ledger, the four directory
  sibling plans, the two single-file sibling plans (converted to directories), the live
  `.implementation-plans/README.md`, and this plan's own inner queue (migrated last).
- **OUT of scope:** product code, skills, docs, tests, and the external satellite repo — all already
  handled in Rounds 1–5. Do not re-touch them here.

### Reconcile depth (settled)

**Mechanical + targeted.** Do every mechanical rename (queue-file references, execution-discipline
prose, final-step status-flip targets, root-ledger entries) and convert the two single-file plans to
directories. Additionally correct only the specific design statements that are plainly *wrong*
against the new code (single-file format, format-detection, `max_rounds` capping). Preserve each
plan's core intent; if a statement cannot be reconciled without changing what the plan intends to
implement, **flag it in the round summary** rather than silently rewriting it.

`skills-under-skills-env-first` is already fully `done`: rename its inner queue and fix only
load-bearing references; **leave its completed narrative as-is** (historical record).

## Current State

### Live `.implementation-plans/` inventory (before this round)

- Root ledger: `.implementation-plans/QUEUE.yaml`; index: `.implementation-plans/README.md`.
- Directory plans (each has inner `QUEUE.yaml` + `README.md` + round files):
  `cog-contract-and-spec-uplift/`, `plan-queue-runner-main-revision/`,
  `cog-self-contained-skill-refs/`, `skills-under-skills-env-first/` (all rounds `done`), and this
  plan `refactor-plan-writer-family/`.
- Single-file plans: `man-page-sync-precommit-hook.md`, `robust-plan-slug-stopword-aware.md`.

### Targeted-semantic spots (reconcile, do not just rename)

- `plan-queue-runner-main-revision/README.md` — the "target may be (a) a single plan file; (b) a
  directory with one round file …; (c) a directory with a multi-round inner `QUEUE.yaml`" list, the
  `QUEUE.yaml -> single_round_dir; single file -> single_file` format-detection mapping, and any
  `max_rounds` round-cap framing. Reconcile to the directory-only / uncapped model while preserving
  the plan's feature intent (main-queue support + plans-revision boundary). Flag irreducible conflicts.
- `robust-plan-slug-stopword-aware` — its references to editing the three `plan-writer` SKILL.md files
  (`skills/claude/plan-writer`, `skills/claude/plan-writer-multi`, `skills/codex/plan-writer`); align
  them to the post-Round-3 skill structure/filenames where stale.

### Existing patterns

- Status values: `backlog | todo | doing | done`. Inner queues may carry a top-level `repos:` list
  before `rounds:` (e.g. `skills-under-skills-env-first` → `/home/gbasso/.dotfiles`); preserve it
  verbatim on rename.
- Markdown fenced code blocks must declare a language (`text` when none applies). `just lint` =
  `pre-commit run --all-files`. **Run no git commands.**

## Implementation Steps

### First Step: Mark this round as started

In this plan's `QUEUE.yaml` (still named `QUEUE.yaml` at this point), set this round's
(`item: migrate-live-plans`) `status` to `doing`.

### Step 1: Migrate the directory sibling plans

For each of `cog-contract-and-spec-uplift`, `plan-queue-runner-main-revision`,
`cog-self-contained-skill-refs`, and `skills-under-skills-env-first`:

- Rename the inner queue: `mv plans/<slug>/QUEUE.yaml plans/<slug>/queue-rounds.yaml`. Preserve the
  file contents byte-for-byte (all round statuses, any `repos:` block).
- Reconcile load-bearing references in that plan's `README.md` and round files:
  - inner-queue prose `QUEUE.yaml` → `queue-rounds.yaml` (e.g. "Read this plan's `QUEUE.yaml`",
    "the authoritative order and status live in `QUEUE.yaml`", "In this plan's `QUEUE.yaml`, set this
    round's status …");
  - root-ledger prose `.implementation-plans/QUEUE.yaml` → `.implementation-plans/queue-plans.yaml`
    (e.g. the Final-Step "set this plan's status to `done` in the top-level …").
- For `skills-under-skills-env-first` only: stop here (file rename + load-bearing refs); leave the
  rest of its completed narrative untouched.
- For `plan-queue-runner-main-revision`: additionally apply the targeted-semantic reconciliation noted
  in Current State (format-detection list/mapping, `max_rounds`). Preserve intent; flag conflicts.

### Step 2: Convert the two single-file plans to directories

For each of `man-page-sync-precommit-hook.md` and `robust-plan-slug-stopword-aware.md` (slug = the
filename without `.md`):

- Create `plans/<slug>/`. Split the single file into:
  - `README.md` — the record sections (Problem Statement, Decisions & Constraints, Rejected
    Alternatives, Current State, Acceptance Criteria, Risks). Replace the `| Single-file plan |`
    metadata line with directory metadata (`> Plan: <slug> | Complexity: <grade> | Rounds: 1 |
    Generated: <date> | Repo: /workspaces/cog`). Add a brief "Rounds" overview pointing at the one
    round file and an Execution Discipline note (one round per `/prex` session).
  - one round file `<round-slug>.md` — the Implementation Steps body, with a `> Plan: <slug> | Round:
    1 of 1 | …` header.
  - `queue-rounds.yaml` — one `rounds:` entry: `item: <round-slug>`, `status:` (carry over the plan's
    current root-ledger status), `depends_on: []`, `prompt: /prex -ar
    .implementation-plans/plans/<slug>/<round-slug>.md`, `notes:` (carry the plan's gist).
- Rewrite the round file's First/Final Step:
  - First Step → "In this plan's `queue-rounds.yaml`, set this round's (`item: <round-slug>`)
    `status` to `doing`."
  - Final Step → "1. In this plan's `queue-rounds.yaml`, set this round's `status` to `done`. 2. All
    rounds are now done, so in the top-level `.implementation-plans/queue-plans.yaml` set this plan's
    (`item: <slug>`) `status` to `done`." Remove the old "There is no inner queue" sentence.
- For `robust-plan-slug-stopword-aware`: apply the targeted SKILL.md-reference reconciliation from
  Step 1's notes while splitting.
- Remove the original `plans/<slug>.md` once the directory is in place.

### Step 3: Migrate the root ledger and the live index

- `mv .implementation-plans/QUEUE.yaml .implementation-plans/queue-plans.yaml`.
- In `queue-plans.yaml`, update the two converted entries (preserving `status`, `depends_on`,
  `notes`):
  - `item: man-page-sync-precommit-hook.md` → `item: man-page-sync-precommit-hook`;
    `prompt: /prex -ar .implementation-plans/plans/man-page-sync-precommit-hook.md` →
    `/prex -ar @.implementation-plans/plans/man-page-sync-precommit-hook/`.
  - `item: robust-plan-slug-stopword-aware.md` → `item: robust-plan-slug-stopword-aware`;
    `prompt: /prex -ar .implementation-plans/plans/robust-plan-slug-stopword-aware.md` →
    `/prex -ar @.implementation-plans/plans/robust-plan-slug-stopword-aware/`.
- Leave all other entries (including `depends_on` references to those two slugs, if any) consistent;
  no other entry references the `.md` form.
- Reconcile `.implementation-plans/README.md`: "either a single self-contained markdown file or a
  directory containing round files and an inner `QUEUE.yaml`" → "a directory containing round files
  and an inner `queue-rounds.yaml`"; the root source-of-truth `QUEUE.yaml` → `queue-plans.yaml`.

### Step 4: Self-migrate this plan last

- `mv plans/refactor-plan-writer-family/QUEUE.yaml plans/refactor-plan-writer-family/queue-rounds.yaml`.
- Reconcile any inner-queue prose in this plan's own `README.md` / round files that still says
  `QUEUE.yaml` for the inner queue → `queue-rounds.yaml`, and `.implementation-plans/QUEUE.yaml` for
  the root → `queue-plans.yaml`. (The README "Scaffolding vs. deliverable" section explains why this
  self-migration happens here, in the final round.)

### Final Step: Update the queue

1. In this plan's now-renamed `queue-rounds.yaml`, set this round's (`item: migrate-live-plans`)
   `status` to `done`.
2. All rounds are now done, so in the top-level `.implementation-plans/queue-plans.yaml` set this
   plan's (`item: refactor-plan-writer-family`) `status` to `done`. Nothing moves on disk beyond the
   renames performed above.

### Gate

Run `just lint` (`pre-commit run --all-files`) and resolve any markdownlint findings (e.g. MD040
fenced-block languages) on the new/renamed live plan files. The round is complete only when lint is
green. If a hook fails for a pre-existing, unrelated reason, capture the exact output and the most
focused fallback, and record it in the round summary.

## Acceptance Criteria

- [ ] No `QUEUE.yaml` remains anywhere under `.implementation-plans/` (root or any plan dir).
- [ ] `.implementation-plans/queue-plans.yaml` exists; the two former single-file plans appear as
      directory entries (`item` without `.md`, `prompt` of the `@.../<slug>/` form), all other entries
      unchanged.
- [ ] `man-page-sync-precommit-hook/` and `robust-plan-slug-stopword-aware/` are directories with
      `README.md`, one round file, and `queue-rounds.yaml` (round status carried over).
- [ ] Every sibling directory plan has `queue-rounds.yaml` (not `QUEUE.yaml`); all prior round statuses
      preserved; `skills-under-skills-env-first` still shows its rounds `done`.
- [ ] No live plan text references `QUEUE.yaml` as a filename, the single-file format, format-detection
      by file vs dir, or `max_rounds` capping (except intentional history flagged in the summary).
- [ ] This plan's `queue-rounds.yaml` shows `migrate-live-plans` as `done`; the root
      `queue-plans.yaml` shows `refactor-plan-writer-family` as `done`.
- [ ] `just lint` passes (or a documented focused fallback for a pre-existing unrelated failure).

## Next Round

This is the final round.
