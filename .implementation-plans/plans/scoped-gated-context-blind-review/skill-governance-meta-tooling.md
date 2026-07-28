# Skill-Governance Meta-Tooling

> Plan: scoped-gated-context-blind-review | Round: 3 of 3 | Complexity: L | Generated: 2026-06-20 | Repo: /workspaces/cog

## Context

This repo governs its skills with a set of non-negotiable rules: the skill/script boundary (determinism in `cog`, judgment in prose — ADR-0008), reference self-containment (ADR-0017), the prefix taxonomy (ADR-0016), the model/effort policy (ADR-0013, never Sonnet), the plan-mode gate (ADR-0015), and — added in Round 2 — the **caller-owns-context** golden rule (skills are context-blind; callers drive flags). Two tooling gaps remain. First, `cog-skill-creator` only loads a _subset_ of these rules and leans on an external `$DOCS_NOTES_REPO`, so a drafted skill can silently miss a rule; it must read and follow **every** repo rule and be self-contained per ADR-0017. Second, there is no skill that _reviews_ an existing repo skill against these rules. We add `cog-skill-reviewer`: given one skill or a set, it reviews each against the repo's rules — using `cog` scripts wherever a deterministic check exists — and can fully refactor, restructure, rename, update, and fix them to comply.

## Previous Rounds

Round 1 delivered the deterministic `cog` foundation (renamed `review-plan-implementation-plans-*` commands + the `-gate`). Round 2 delivered the context-blind scoped/gated review skill, the `runner-queue` integration, the ADR superseding ADR-0014, and the **caller-owns-context golden rule** now present in `AGENTS.md`, `CLAUDE.md`, and `docs/reference/skill-contract.md`. Expect the full repo rule set to be finalized and discoverable from those governance files and the `docs/decisions/` ADRs.

## Scope of This Round

IN scope:

- Rewrite `cog-skill-creator` so it reads and applies **every** repo rule (the full ADR set + the new golden rule) and is self-contained per ADR-0017 (no load-bearing external `$DOCS_NOTES_REPO` dependency).
- Create the new `cog-skill-reviewer` skill at `.claude/skills/cog-skill-reviewer/SKILL.md`: reviews one or many repo skills against the rules, delegates deterministic checks to `cog` (reuse `cog skill-lint`; add a new `cog` routine only if a needed deterministic check is missing, per the skill/script boundary), and can fully refactor/restructure/rename/fix the reviewed skills.
- Tests + reference surface for any new `cog` command introduced.

OUT of scope: the review-boundary skill, the deterministic command layer, and `runner-queue` (Rounds 1-2). Do not relocate `cog-skill-creator`/`cog-skill-reviewer` to the shipped tree — they are cog's own development tooling and stay project-local.

## Current State

### Key Files

- `/workspaces/cog/.claude/skills/cog-skill-creator/SKILL.md` — current authoring skill. Reference resolution reads `$DOCS_NOTES_REPO` and warns/continues if unset (lines ~27-45); it treats `docs/reference/skill-contract.md` as authoritative and names three decisions (0016 taxonomy, 0013 model/effort, 0015 plan-mode gate) at lines ~37-45. Cog Contract uses `cog cog-skill-creator-validate` and `cog cog-skill-creator-scaffold` (lines ~75-114) plus `cog skill-lint`. 17-step workflow (lines ~116-181). Does **not** currently load ADR-0008 (skill/script boundary), ADR-0017 (reference self-containment), or the caller-owns-context rule.
- `/workspaces/cog/lib/commands/cmd_skill_lint.sh` — the lint command. Structural checks (frontmatter, name, parent-dir match, line count, emojis, untagged fences, trigger-tests), plan-mode-gate check (~lines 100-113), prefix-taxonomy check (~lines 115-150), shell-premise lint, orchestration-history lint. This is the deterministic review backbone `cog-skill-reviewer` reuses.
- `/workspaces/cog/lib/functions/fn_skill.sh` — `name_is_valid` (~22), `is_plan_emitter` (~79), `has_plan_mode_gate` (~84), `classify_prefix` (~89), `superseded_by` (~101), `is_plan_reviewer_intent` (~107), `is_executor_intent` (~113), `runtime_for_path`, `frontmatter_name`.
- `/workspaces/cog/docs/reference/skill-contract.md` — authoritative local contract (incl. the Round 2 golden rule). `/workspaces/cog/docs/decisions/` — ADR-0008, 0013, 0015, 0016, 0017, and Round 2's new superseding ADR.
- `/workspaces/cog/AGENTS.md`, `/workspaces/cog/CLAUDE.md` — non-negotiables, incl. the golden rule.
- `/workspaces/cog/lib/commands/cmd_cog_skill_creator_validate.sh`, `/workspaces/cog/lib/commands/cmd_cog_skill_creator_scaffold.sh` — existing deterministic backing for the creator. Tests live under `test/`.
- `/workspaces/cog/completions/cog.bash`, `/workspaces/cog/man/cog.1.scd`, `/workspaces/cog/docs/reference/cli-commands.md` — reference surface for any new `cog` command.

### Existing Patterns

