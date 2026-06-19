# Encode the rules as lint, then audit and sweep every skill and script

> Plan: skills-under-skills-env-first | Round: 3 of 3 | Complexity: L | Generated: 2026-06-18 |
> Repo: /workspaces/cog

## Context

`cog` must be self-enforcing for future AI-authored skills and scripts: `cog skill-lint` should
mechanically catch stale hook guarantees and wrong orchestration primitives, every existing
skill/script must be audited against the corrected contract, and no leftovers from the old
`codex-foreground` attempt may remain anywhere. Round 1 made the env-first guarantee real and removed
the hook's core surface; Round 2 documented the contract (ADR-0009, reference, explanation, guards,
skill-builder). This round encodes the rules as lint and runs the full per-skill + per-script
audit/sweep — the load-bearing step for the "no leftovers" requirement, given its own `/prex` session
so its completeness is independently verifiable.

The corrected contract to enforce (from Round 2 docs): env-first no-backgrounding guarantee (never a
`PreToolUse` hook); foreground discipline; Skill-inline (0 depth) vs Agent-delegate (1 level, cap 5);
verify-at-each-boundary; deterministic mechanics in cog (ADR-0008).

## Previous Rounds

Round 1 (`revert-and-assert-core`) removed the `codex-foreground` hook end-to-end, added the
fail-closed `cog` env preflight, fixed `prex-stop` (stage3), injected the `base.json` env, and updated
the CORE orchestration prose (prex, plan-queue-runner, claude-delegate). Round 2
(`document-orchestration-contract`) recorded the contract in ADR-0009 + reference + explanation +
AGENTS/CLAUDE guards, reconciled `skill-contract.md` / `codex-single-entrypoint.md`, and taught
`skill-builder`. The rules now exist in prose and the contract; this round makes them mechanical and
sweeps the whole tree.

## Scope of This Round

IN scope:

- New mechanical `cog skill-lint` checks encoding the new rules (in `cmd_skill_lint.sh` +
  `fn_skill.sh`), kept in sync with `skill-contract.md` and `test/integration/cmd_skill_lint.bats`
  (add fixtures for the new failures and allowed cases). The rules are gated by the existing
  pre-commit local hook.
- A FULL per-skill audit (`skills/claude/*`, `skills/codex/*`, `.claude/skills/*`) and per-script
  audit (`lib/commands/cmd_*.sh`, `lib/functions/fn_*.sh`) against the corrected contract — inventory
  the actual checkout at execution time (counts below are approximate).
- Fix every violation, including any remaining foreground/600000/reap or hook prose in `review-loop`,
  `ask`, `plan-writer-multi`, and the codex-side skills that Rounds 1–2 did not touch. Keep
  foreground/600000 discipline wording where it is still correct (Codex calls SHOULD still be
  foreground with a long timeout); remove only the claims that a hook is the guarantee.
- Verify NO LEFTOVERS across `/workspaces/cog` and `/home/gbasso/.dotfiles`.

OUT of scope: anything Rounds 1–2 own (hook removal, env preflight, prex-stop fix, base.json
injection, the docs themselves).

## Current State

### Key Files

- `/workspaces/cog/lib/commands/cmd_skill_lint.sh` — the linter. Structural checks in
  `__cog_skill_lint_check_structure()`; premise checks in `__cog_skill_lint_scan_premise_file()`;
  default file set from `__cog_skill_lint_add_default_files()` (globs `skills/claude`, `skills/codex`,
  `.claude/skills`). New rules go here.
- `/workspaces/cog/lib/functions/fn_skill.sh` — `cog::fn::skill::*` helpers, including the frontmatter
  allowlist (must stay in sync with `skill-contract.md` and the lint tests).
- `/workspaces/cog/test/integration/cmd_skill_lint.bats` — must stay in sync with any new lint rule
  and the allowlist; add fixtures for the new failure + allowed cases.
- `/workspaces/cog/.pre-commit-config.yaml` — already runs `bin/cog skill-lint` as a local hook;
  extending the linter propagates the new rules to ALL skills via pre-commit.
- Skill trees to sweep (inventory at execution time): `skills/claude/*` (~20, incl. prex,
  plan-queue-runner, review-loop, ask, plan-writer-multi, plan-writer, plan-reviewer, tsk-impl,
  tsk-new, gc, claudemd, pre-commit, osc-obs, suckless-patcher, test-review, review-findings,
  review-code-deep, ast-grep, refactor-migration-plan), `skills/codex/*` (~9), `.claude/skills/*`
  (skill-builder). Known remaining stale prose after Rounds 1–2:
  - `/workspaces/cog/skills/claude/review-loop/SKILL.md` (~lines 85–91): foreground/600000 + reap.
  - `/workspaces/cog/skills/claude/ask/SKILL.md` (~lines 149–155): foreground/600000 + reap.
  - `/workspaces/cog/skills/claude/plan-writer-multi/SKILL.md` (~lines 330–334): foreground/600000 +
    reap.
- Script trees to audit: `lib/commands/cmd_*.sh` (~52) and `lib/functions/fn_*.sh` (~14). Check for
  stale `codex-foreground` / `guard-codex-foreground` references and confirm command modules keep the
  line-2 `: 'desc: ...'` sentinel and naming conventions. If a command description changed in earlier
  rounds, update `/workspaces/cog/docs/reference/cli-commands.md` and help-snapshot tests.
- `/home/gbasso/.dotfiles` — confirm no stale `guard-codex-foreground.sh` or hook registration
  remains (Round 1 should have removed them); this is a final cross-repo verification.

