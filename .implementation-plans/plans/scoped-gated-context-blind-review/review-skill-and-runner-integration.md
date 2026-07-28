# Review Skill, Runner Integration, and Governance

> Plan: scoped-gated-context-blind-review | Round: 2 of 3 | Complexity: L | Generated: 2026-06-20 | Repo: /workspaces/cog

## Context

The implementation-plan review boundary must become a **context-blind, self-contained** skill that behaves like a CLI program: it defaults to cheap deterministic checks, gates the expensive LLM pass behind `--full-review`, accepts a `--scope`, returns a machine-first report, and **auto-applies guarded** reconciliation. The **caller owns context** and drives the flags — this becomes a repo golden rule. Between rounds, `runner-queue` must run only a scoped review (one plan's rounds queue); between plans, a global cross-plan review. Today the skill is project-local (`.claude/skills/review-implementation-plans/`), loaded via a cwd hack, always runs a global Opus pass, and only reconciles the just-landed plan — it never asks whether _other_ plans are now redundant/conflicting/stale. Round 1 already renamed the backing commands to `review-plan-implementation-plans-*` and added the deterministic `-gate`. This round builds the skill and integration on that foundation and establishes the governing rules.

## Previous Rounds

Round 1 produced the deterministic `cog` foundation: the `review-plan-implementation-plans-scan` / `-verify` commands (with `--scope global|rounds` + scoped inventory/fingerprint helpers), the new pure-deterministic `review-plan-implementation-plans-gate` command emitting `{drift, reasons[],
graph_valid}`, a repo-wide token migration, and renamed/extended/added bats suites. Expect the gate to be callable for both scopes and the global scan path to be byte-identical to its pre-rename behavior.

## Scope of This Round

IN scope:

- Relocate `.claude/skills/review-implementation-plans/` → `skills/claude/review-plan-implementation-plans/` and rewrite the skill as context-blind, scoped, gated, auto-applying.
- Rewire `runner-queue` to drive it per context: scoped gate + scoped full-review between rounds; global full-review between plans; drop the project-local cwd hack.
- Land the new ADR superseding ADR-0014; add the caller-owns-context golden rule to `AGENTS.md`, `CLAUDE.md`, and `docs/reference/skill-contract.md`; update `docs/reference/skills.md`.
- Add the shipped skill to the skills test list.

OUT of scope (Round 3): `cog-skill-creator` and the new `cog-skill-reviewer`. The further changes to the deterministic command layer are done (Round 1).

## Current State

### Key Files

- `/workspaces/cog/.claude/skills/review-implementation-plans/SKILL.md` — current skill. Frontmatter `name: review-implementation-plans`, `model: opus`, `effort: low`, `argument-hint: "--repo-root <dir> --main-queue <path>"`, `allowed-tools: Bash Read Edit Write
  Skill`, `disable-model-invocation: true`. Markers: `<!-- cog-skill: plan-emitter -->`, `<!-- cog-skill: superseded-by review-plan-implementation -->`, `<!-- cog-plan-mode-gate -->`. Two phases: Phase 1 reconciliation (mark-done mutable items, revise own prose, append gaps; `/gc -a` commit), Phase 2 queue order/deps (`queue-deps-set` + `queue-reorder` + `queue-graph-check`; `/gc
  -a` commit). Output: `STATUS: OK|FAILED`, `RESULT` lines, `NO_DRIFT` per phase.
- `/workspaces/cog/skills/claude/runner-queue/SKILL.md` — the "Review-Implementation-Plans Boundary" section (~lines 396-458) invokes the skill after every committed item; call sites at ~lines 291-293 (inner round) and ~363-369 (main plan). Lines ~402-407 treat it as a **project** skill and set cwd to `REPO_ROOT` so the delegate loads `.claude/skills/review-implementation-plans/SKILL.md`; the verify postcondition is at ~lines 449-458. Per-run `$RUN_DIR` + `ctx.env`/`inner.env` conventions exist (e.g. lines ~178-186, 264, 273, 309, 342).
- `/workspaces/cog/install.sh` — copies `skills/claude` → `$HOME/.claude/skills` (lines ~119-121); copies `skill-refs` → `$XDG_DATA_HOME/cog/skill-refs` (line ~111). No install change needed.
- `/workspaces/cog/docs/decisions/0014-review-implementation-plans-boundary.md` — Accepted; supersedes ADR-0012; defines the two-phase boundary. `/workspaces/cog/docs/decisions/0012-plan-queue-revision-boundary.md` — Accepted. Both stay (accepted ADRs are never deleted).
- `/workspaces/cog/docs/reference/skill-contract.md`, `/workspaces/cog/AGENTS.md`, `/workspaces/cog/CLAUDE.md` — governance surfaces. `/workspaces/cog/docs/reference/skills.md` — skill inventory listing the project-local entry under `review-plan-*`.
- `/workspaces/cog/test/integration/skills_claude.bats` — shipped-skill list.

### Existing Patterns

- Shipped skills live at `skills/claude/<name>/SKILL.md` with frontmatter + `trigger-tests` comment; they install to `$HOME/.claude/skills/` and are invoked as stowed skills (no cwd hack).
- skill-lint prefix taxonomy: `is_plan_reviewer_intent` = `is_plan_emitter` AND a phrase match (incl. "review implementation plans"); it expects a `review-plan` prefix. The new name `review-plan-implementation-plans` satisfies it with the `plan-emitter` marker kept and **no lint change**.
- Skill prose keeps judgment; deterministic mechanics call `cog`. Skills that emit/mutate plan files carry the Phase 0 plan-mode gate.
- ADRs use a superseding-record pattern; markdown fenced blocks must declare a language.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: review-skill-and-runner-integration`) `status` to `doing`.

### Step 1: Relocate + rewrite the skill (context-blind, self-contained)

Create `skills/claude/review-plan-implementation-plans/SKILL.md` and remove the old `.claude/skills/review-implementation-plans/` directory.

- Frontmatter: `name: review-plan-implementation-plans`, `model: opus`, `effort: low`, `disable-model-invocation: true`, and an `argument-hint` covering the new flags. Keep `<!-- cog-skill: plan-emitter -->` and the Phase 0 plan-mode gate (`<!-- cog-plan-mode-gate -->`); **remove** `<!-- cog-skill: superseded-by review-plan-implementation -->`. Update the `trigger-tests` comment to the new name.
- Flags (caller-driven): `--scope global|rounds`, `--queue <path>` (rounds), `--repo-root`, `--main-queue` (global), `--full-review`. `$RUN_DIR` for artifacts.
- Phase 0: plan-mode gate (unchanged intent).
- Phase 1 (always, deterministic, cheap): run the scoped scan + `review-plan-implementation-plans-gate` verdict; emit a machine-first **report** (`drift`, `reasons`, `graph_valid`, changed items). If `--full-review` is absent → return the report and STOP (the cheap path; usable standalone by a human or agent).
- Phase 2 (only with `--full-review`): scoped semantic analysis, then **auto-apply guarded** via `cog queue-*` + mutable prose edits, then verify + foreground `/gc -a` (still up to two commits: reconciliation, then order/deps), parse with `cog runner-queue-parse-commit`, return `STATUS: OK`
  - `RESULT` lines (`NO_DRIFT` per phase when clean). Fail-closed → `STATUS: FAILED`.
  * rounds scope: analyze only that plan's remaining rounds vs. landed code (do the remaining rounds still make sense? any now-implemented/redundant?); mutate only within that one rounds queue.
  * global scope: cross-plan analysis over the main queue + all inner queues, asking for each _other_ mutable plan: (1) now redundant/partially-implemented → mark `done` or trim; (2) still makes sense / needs adaptation → revise mutable prose; (3) conflict/regression vs. the implementation → revise or re-sequence; (4) new gaps → `queue-append`; (5) dependency/order changes → `queue-deps-set` + `queue-reorder` + `queue-graph-check`.
- Immutability preserved: never touch `done`/`doing` status, prompt, deps, notes, prose, or order.
- Keep the Cog Contract section pointing at the renamed commands and the new gate.

### Step 2: Rewire `runner-queue`

In `skills/claude/runner-queue/SKILL.md`:

- Between rounds (inner queue): before the round, capture a `rounds`-scope baseline scan to `$RUN_DIR/gate-baseline-<n>.json`; after the round's `/gc`, run `cog review-plan-implementation-plans-gate --scope rounds --queue "$INNER_QUEUE_PATH" --baseline ...`. If `.drift == false` → **skip** dispatching the skill. If drift → dispatch the skill with `--full-review --scope rounds --queue "$INNER_QUEUE_PATH"`.
- Between plans (main queue): always dispatch the skill with `--full-review --scope global --main-queue "$REVISION_MAIN_QUEUE"`.
- Relocation cleanup: replace the "project-local … cwd = REPO_ROOT … loads `.claude/skills/...`" language (~lines 402-407, plus the "project-local" mentions at ~402/434) with normal shipped-skill (stowed `$HOME/.claude/skills/`) treatment; drop the cwd hack. Keep the verify postcondition, updating any command tokens to the renamed forms.

### Step 3: Land the ADR + the golden rule

- Add a new ADR (next number) **superseding ADR-0014**: the scoped + gated + context-blind review boundary, the deterministic gate, and the **caller-owns-context** rule. Mark ADR-0014 superseded by reference; do not delete 0012/0014.
- Add the golden rule "skills are context-blind; callers own context and drive flags" to `AGENTS.md`, `CLAUDE.md` (as a non-negotiable, consistent with the existing ones), and `docs/reference/skill-contract.md`.
- Update `docs/reference/skills.md`: move the entry to the shipped `review-plan-*` listing under the new name; remove the `review-plan-implementation` look-alike mention.

### Step 4: Tests

- Add `review-plan-implementation-plans` to `test/integration/skills_claude.bats`.
- Run `cog skill-lint skills/claude/review-plan-implementation-plans/SKILL.md` and confirm it passes with the kept `plan-emitter` marker and no superseded marker (no lint change needed).

### Final Step: Update the queue

In this plan's `queue-rounds.yaml`, set this round's (`item: review-skill-and-runner-integration`) `status` to `done`.

## Acceptance Criteria

- [ ] `skills/claude/review-plan-implementation-plans/SKILL.md` exists, is context-blind/scoped/gated, auto-applies guarded edits, and passes `cog skill-lint`; the old `.claude/skills/review-implementation-plans/` directory is gone.
- [ ] Without `--full-review` the skill returns a report and makes no edits; with `--full-review` it analyzes within the given scope and commits drift (or `NO_DRIFT`).
- [ ] `runner-queue` runs the scoped gate between rounds (skipping dispatch on no-op), runs the scoped full-review on drift, and the global full-review between plans; the cwd hack is gone.
- [ ] A new ADR supersedes ADR-0014; the caller-owns-context golden rule is present in `AGENTS.md`, `CLAUDE.md`, and `docs/reference/skill-contract.md`; `docs/reference/skills.md` is updated.
- [ ] `just lint` and `just test` pass.
- [ ] This plan's `queue-rounds.yaml` shows round `review-skill-and-runner-integration` as `done`.

## Next Round

Round 3 makes `cog-skill-creator` read and follow **every** repo rule (including this round's golden rule and reference self-containment) and creates the new `cog-skill-reviewer` skill that reviews any repo skill against those finalized rules and can fully refactor it.
