# Rename plans-revision → review-implementation-plans (Skill + cog Commands), Apply opus/low, Add Queue Ordering/Dependency Review

> Plan: model-effort-policy-and-rename | Round: 3 of 3 | Complexity: XL | Generated: 2026-06-19 |
> Repo: /workspaces/cog

## Context

The project-local skill `plans-revision` reconciles implementation-plan queues with repo state after
a committed runner-queue item. It is the **only** skill using `model: sonnet` (+ `effort:
high`) — the outlier the new model/effort policy retires. This round performs the atomic rename of
that skill **and its sibling `cog` commands** to `review-implementation-plans`, and re-grades the
skill to `model: opus` + `effort: low` (the canonical "never sonnet → opus+low" worked example).

**This round also expands what the skill does.** Today the skill is **append-only and explicitly
forbids reordering** (workflow step 6: "Do not reorder existing entries"); it marks items done,
revises mutable prose, and appends newly discovered gaps, but never touches execution order or the
dependency wiring of existing items. Per user direction the renamed skill must additionally **review
queue execution order and dependencies and adjust them for better sequential execution**, at both
queue levels (the top-level `plans` queue and each plan's inner `rounds` queue). Concretely the
revision pass becomes two reviewed-and-committed phases:

1. **Review plans + commit** — reconcile each plan against the current codebase (existing behavior),
   then run the `/gc` skill (commit A).
2. **Review queue + commit** — review queue ordering + dependencies and adjust **mutable**
   (`todo`/`backlog`) items, then run the `/gc` skill (commit B).

Because execution order is derived from **list position + `depends_on`** (the selector picks the
first `todo` in list order whose `depends_on` are all `done`), "adjust ordering" needs **two levers**:
edit `depends_on` of mutable items **and** physically reorder mutable items. Both are deterministic
YAML mutations, so per CLAUDE.md / ADR-0008 they **must be new guarded `cog` subcommands**, never
freehand edits (the skill's own "Never mutate a queue by direct editing" rule already requires this).
There is also **no dependency-graph validator today** (cycle / dangling-ref detection), so this round
adds one.

The rename itself is still treated as **one atomic change** (skill + commands + every reference) so
the repo never sits in a half-renamed state; its blast radius is wide but mechanical, driven by
grepping rather than a fixed list. The added behavior + new commands + verify/ADR/runner changes make
this round **significantly heavier than a pure rename** — sequence the new mechanics first, then the
rename, so the new commands exist under their final `queue-*` names from the start.

## Previous Rounds

- `research-current-model-data` produced dated evidence references in `docs/reference/`.
- `model-effort-policy-sot` authored `docs/reference/model-effort-policy.md`, the two descriptive
  TOML data files in `docs/reference/`, the policy ADR (the "never sonnet → opus+low" rule), and
  AGENTS.md/CLAUDE.md wiring.
  This round's re-grade of the skill to opus/low is the policy's first application; cite the policy
  ADR in the skill's frontmatter rationale or commit message.

## Scope of This Round

- IN scope:
  - **Rename** the skill directory `.claude/skills/plans-revision/` → `.claude/skills/
    review-implementation-plans/`; set frontmatter `name: review-implementation-plans`, `model:
    opus`, `effort: low`; update its trigger-tests and any in-body command references.
  - **Rename** the `cog` commands `plans-revision-scan` / `plans-revision-verify` →
    `review-implementation-plans-scan` / `review-implementation-plans-verify`: command modules,
    handler/self-check identifiers, line-2 `desc:` sentinels, usage/help strings, and (for
    consistency) the internal `fn_plans_revision.sh` helpers.
  - **New queue-ordering mechanics** (generic `queue-*` namespace, alongside `queue-append` /
    `queue-status-set` / `queue-select`):
    - `cog queue-deps-set` — replace one mutable item's `depends_on`.
    - `cog queue-reorder` — deterministically reorder mutable items by stable topological sort of
      `depends_on` (no agent-supplied order).
    - `cog queue-graph-check` — validate dependency graph (existence + acyclicity), report
      blocked/unreachable items.
  - **Extend `review-implementation-plans-verify`**: pin `doing` items like `done`; run the graph
    check on the after-scan (fail closed on cycle/dangling dep); report `deps_changes` + `reordered`.
  - **Expand the skill's workflow**: add a queue-ordering review phase, rewrite the no-reorder
    guardrail, adopt the two-`/gc`-commit cadence, list the new commands in the Cog Contract.
  - **Superseding ADR** for the revision-boundary contract change (two commits + order-adjusting
    mutable items); update `runner-queue/SKILL.md` accordingly.
  - Update every reference: `runner-queue/SKILL.md`, ADR-0012, `docs/reference/cli-commands.md`,
    completions, man page, integration tests, and help snapshots.
  - Regenerate completions + man + help snapshots; run `cog skill-lint` and the integration suite.
  - **Gated final cleanup:** after everything above verifies, delete the now-superseded model-
    reference files from `$DOCS_NOTES_REPO` (the in-cog replacements were authored in Rounds 1–2).
- OUT of scope:
  - **Behavior changes beyond queue ordering review** — only the ordering/dependency review (via the
    three named `queue-*` commands), the two-commit cadence, and the rename/re-grade. The skill's
    plan-reconciliation logic is otherwise unchanged.
  - Re-grading any *other* skill's frontmatter (deferred beyond this plan).
  - Deleting any DocsNNotes file other than the three model-reference files listed below.

## Current State

### Key Files (rename surface — confirm with grep, do not trust line numbers)

- `/workspaces/cog/.claude/skills/plans-revision/SKILL.md` — line 2 `name: plans-revision`; line 7
  `model: sonnet`; line 8 `effort: high`; `<!-- trigger-tests: "plans-revision", ... -->`; body
  references `cog plans-revision-scan` / `cog plans-revision-verify`; workflow step 6 contains the
  "Do not reorder existing entries" rule and the Guardrails list contains the append-only / no-reorder
  rules to rewrite. It is **project-local** (under `.claude/skills/`, not `skills/claude/`), so
  `install.sh` does not ship it — keep it under `.claude/skills/` after the rename.
- `/workspaces/cog/lib/commands/cmd_plans_revision_scan.sh` — line 2
  `: 'desc: Inventory all implementation-plan queues and repo/plan fingerprints.'`; handler
  `cog::cmd::plans_revision_scan()` (line ~59); self-check var `__cog_plans_revision_scan_self_check`;
  usage string `cog plans-revision-scan ...`.
- `/workspaces/cog/lib/commands/cmd_plans_revision_verify.sh` — line 2
  `: 'desc: Verify a plans-revision against a before/after scan.'`; handler
  `cog::cmd::plans_revision_verify()` (line ~148); self-check var
  `__cog_plans_revision_verify_scan_check`; history-preserved gate
  `__cog_plans_revision_verify_history_preserved` (~lines 62-78) pins **done** items' fields by item
  identity — extend to also pin `doing`, run the graph check, and report `deps_changes`/`reordered`.
- `/workspaces/cog/lib/functions/fn_plans_revision.sh` — helpers `cog::fn::plans_revision_*`
  (`_queue_schema`, `_inventory_json`, `_repo_fingerprint`, `_plans_fingerprint`, …). Internal; rename
  for naming consistency (file → `fn_review_implementation_plans.sh`, functions →
  `cog::fn::review_implementation_plans_*`) and update all callers in the two command modules.
- `/workspaces/cog/lib/functions/fn_queue.sh` — core queue I/O + validation
  (`cog::fn::queue_validate_file`, `cog::fn::queue_select_next_item` ~line 268). **Add** graph-build +
  cycle-detect helpers here for DRY reuse by the three new commands and the verify gate.
- `/workspaces/cog/lib/commands/cmd_queue_append.sh` (append-only byte-prefix-verify pattern) and
  `/workspaces/cog/lib/commands/cmd_queue_status_set.sh` (CAS guard + `yq` edit-in-place + `jq`
  self-check that only one field on one item changed) — **reference patterns** for the three new
  guarded mutation commands. Do not change them.
- `/workspaces/cog/skills/claude/runner-queue/SKILL.md` — ~13 references to the skill name and
  the path `.claude/skills/plans-revision/SKILL.md`, plus references to `cog plans-revision-scan` /
  `-verify` (around lines 10, 56, 346–394). The revision-boundary description must also reflect
  ordering review + up to two commits per boundary.
- `/workspaces/cog/docs/decisions/0012-plan-queue-revision-boundary.md` — prose references to
  `.claude/skills/plans-revision` and `cog plans-revision-verify` (around lines 26–33). **Do not
  rewrite the decision**; update only the path/command-name strings so they resolve. The contract
  change (two commits + order-adjusting) is recorded in a **new superseding ADR**, not here.
- `/workspaces/cog/docs/reference/cli-commands.md` — the two renamed command rows (around lines
  59–60) **plus three new rows** for `queue-deps-set` / `queue-reorder` / `queue-graph-check`.
- `/workspaces/cog/completions/cog.bash`, `/workspaces/cog/man/cog.1`, `/workspaces/cog/man/cog.1.scd`
  — command-name occurrences for the renamed and new commands (regenerated artifacts; prefer
  regenerating over hand-editing).
- `/workspaces/cog/test/integration/plans_revision_scan.bats`,
  `/workspaces/cog/test/integration/plans_revision_verify.bats` — rename the files and update the
  test names/bodies and the command invocations; extend the verify suite for the new behavior. **Add**
  `queue_deps_set.bats`, `queue_reorder.bats`, `queue_graph_check.bats`.
- `/workspaces/cog/test/integration/skills_claude.bats` (line ~133 `assert_file_contains "$file"
  "plans-revision"`) and `/workspaces/cog/test/integration/help_snapshots.bats` (lines ~61–62,
  136–137) — update to the new names; the help-snapshot suite gains the three new command summaries.

### Existing Patterns

- The loader maps a dashed command to `cmd_<slug_with_underscores>.sh` + `cog::cmd::<slug>`. So
  `review-implementation-plans-scan` → `cmd_review_implementation_plans_scan.sh` +
  `cog::cmd::review_implementation_plans_scan`; `queue-deps-set` → `cmd_queue_deps_set.sh` +
  `cog::cmd::queue_deps_set`; likewise `queue-reorder`, `queue-graph-check`.
- Every command module keeps its line-2 `: 'desc: ...'` sentinel (root help, man, completion drift
  checks depend on it).
- Guarded mutation discipline: `yq` edit-in-place + a `jq` self-check asserting **only the intended
  change occurred and every non-mutable item is byte-identical at its original index**, fail-closed
  on any deviation (see `queue-status-set`/`queue-append`).
- Selection semantics: `cog::fn::queue_select_next_item` picks the first `todo` in list order whose
  `depends_on` are all `done`; `depends_on` is gating (a blocked queue is fail-closed). New deps must
  therefore reference existing items and never form a cycle.
- Skill name validation: `^[a-z0-9-]{1,64}$`, not `anthropic`/`claude` (`lib/functions/fn_skill.sh`
  `cog::fn::skill::name_is_valid`). `review-implementation-plans` is valid. `cog skill-lint` requires
  the frontmatter `name:` to equal the parent directory name.
- Man/completions may regenerate via the justfile (and, if the `man-page-sync-precommit-hook` plan
  has landed, `cog man-build`). Use the repo's mechanism; otherwise edit `man/cog.1.scd` and
  regenerate `man/cog.1`.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: rename-to-review-implementation-plans`)
`status` to `doing`.

### Step 1: Add the queue-ordering mechanics (do this before the rename)

Add the graph helpers and three commands first so the renamed skill can reference them under their
final names.

- In `lib/functions/fn_queue.sh`, add reusable helpers: build the dependency graph from a queue,
  detect dangling references (a `depends_on` entry that is not an existing `item`), and detect cycles;
  return JSON describing offenders and any permanently-blocked/unreachable items.
- `cog queue-deps-set --queue <path> --schema <plans|rounds> --item <item> --depends-on <csv|""> [--expect <csv>] <out.json>`
  - Target item must exist and be **mutable** (`todo`/`backlog`); refuse on `done`/`doing`.
  - New deps must reference existing items in the same queue (no dangling); the resulting graph must
    be acyclic (call the graph helper pre-write). Optional `--expect` is a CAS guard on current deps.
  - `yq` edit-in-place of only `.depends_on` on the target item; `jq` self-check that only that one
    field on that one item changed and every other item/field is identical.
- `cog queue-reorder --queue <path> --schema <plans|rounds> <out.json>`
  - **Deterministic — no agent-supplied order.** The model's only ordering input is the `depends_on`
    it set via `queue-deps-set`; this command **derives** the physical order by a **stable topological
    sort** of that dependency tree. Permute **mutable** items only, within the positions currently
    occupied by mutable items; non-mutable (`done`/`doing`) items keep their **exact index and
    content**; item multiset unchanged (no add/drop). **Stable tiebreak:** among items with no
    ordering constraint between them, preserve their current relative order (minimize churn → the
    command is idempotent when already canonical). Fails closed on a cycle or dangling dep (delegates
    to the graph helper / `queue-graph-check`).
  - `jq` self-check: each non-mutable item byte-identical at its original index; mutable slots
    reordered to the computed topological order; full set of items unchanged.
- `cog queue-graph-check --queue <path> --schema <plans|rounds> <out.json>`
  - Read-only validator wrapping the helpers: every `depends_on` references an existing item; no
    cycles; report unreachable/permanently-blocked items. Used as a pre-write guard by the two
    mutation commands **and** standalone by the skill and the verify gate.
- Add bats `queue_deps_set.bats`, `queue_reorder.bats`, `queue_graph_check.bats` covering happy paths
  and fail-closed cases: mutating a `done`/`doing` item, a dangling dependency, and a cycle.

### Step 2: Extend the verify gate

In `cmd_plans_revision_verify.sh` (renamed in Step 4):

- Pin `doing` items the same way `done` items are pinned (`status/prompt/depends_on/notes` immutable):
  `doing` is in-flight and must not be reordered or re-depended during a revision pass.
- Run `queue-graph-check` against the **after** scan; if it reports a cycle or dangling dep, the gate
  fails closed (`completed_history_preserved`/`ok` false).
- Report new change classes alongside `status_changes`/`new_items`: `deps_changes` (item, before/after
  `depends_on`) and `reordered` (queue path + new order), for mutable items.
- Extend `plans_revision_verify.bats` (renamed in Step 5) for `doing`-immutability, the new reports,
  and graph-check fail-closed.

### Step 3: Rename the skill (and expand its workflow)

`git mv` (or move) `.claude/skills/plans-revision/` → `.claude/skills/review-implementation-plans/`.
In its `SKILL.md`:

- Set `name: review-implementation-plans`, `model: opus`, `effort: low`; update the `trigger-tests`
  comment to the new name; update in-body references to the renamed `cog` commands
  (`cog review-implementation-plans-scan` / `-verify`). Keep it under `.claude/skills/`.
- Add the three new commands to the **Cog Contract** section.
- Add a **"Review queue execution order & dependencies"** phase that runs **after** plan
  reconciliation. The split follows ADR-0008 — **judgment in the model, determinism in the script:**
  - *Judgment (model):* for the main `plans` queue and each plan's `rounds` queue, analyze the
    reconciled plans against the current code and decide the best dependency wiring (least friction,
    correct prerequisites). Express that decision **only** by setting `depends_on` on **mutable**
    (`todo`/`backlog`) items via `cog queue-deps-set` (add a prerequisite the reconciliation surfaced;
    drop one the code made irrelevant). The model does **not** pick a physical order.
  - *Determinism (script):* then run `cog queue-reorder` to physically reorder the mutable items to
    the canonical order **derived by stable topological sort of `depends_on`**, and `cog
    queue-graph-check` to confirm the graph is acyclic with no dangling refs. The order falls out of
    the dependency tree.
- Rewrite guardrail step 6 from "Do not reorder existing entries" → "Re-depend **mutable**
  (`todo`/`backlog`) items only via `cog queue-deps-set` (model judgment); the physical order is then
  derived **deterministically** by `cog queue-reorder` (topological sort of `depends_on`). Never move
  or re-depend `done`/`doing` items; never by direct edit." Update the append-only Guardrails wording
  to permit dependency adjustment of mutable items through the new commands.
- Adopt the **two-commit cadence**, each via the `/gc` skill (never raw git): after reconciliation,
  run `/gc -a` (commit A); then run the ordering phase; then run `/gc -a` again (commit B). Both
  foreground (never backgrounded), each parsed with `cog runner-queue-parse-commit`. Update the
  `RESULT:` contract to report both phases, reporting `NO_DRIFT` for whichever phase changed nothing
  (no empty commits).

### Step 4: Rename the cog command modules + handlers + fn helpers

- Move `lib/commands/cmd_plans_revision_scan.sh` → `cmd_review_implementation_plans_scan.sh` and
  `cmd_plans_revision_verify.sh` → `cmd_review_implementation_plans_verify.sh`.
- Rename handlers `cog::cmd::plans_revision_scan/verify` →
  `cog::cmd::review_implementation_plans_scan/verify`; rename the self-check vars
  (`__cog_plans_revision_scan_self_check`, `__cog_plans_revision_verify_scan_check`,
  `__cog_plans_revision_verify_history_preserved`) to match; update usage strings to the new dashed
  command names; reword the line-2 `desc:` sentinels (e.g. "Verify a review-implementation-plans run
  against a before/after scan.").
- Move `lib/functions/fn_plans_revision.sh` → `fn_review_implementation_plans.sh`; rename
  `cog::fn::plans_revision_*` → `cog::fn::review_implementation_plans_*`; update all callers.

### Step 5: Update all consumers + the superseding ADR

- `skills/claude/runner-queue/SKILL.md`: every `plans-revision` skill reference → `review-
  implementation-plans`; the path `.claude/skills/plans-revision/SKILL.md` → `.claude/skills/
  review-implementation-plans/SKILL.md`; `cog plans-revision-scan/verify` → the new command names;
  update the revision-boundary description to reflect ordering review + up to two commits per
  boundary.
- `docs/decisions/0012-plan-queue-revision-boundary.md`: update the path/command strings only — **do
  not rewrite the decision**.
- **New superseding ADR** (assign the **next free** number at execution — coordinate with Round 2's
  never-sonnet ADR and the unrelated self-contained-skill-refs ADR; README flags 0013 contention):
  record (a) the revision boundary now performs queue ordering/dependency review, adjusting mutable
  items via `queue-deps-set`/`queue-reorder`, and (b) the two-`/gc`-commit cadence. State that it
  supersedes ADR-0012; leave ADR-0012 in place (AGENTS.md: accepted ADRs are never deleted).
- `docs/reference/cli-commands.md`: update the two renamed rows and add three rows for the new
  commands.

### Step 6: Rename + update tests

- `git mv` `test/integration/plans_revision_scan.bats` →
  `review_implementation_plans_scan.bats` and `plans_revision_verify.bats` →
  `review_implementation_plans_verify.bats`; update test descriptions, command invocations, and any
  asserted strings; fold in the Step-2 verify extensions.
- Ensure the new `queue_*` bats from Step 1 are present and green.
- `test/integration/skills_claude.bats`: update the `assert_file_contains ... "plans-revision"`
  assertion (line ~133) to the new skill name.
- `test/integration/help_snapshots.bats`: update the renamed command-summary lines (~61–62, 136–137)
  and add the three new command summaries.

### Step 7: Regenerate artifacts and verify

- Regenerate completions + man (`man/cog.1.scd` → `man/cog.1`) and the help snapshots via the repo's
  mechanism (justfile recipe / `cog man-build` if present).
- Run `cog skill-lint .claude/skills/review-implementation-plans/SKILL.md` — must pass (name matches
  dir; valid charset).
- Run the integration suite (`just test` / the integration hook) and confirm the renamed bats suites,
  the three new `queue_*` suites, and the help-snapshot tests pass.
- Final `grep -rn 'plans-revision\|plans_revision' . ':!.implementation-plans'` returns no
  unintended residue (archival `.implementation-plans/**` references are acceptable).

### Step 8: Gated retirement of the DocsNNotes model-reference sources

Only after Step 7 is fully green AND the in-cog replacements exist
(`docs/reference/models-reference-claude.md`, `docs/reference/models-reference-codex.md`,
`docs/reference/model-effort-policy.md`, and the two `docs/reference/model-effort-*.toml` files),
delete the now-superseded source files from `$DOCS_NOTES_REPO`:

```text
$DOCS_NOTES_REPO/tech/tools/claude-code/models-reference.md
$DOCS_NOTES_REPO/tech/tools/claude-code/codex-models-pricing.md
$DOCS_NOTES_REPO/tech/tools/claude-code/codex-models-comparison.md
```

Also fix any DocsNNotes cross-links that pointed at these files (e.g. `codex-conventions.md`). Do NOT
run any git command in DocsNNotes — leave the repo uncommitted for the human to review and commit
(AGENTS.md). If the in-cog replacements are missing or verification is not green, **skip this step**
and report it, rather than deleting.

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's
   (`item: rename-to-review-implementation-plans`) `status` to `done`.
2. All rounds are now done, so in the top-level `.implementation-plans/queue-plans.yaml` set this
   plan's (`item: model-effort-policy-and-rename`) `status` to `done`. Leave the plan directory in
   place.

## Acceptance Criteria

- [ ] `.claude/skills/review-implementation-plans/SKILL.md` exists with `name:
      review-implementation-plans`, `model: opus`, `effort: low`; the old skill directory is gone.
- [ ] `cog review-implementation-plans-scan` and `cog review-implementation-plans-verify` resolve and
      run; the old command names no longer exist; line-2 `desc:` sentinels are present and reworded.
- [ ] `cog queue-deps-set`, `cog queue-reorder`, and `cog queue-graph-check` resolve and run; their
      bats cover happy paths and fail-closed on `done`/`doing` mutation, dangling dep, and cycle.
      `queue-reorder` takes **no** explicit order: it produces a stable topological order from
      `depends_on`, is **idempotent** when the queue is already canonical, and leaves `done`/`doing`
      pinned (covered by bats).
- [ ] `review-implementation-plans-verify` pins `doing` items, reports `deps_changes`/`reordered`,
      and fails closed when a revision introduces a cycle or dangling dep (extended bats green).
- [ ] The renamed skill's workflow contains the ordering-review phase, the rewritten guardrail, the
      two-`/gc`-commit cadence, and the three new commands in its Cog Contract.
- [ ] A new superseding ADR (next free number) records the two-commit cadence + order-adjusting of
      mutable items and supersedes ADR-0012; ADR-0012 is untouched except its rename strings;
      `runner-queue/SKILL.md` reflects ordering review + up to two commits per boundary.
- [ ] `runner-queue/SKILL.md`, ADR-0012, and `cli-commands.md` reference the new skill/command names;
      `cli-commands.md` has rows for the three new commands; the skill invocation path is updated.
- [ ] Renamed bats suites pass; the three new `queue_*` suites pass; `skills_claude.bats` and
      `help_snapshots.bats` are updated and green.
- [ ] `cog skill-lint` passes for the renamed skill; completions/man/help-snapshots regenerated.
- [ ] No unintended `plans-revision`/`plans_revision` residue outside `.implementation-plans/**`.
- [ ] The three DocsNNotes model-reference source files are deleted (only if the in-cog replacements
      exist and verification is green); DocsNNotes is left uncommitted for the human. If skipped, the
      reason is reported.
- [ ] This plan's `queue-rounds.yaml` shows round `rename-to-review-implementation-plans` as `done`.
- [ ] The top-level `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

This is the final round.
