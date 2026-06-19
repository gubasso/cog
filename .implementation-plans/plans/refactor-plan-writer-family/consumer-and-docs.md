# Update the queue consumer, cog docs, and record a superseding ADR

> Plan: refactor-plan-writer-family | Round: 4 of 5 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

`plan-queue-runner` is the CONSUMER that drives a directory plan from its inner queue — it
reads/selects rounds by filename, so the inner rename (`QUEUE.yaml` → `queue-rounds.yaml`) breaks it
unless updated. Several cog docs/ADRs also reference the queue postcondition by the old name. Finally,
the format change (retire single-file) + uncapped rounds + two-layer decomposition + queue rename is a
decision-worthy change: per AGENTS.md a changed architectural decision is recorded as a **NEW
superseding ADR** (accepted ADRs are never deleted).

Do NOT rename this plan's own `QUEUE.yaml` (see the plan README's "Scaffolding vs. deliverable").

## Previous Rounds

Round 1 rewrote the external spec. Round 2 renamed the cog mechanics (incl.
`cmd_plan_queue_runner_setup` resolving `queue-rounds.yaml` and the generalized `fn_queue.sh` error
strings). Round 3 rewrote the producer skills for the directory-always / uncapped / two-layer model
and new filenames (and removed the `plan-writer-multi` EF-sanity gate). The consumer + docs must now
align.

## Scope of This Round

- **IN scope:** `plan-queue-runner/SKILL.md` (inner-filename reads/selects), cog docs that name the
  queue postcondition, the `docs/README.md` index, and a new superseding ADR.
- **OUT of scope:** the test blast radius (Round 5) and any live `.implementation-plans/` data.

## Current State

### Key Files

- `/workspaces/cog/skills/claude/plan-queue-runner/SKILL.md` (~275 lines). Drives a directory plan
  from its inner queue. References `QUEUE.yaml` throughout: the frontmatter `description`, the prose,
  the Multi-Repo `repos:` example, the Algorithm, the dry-run selection
  `yq e -r '.rounds[] | select(.status == "todo") | "- " + .item + ": " + .prompt' "$QUEUE_PATH"`, the
  verify snippets `ITEM="$ITEM" yq e -r '.rounds[] | select(.item == strenv(ITEM)) | .status'
  "$QUEUE_PATH"`, the Usage examples (`/plan-queue-runner .../QUEUE.yaml`), and the Rules ("Never
  write `QUEUE.yaml`", "no `yq -i` ... to the queue path"). It calls `cog plan-queue-runner-setup`,
  whose normalization was already updated in Round 2 to resolve `queue-rounds.yaml`. It already
  supports an optional top-level `repos:` list in the inner queue (clean-tree guard + `/gc -a --repo
  <sat>` cover every declared repo). Update all inner-queue references to `queue-rounds.yaml`.
- `/workspaces/cog/docs/reference/orchestration-contract.md` — documents the postcondition
  "`QUEUE.yaml` status == done" (~line 49). Update to the appropriate filename: the inner round
  postcondition is `queue-rounds.yaml`; the top-level plan postcondition is `queue-plans.yaml` —
  disambiguate per context.
- `/workspaces/cog/docs/decisions/0007-in-session-subagent-delegation.md` — references queue
  completion (~line 26). Update the filename reference only (do not rewrite the ADR's decision).
- `/workspaces/cog/docs/README.md` — Diataxis index. May enumerate ADRs / reference docs; update if it
  lists the new ADR or the changed reference doc.

### Existing Patterns

- ADRs live in `docs/decisions/`; accepted ADRs are never deleted — add a NEW ADR that supersedes the
  prior decision and cross-link both directions. Use the repo's ADR format and the next number in
  sequence (inspect existing `docs/decisions/NNNN-*.md` to find the format and the next number; ADR
  0008 is `0008-skill-script-boundary.md`).
- Skills keep judgment in prose; mechanics in cog. The `yq` selection in `plan-queue-runner` reads
  from the path that `cog plan-queue-runner-setup` resolves — keep prose and mechanics consistent.
- `docs/README.md` is an **index only** (no content beyond pointers).

## Implementation Steps

### First Step: Mark this round as started

In this plan's `QUEUE.yaml`, set this round's (`item: consumer-and-docs`) `status` to `doing`.

### Step 1: Update `plan-queue-runner/SKILL.md`

- Replace every inner-queue reference `QUEUE.yaml` with `queue-rounds.yaml`: the frontmatter
  `description`, the prose, the `repos:` example, the Algorithm, the `yq` dry-run + verify selections
  (`.rounds[]` selections operate on `$QUEUE_PATH`), the Usage examples, and the Rules. Confirm the
  `cog plan-queue-runner-setup` target examples accept a bare plan dir (now resolves
  `queue-rounds.yaml`) and an explicit `.../queue-rounds.yaml` path. Keep the `repos:` satellite
  handling intact.
- Run `cog skill-lint` on the touched SKILL.md.

### Step 2: Update cog docs

- `docs/reference/orchestration-contract.md`: update the queue-postcondition wording to the new
  filename(s), disambiguating inner (`queue-rounds.yaml`) vs top-level (`queue-plans.yaml`).
- `docs/decisions/0007-in-session-subagent-delegation.md`: update the queue-completion filename
  reference only.

### Step 3: Record a superseding ADR

- Add a new ADR in `docs/decisions/` (next number in sequence, repo ADR format) recording the changed
  decisions: every plan is a directory (single-file format / Template E retired); the round cap is
  removed (round count is scope-driven and uncapped); the two-layer decomposition (Layer 1 domain
  split → flat sibling dirs via top-level `depends_on`; Layer 2 per-dir grade → uncapped rounds) is
  adopted; and the queue files are renamed to `queue-plans.yaml` (root) / `queue-rounds.yaml` (inner).
  Mark it as **superseding** whichever prior ADR(s) established the single-file / capped-round /
  `QUEUE.yaml` decisions (search `docs/decisions/` for the relevant ADR; cross-link both directions).
  Do NOT delete the superseded ADR.
- Update `docs/README.md` if it enumerates ADRs or reference docs.

### Final Step: Update the queue

1. In this plan's `QUEUE.yaml`, set this round's (`item: consumer-and-docs`) `status` to `done`.

## Acceptance Criteria

- [ ] `plan-queue-runner` reads/selects rounds from `queue-rounds.yaml`; no `QUEUE.yaml` literal
      remains in it; `cog skill-lint` passes.
- [ ] `docs/reference/orchestration-contract.md` and `docs/decisions/0007-*.md` reference the new
      filenames.
- [ ] A new superseding ADR records the format change + uncapped rounds + two-layer model + rename and
      cross-links the prior ADR (which is NOT deleted); `docs/README.md` updated if it indexes ADRs.
- [ ] This plan's `QUEUE.yaml` shows round `consumer-and-docs` as `done`.

## Next Round

Round 5 updates the full test blast radius (24 references), including the literal-path assertions in
`plan_init.bats` and `plan_queue_runner_setup.bats`, sweeps the repo for stale references, and runs
`just lint` + `just test`.
