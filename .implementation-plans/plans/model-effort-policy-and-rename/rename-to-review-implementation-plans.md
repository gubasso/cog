# Rename plans-revision → review-implementation-plans (Skill + cog Commands), Apply opus/low

> Plan: model-effort-policy-and-rename | Round: 3 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog

## Context

The project-local skill `plans-revision` reconciles implementation-plan queues with repo state after
a committed plan-queue-runner item. It is the **only** skill using `model: sonnet` (+ `effort:
high`) — the outlier the new model/effort policy retires. This round performs the atomic rename of
that skill **and its sibling `cog` commands** to `review-implementation-plans`, and re-grades the
skill to `model: opus` + `effort: low` (the canonical "never sonnet → opus+low" worked example).

The rename is treated as **one atomic change** (skill + commands + every reference) so the repo never
sits in a half-renamed state. The blast radius is wide but mechanical; it is driven by grepping for
every occurrence rather than trusting a fixed list.

## Previous Rounds

- `research-current-model-data` produced dated evidence references in `docs/reference/`.
- `model-effort-policy-sot` authored `docs/reference/model-effort-policy.md`, the two descriptive
  TOML data files in `docs/reference/`, the policy ADR (the "never sonnet → opus+low" rule), and
  AGENTS.md/CLAUDE.md wiring.
  This round's re-grade of the skill to opus/low is the policy's first application; cite the policy
  ADR in the skill's frontmatter rationale or commit message.

## Scope of This Round

- IN scope:
  - Rename the skill directory `.claude/skills/plans-revision/` → `.claude/skills/
    review-implementation-plans/`; set frontmatter `name: review-implementation-plans`, `model:
    opus`, `effort: low`; update its trigger-tests and any in-body command references.
  - Rename the `cog` commands `plans-revision-scan` / `plans-revision-verify` →
    `review-implementation-plans-scan` / `review-implementation-plans-verify`: command modules,
    handler/self-check identifiers, line-2 `desc:` sentinels, usage/help strings, and (for
    consistency) the internal `fn_plans_revision.sh` helpers.
  - Update every reference: `plan-queue-runner/SKILL.md`, ADR-0012, `docs/reference/cli-commands.md`,
    completions, man page, integration tests, and help snapshots.
  - Regenerate completions + man + help snapshots; run `cog skill-lint` and the integration suite.
  - **Gated final cleanup:** after everything above verifies, delete the now-superseded model-
    reference files from `$DOCS_NOTES_REPO` (the in-cog replacements were authored in Rounds 1–2).
- OUT of scope:
  - Changing the skill's behavior/workflow (only its name, model/effort, and the command names it
    calls).
  - Re-grading any *other* skill's frontmatter (deferred beyond this plan).
  - Deleting any DocsNNotes file other than the three model-reference files listed below.

## Current State

### Key Files (rename surface — confirm with grep, do not trust line numbers)

- `/workspaces/cog/.claude/skills/plans-revision/SKILL.md` — line 2 `name: plans-revision`; line 7
  `model: sonnet`; line 8 `effort: high`; `<!-- trigger-tests: "plans-revision", ... -->`; body
  references `cog plans-revision-scan` / `cog plans-revision-verify`. It is **project-local** (under
  `.claude/skills/`, not `skills/claude/`), so `install.sh` does not ship it — keep it under
  `.claude/skills/` after the rename.
- `/workspaces/cog/lib/commands/cmd_plans_revision_scan.sh` — line 2
  `: 'desc: Inventory all implementation-plan queues and repo/plan fingerprints.'`; handler
  `cog::cmd::plans_revision_scan()` (line ~59); self-check var `__cog_plans_revision_scan_self_check`;
  usage string `cog plans-revision-scan ...`.
- `/workspaces/cog/lib/commands/cmd_plans_revision_verify.sh` — line 2
  `: 'desc: Verify a plans-revision against a before/after scan.'`; handler
  `cog::cmd::plans_revision_verify()` (line ~148); self-check var
  `__cog_plans_revision_verify_scan_check`.
- `/workspaces/cog/lib/functions/fn_plans_revision.sh` — helpers `cog::fn::plans_revision_*`
  (`_queue_schema`, `_inventory_json`, `_repo_fingerprint`, `_plans_fingerprint`, …). Internal; rename
  for naming consistency (file → `fn_review_implementation_plans.sh`, functions →
  `cog::fn::review_implementation_plans_*`) and update all callers in the two command modules.
- `/workspaces/cog/skills/claude/plan-queue-runner/SKILL.md` — ~13 references to the skill name and
  the path `.claude/skills/plans-revision/SKILL.md`, plus references to `cog plans-revision-scan` /
  `-verify` (around lines 10, 56, 346–394).
- `/workspaces/cog/docs/decisions/0012-plan-queue-revision-boundary.md` — prose references to
  `.claude/skills/plans-revision` and `cog plans-revision-verify` (around lines 26–33). **Do not
  rewrite the decision**; update only the path/command-name strings so they resolve.
- `/workspaces/cog/docs/reference/cli-commands.md` — the two command rows (around lines 59–60).
- `/workspaces/cog/completions/cog.bash`, `/workspaces/cog/man/cog.1`, `/workspaces/cog/man/cog.1.scd`
  — command-name occurrences (regenerated artifacts; prefer regenerating over hand-editing).