- Skill/script boundary (ADR-0008): deterministic routines belong in `cog`; skills keep sequencing and judgment. Reuse an existing `cog` subcommand/helper before adding one.
- Reference self-containment (ADR-0017): required runtime references ship in-repo under `skill-refs/` and resolve via `cog skill-refs`; external docs are optional enhancers that must degrade gracefully.
- Authoring/utility skills take a **descriptive non-taxonomy name** (e.g. `cog-skill-creator`); they are not governed-intent, so the prefix-taxonomy check imposes no prefix. `cog-skill-reviewer` follows this pattern. Confirm `skill-lint`'s intent detection does not misfire (no `plan-emitter` marker; no executor phrases).
- Command modules: `cmd_<slug>.sh` + `cog::cmd::<slug>` + line-2 `desc:` sentinel; `(<out.json>|--json)`
  - `--help`.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: skill-governance-meta-tooling`) `status` to `doing`.

### Step 1: Make `cog-skill-creator` follow every repo rule + be self-contained

In `.claude/skills/cog-skill-creator/SKILL.md`:

- Replace the partial decision list with the **full** governing set, read at skill start from in-repo sources: ADR-0008 (skill/script boundary), ADR-0013 + `docs/reference/model-effort-policy.md` (model/effort, never Sonnet), ADR-0015 (plan-mode gate), ADR-0016 (prefix taxonomy), ADR-0017 (reference self-containment), the Round 2 superseding review-boundary ADR, and the **caller-owns-context** golden rule. Treat `docs/reference/skill-contract.md` as the authoritative index and follow each rule while drafting.
- Make reference resolution self-contained per ADR-0017: resolve required references via `cog skill-refs` / in-repo `docs/`, and treat `$DOCS_NOTES_REPO` as an **optional enhancer** that degrades gracefully — never a load-bearing dependency.
- Add to the interview/checklist an explicit "caller-owns-context" decision: when a drafted skill could be context-aware, prefer a context-blind, flag-driven design and document why if not.
- Keep the deterministic gates (`cog cog-skill-creator-validate`, `cog skill-lint`) and the approval gate; do not embed deterministic shell that a `cog` command should own.

### Step 2: Create the `cog-skill-reviewer` skill

Create `.claude/skills/cog-skill-reviewer/SKILL.md` (project-local, descriptive non-taxonomy name):

- Frontmatter: `name: cog-skill-reviewer`, `description` with triggers (e.g. "cog-skill-reviewer", "review a skill", "audit skills", "make a skill follow the rules"), `model: opus` + `effort: low` (thin orchestration over deterministic mechanics; never Sonnet), `allowed-tools` incl. `Bash Read
  Edit Write`, and a `trigger-tests` comment. No `plan-emitter` marker (it edits skills, not plans), so no plan-mode gate is lint-required — but confirm via `cog skill-lint`.
- Inputs: one or more target skill paths (or a glob / "all skills"); a mode flag distinguishing a read-only **report** from an **auto-fix** run (mirroring the caller-owns-context principle — the caller decides).
- Workflow:
  1. Resolve the target skill file(s).
  2. For each, run the deterministic backbone `cog skill-lint <file>` and read `docs/reference/skill-contract.md` + the relevant ADRs.
  3. Judge each skill against every rule: prefix taxonomy match, model/effort policy, plan-mode gate (when it emits/mutates plans), skill/script boundary (deterministic shell that should be a `cog` command), reference self-containment, and caller-owns-context.
  4. Produce a machine-first findings report per skill.
  5. In auto-fix mode, fully refactor/restructure/rename/update/fix the skill to comply — moving deterministic shell into `cog` (or proposing the new command), correcting frontmatter/markers, fixing the name prefix, and re-running `cog skill-lint` until clean. Gate destructive changes (rename/restructure) behind explicit approval.
- Keep all deterministic checks in `cog` (reuse `cog skill-lint`); add a new `cog` routine **only** if a needed deterministic check has no existing command — and if so, implement it as `cmd_<slug>.sh`
  - helper, with tests and reference-surface entries (Step 3).

### Step 3: Backing command (only if needed) + tests + reference surface

- If Step 2 requires a new deterministic check with no existing `cog` home, add it as a `cog` command (module + handler + line-2 `desc:` + `--json`/`--help`) with a bats suite, and register it in `completions/cog.bash`, `man/cog.1.scd`, and `docs/reference/cli-commands.md`. If `cog skill-lint` already covers the checks, add no new command.
- Run `cog skill-lint .claude/skills/cog-skill-creator/SKILL.md` and `cog skill-lint .claude/skills/cog-skill-reviewer/SKILL.md`; both must pass.
- Add any project-skill test-list entry needed for `cog-skill-reviewer`.

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: skill-governance-meta-tooling`) `status` to `done`.
2. All rounds are now done, so in the top-level `.implementation-plans/queue-plans.yaml` set this plan's (`item: scoped-gated-context-blind-review`) `status` to `done`. Leave the plan directory in place.

## Acceptance Criteria

- [ ] `cog-skill-creator` reads and applies the full repo rule set (ADR-0008/0013/0015/0016/0017 + the Round 2 review-boundary ADR + the caller-owns-context golden rule) and treats `$DOCS_NOTES_REPO` as an optional enhancer only; it passes `cog skill-lint`.
- [ ] `.claude/skills/cog-skill-reviewer/SKILL.md` exists, reviews one or many skills against the rules via `cog skill-lint` + the contract, reports findings, and can auto-fix/refactor to compliance; it passes `cog skill-lint`.
- [ ] Any new `cog` command added for the reviewer has a `desc:` sentinel, `--json`/`--help`, a bats suite, and completion/man/cli-commands entries; if none is needed, none is added.
- [ ] `just lint` and `just test` pass.
- [ ] This plan's `queue-rounds.yaml` shows round `skill-governance-meta-tooling` as `done`, and the top-level `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

This is the final round.