### Existing Patterns

- A new structural `cog skill-lint` rule fails closed across the tree — the sweep MUST clear every
  newly-flagged violation or `just lint` fails. `<!-- cog-skill-lint: allow-inline-shell <reason> -->`
  suppresses premise findings only; any new rule should have a similarly narrow, documented escape if
  one is justified.
- Skill body discipline (ADR-0008 / `skill-contract.md`): skills keep judgment/sequencing in prose;
  deterministic mechanics live in cog.
- Distinguish "remove" from "keep": the env-first contract removes only the *hook-as-guarantee*
  claims. Foreground discipline + a ≥600000 Bash timeout for Codex calls remain correct guidance.
- Markdown fenced blocks declare a language (MD040); use `text` when none applies.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: encode-lint-and-sweep`) `status` to `doing`.

### Step 1: Encode the new skill-lint rules

Extend `/workspaces/cog/lib/commands/cmd_skill_lint.sh` (structural and/or premise) and any helper in
`/workspaces/cog/lib/functions/fn_skill.sh` to fail on high-confidence violations of the corrected
contract, e.g.: references to `cog hook-guard codex-foreground` / `guard-codex-foreground`; claims
that a `PreToolUse` hook is the no-backgrounding guarantee; instructions to background orchestration /
Codex work; headless `claude -p` as a preferred recursion/process primitive; unqualified claims that
foreground subagents nest at unlimited depth. Keep the rules tightly scoped so they do not block
legitimate docs that preserve external research or historical/rejected-alternative discussion (allow
those via placement outside `SKILL.md` or a narrow lint allow marker). Keep the allowlist in sync
across `fn_skill.sh`, `docs/reference/skill-contract.md`, and `test/integration/cmd_skill_lint.bats`;
add fixtures for the new failure and allowed cases. Keep deterministic logic in cog (ADR-0008).

### Step 2: Sweep all skills and agents

Inventory the actual checkout, then audit and fix:

```bash
find /workspaces/cog/skills/claude /workspaces/cog/skills/codex /workspaces/cog/.claude/skills \
  -mindepth 2 -maxdepth 2 -type f -name SKILL.md | sort
find /workspaces/cog/agents -type f -name '*.md' | sort
```

Replace stale hook-as-guarantee claims with env-first + preflight wording; keep foreground/600000
discipline where still correct; add depth-budget wording only where relevant (do not bloat unrelated
skills). Known targets: `review-loop`, `ask`, `plan-writer-multi`, plus anything the lint flags. Run
`cog skill-lint` on every touched `SKILL.md`, then on the full default set.

### Step 3: Audit command and function scripts

Inventory and audit:

```bash
find /workspaces/cog/lib/commands /workspaces/cog/lib/functions -type f \
  \( -name 'cmd_*.sh' -o -name 'fn_*.sh' \) | sort
```

Check for stale `codex-foreground` / `guard-codex-foreground` references and confirm every command
module keeps its line-2 `: 'desc: ...'` sentinel and the `cog::cmd::<slug>` / `cog::fn::*` naming
conventions. Update `/workspaces/cog/docs/reference/cli-commands.md` and help-snapshot tests if any
command description changed across the plan.

### Step 4: Verify no leftovers (cross-repo)

Run targeted searches from both repos:

```bash
rg -n "codex-foreground|guard-codex-foreground|hook is the guarantee" \
  /workspaces/cog /home/gbasso/.dotfiles
```

Expected: no `codex-foreground` / `guard-codex-foreground` references remain except deliberate
historical/rejected-alternative documentation (ADR-0009, the explanation doc); the only surviving
`hook-guard` references are the kept `prex-stop` ones; env vars present in `base.json` + docs; the
foreground-guard `PreToolUse` registration gone; the `Stop` registration kept.

### Step 5: Run the full gates

Run `just lint` and `just test` until clean (pre-commit is the quality SoT). Resolve every
newly-flagged `cog skill-lint` violation. Commit via `/gc`; the executor must NOT run git directly.

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: encode-lint-and-sweep`) `status` to `done`.
2. All rounds are now done, so in the top-level `.implementation-plans/queue-plans.yaml` set this plan's
   (`item: skills-under-skills-env-first`) `status` to `done`. Leave the plan directory in place.

## Acceptance Criteria

- [ ] New `cog skill-lint` rule(s) exist, fail stale codex-foreground / hook-as-guarantee /
      background-orchestration claims, are covered by `test/integration/cmd_skill_lint.bats`, and the
      allowlist is in sync across `fn_skill.sh` + `skill-contract.md` + tests.
- [ ] `cog skill-lint` over the full default set passes; every skill in `skills/claude/*`,
      `skills/codex/*`, `.claude/skills/*` conforms.
- [ ] `review-loop`, `ask`, `plan-writer-multi`, and any other flagged skill no longer claim a hook
      is the guarantee; correct foreground/600000 discipline wording is retained where appropriate.
- [ ] Every `lib/commands/cmd_*.sh` keeps its line-2 sentinel and naming conventions; no stale
      codex-foreground references remain in scripts; `cli-commands.md` and help snapshots are in sync.
- [ ] The cross-repo `rg` sweep finds no stale leftovers (only the kept `prex-stop` references and the
      deliberate ADR/explanation history remain).
- [ ] `just lint` and `just test` pass.
- [ ] This plan's `queue-rounds.yaml` shows round `encode-lint-and-sweep` as `done`, and the top-level
      `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

This is the final round.