- `/workspaces/cog/test/integration/plans_revision_scan.bats`,
  `/workspaces/cog/test/integration/plans_revision_verify.bats` — rename the files and update the
  test names/bodies and the command invocations.
- `/workspaces/cog/test/integration/skills_claude.bats` (line ~133 `assert_file_contains "$file"
  "plans-revision"`) and `/workspaces/cog/test/integration/help_snapshots.bats` (lines ~61–62,
  136–137) — update to the new names.

### Existing Patterns

- The loader maps a dashed command to `cmd_<slug_with_underscores>.sh` + `cog::cmd::<slug>`. So
  `review-implementation-plans-scan` → `cmd_review_implementation_plans_scan.sh` +
  `cog::cmd::review_implementation_plans_scan`.
- Every command module keeps its line-2 `: 'desc: ...'` sentinel (root help, man, completion drift
  checks depend on it).
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

### Step 1: Enumerate the full rename surface

Run, from the repo root, to get the authoritative occurrence list (line numbers in this file may have
shifted):

```bash
grep -rn 'plans-revision\|plans_revision' \
  --include='*.sh' --include='*.md' --include='*.bats' --include='*.bash' \
  --include='*.scd' --include='*.1' \
  . ':!.implementation-plans'
```

Exclude `.implementation-plans/**` (archival plan docs — historical, left as-is except where this
plan instructs). Classify each hit: skill name, skill path, command name, handler/fn identifier,
self-check var, desc sentinel, test, doc, completion/man.

### Step 2: Rename the skill

`git mv` (or move) `.claude/skills/plans-revision/` → `.claude/skills/review-implementation-plans/`.
In its `SKILL.md`: set `name: review-implementation-plans`, `model: opus`, `effort: low`; update the
`trigger-tests` comment to the new name; and update in-body references to the renamed `cog` commands
(`cog review-implementation-plans-scan` / `-verify`). Keep it under `.claude/skills/`.

### Step 3: Rename the cog command modules + handlers + fn helpers

- Move `lib/commands/cmd_plans_revision_scan.sh` → `cmd_review_implementation_plans_scan.sh` and
  `cmd_plans_revision_verify.sh` → `cmd_review_implementation_plans_verify.sh`.
- Rename handlers `cog::cmd::plans_revision_scan/verify` →
  `cog::cmd::review_implementation_plans_scan/verify`; rename the self-check vars
  (`__cog_plans_revision_scan_self_check`, `__cog_plans_revision_verify_scan_check`) to match; update
  usage strings to the new dashed command names; reword the line-2 `desc:` sentinels (e.g. "Verify a
  review-implementation-plans run against a before/after scan.").
- Move `lib/functions/fn_plans_revision.sh` → `fn_review_implementation_plans.sh`; rename
  `cog::fn::plans_revision_*` → `cog::fn::review_implementation_plans_*`; update all callers.

### Step 4: Update all consumers

- `skills/claude/plan-queue-runner/SKILL.md`: every `plans-revision` skill reference → `review-
  implementation-plans`; the path `.claude/skills/plans-revision/SKILL.md` → `.claude/skills/
  review-implementation-plans/SKILL.md`; `cog plans-revision-scan/verify` → the new command names.
- `docs/decisions/0012-plan-queue-revision-boundary.md`: update the path/command strings only.
- `docs/reference/cli-commands.md`: update the two command rows.

### Step 5: Rename + update tests

- `git mv` `test/integration/plans_revision_scan.bats` →
  `review_implementation_plans_scan.bats` and `plans_revision_verify.bats` →
  `review_implementation_plans_verify.bats`; update test descriptions, command invocations, and any
  asserted strings.
- `test/integration/skills_claude.bats`: update the `assert_file_contains ... "plans-revision"`
  assertion (line ~133) to the new skill name.
- `test/integration/help_snapshots.bats`: update the four command-summary lines (~61–62, 136–137).

### Step 6: Regenerate artifacts and verify

- Regenerate completions + man (`man/cog.1.scd` → `man/cog.1`) and the help snapshots via the repo's
  mechanism (justfile recipe / `cog man-build` if present).
- Run `cog skill-lint .claude/skills/review-implementation-plans/SKILL.md` — must pass (name matches
  dir; valid charset).
- Run the integration suite (`just test` / the integration hook) and confirm the renamed bats suites
  and help-snapshot tests pass.
- Final `grep -rn 'plans-revision\|plans_revision' . ':!.implementation-plans'` returns no
  unintended residue (archival `.implementation-plans/**` references are acceptable).

### Step 7: Gated retirement of the DocsNNotes model-reference sources

Only after Step 6 is fully green AND the in-cog replacements exist
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
- [ ] `plan-queue-runner/SKILL.md`, ADR-0012, and `cli-commands.md` reference the new skill/command
      names; the skill invocation path is updated.
- [ ] Renamed bats suites pass; `skills_claude.bats` and `help_snapshots.bats` are updated and green.
- [ ] `cog skill-lint` passes for the renamed skill; completions/man/help-snapshots regenerated.
- [ ] No unintended `plans-revision`/`plans_revision` residue outside `.implementation-plans/**`.
- [ ] The three DocsNNotes model-reference source files are deleted (only if the in-cog replacements
      exist and verification is green); DocsNNotes is left uncommitted for the human. If skipped, the
      reason is reported.
- [ ] This plan's `queue-rounds.yaml` shows round `rename-to-review-implementation-plans` as `done`.
- [ ] The top-level `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

This is the final round.
