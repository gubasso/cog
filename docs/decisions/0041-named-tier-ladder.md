# ADR-0041: Named Model/Effort Tier Ladder

## Context and Problem Statement

Model/effort selection used three tier names — `exploration`, `procedural`, `routine` — in the provider TOMLs and three power-grade pairings — `exploration`, `single-pass-escalation`, `routine`. The names described _roles_, not the relative power level, and the set did not cover every model/effort cell the policy actually wanted (notably an opus@medium rung and a gpt-5.5@low rung). Review effort rode a single exploration default for every review skill (ADR-0027), which under-graded full from-scratch code review and left `review-loop` re-reviewing the whole live diff cold every round.

Every effort cell under consideration is real and supported: Opus 4.8 exposes `low/medium/high/xhigh/
max` (default `high`); `gpt-5.5`, `gpt-5.4`, and `gpt-5.4-mini` each expose `minimal/low/medium/high/
xhigh` via the Codex `model_reasoning_effort` key (API `reasoning_effort` uses `none` for the lowest tier, which equals Codex `minimal`); Haiku 4.5 rejects a selectable effort. Evidence: `docs/reference/models-reference-claude.md` and `docs/reference/model-effort-codex.toml` `[supported_efforts]`.

## Considered Options

- Keep the three role-named tiers and add ad-hoc per-skill overrides.
- Adopt a power-ordered named ladder that names every policy-selectable rung.

## Decision Outcome

Chosen option: **a five-rung power-ordered named ladder** — `XHIGH`, `HIGH`, `MEDIUM`, `LOW`, `CHEAP` — as the canonical tier vocabulary. Each rung maps to one Claude cell and one Codex cell:

| Tier   | Claude cell       | Codex cell          |
| ------ | ----------------- | ------------------- |
| XHIGH  | opus-4.8@xhigh    | gpt-5.5@high        |
| HIGH   | opus-4.8@high     | gpt-5.5@medium      |
| MEDIUM | opus-4.8@medium   | gpt-5.5@low         |
| LOW    | opus-4.8@low      | gpt-5.4@medium      |
| CHEAP  | haiku (no effort) | gpt-5.4-mini@medium |

### Old-to-new reconciliation

- `exploration` (opus@high / gpt-5.5@medium) → **HIGH** (the session default; cells unchanged).
- `single-pass-escalation` (opus@xhigh / gpt-5.5@high) → **XHIGH** (cells unchanged).
- `routine` (haiku / gpt-5.4-mini@medium) → **CHEAP** (cells unchanged).
- `procedural` (opus@low / gpt-5.5@medium) → **LOW** by its Claude cell (opus@low). The old `procedural` Codex cell (gpt-5.5@medium) collided with the new HIGH Codex cell; the new LOW Codex cell is gpt-5.4@medium. Codex skills carry no SKILL.md frontmatter, so a skill's Codex tier is realized per-invocation by `cog codex-runner`; the divergence is resolved at invocation, not in frontmatter.
- **MEDIUM** (opus@medium / gpt-5.5@low) is a new rung with no old name.

### CHEAP Codex effort

CHEAP's Codex cell is `gpt-5.4-mini@medium`, not the model floor (`minimal`). This preserves the prior `routine`-tier value across the rename and matches the high-confidence `codex-gpt-5.4-mini-medium` power-grade profile rather than silently lowering the cheap reviewer's effort.

### Prefix-to-tier defaults

- `plan-*` → HIGH.
- `executor-*` → MEDIUM by default; a reasoning executor that judges, re-evaluates, directs, or fixes (e.g. `executor-prex`) may ride HIGH.
- `review-plan-*` → HIGH.
- `review-oneshot-*` → XHIGH.
- `runner-*` → LOW for verbatim prompt-opaque dispatch; higher only when it does routing policy, triage, or retry decisions.

Delegation launchers (the thin Claude wrappers that run Codex under the hood, e.g. `executor-oneshot-codex`, `plan-oneshot-codex`) ride LOW: the Claude wrapper does little reasoning and the real work runs under Codex.

### Review tiers (refines ADR-0027)

ADR-0027 placed all review/verification at the exploration default. This ADR refines that:

- `review-plan-*` → HIGH (reviewing an already-distilled plan rides the session default — the ADR-0027 floor, now named HIGH).
- `review-oneshot-*` → XHIGH (a fresh-context full review rebuilds the whole codebase/plan/diff before judging; the reconstruction cost erodes the generator-verifier asymmetry discount).
- `review-loop` → round 1 HIGH, rounds 2+ MEDIUM.

### review-loop resumed-context behavior

`review-loop` round 1 is a fresh from-scratch review with full input. Rounds 2+ **resume** the round-1 Codex reviewer thread (warm context that retains prior-round findings) via `cog codex-runner
run-resume`, rather than spawning a fresh cold `review-oneshot` each round. Each resumed round both re-checks whether prior findings were resolved and performs a full re-review for new regressions. The retained context earns one rung of discount (HIGH → MEDIUM); LOW would be unsafe while regressions in the unseen fix-code remain in scope. The round-1 Codex effort (`medium`, the HIGH Codex cell) and the rounds-2+ effort (`low`, the MEDIUM Codex cell) are unchanged in value; the substantive change is the cold→warm resume switch and the tier naming.

This ADR refines ADR-0013's tier naming and the ADR-0027 review-effort outcome. Accepted ADRs are retained unedited; the supersession is recorded here.

## Consequences

- Good: tier names are power-ordered and cover every policy-selectable rung, including the previously unnamed opus@medium and gpt-5.5@low cells.
- Good: review effort is matched to context-reconstruction cost; `review-loop` rounds 2+ reuse warm reviewer context instead of paying a cold full re-read every round.
- Neutral: `executor-oneshot`/`executor-vetted` move to MEDIUM and `review-oneshot` to XHIGH, raising their token budgets intentionally; `plan-vetted` rides HIGH instead of an explicit opus@low.
- The only machine consumer of tier/pairing names is `cog power-grade` via `power-grade-matrix.toml` `[[named_profiles]]`; `cog skill-lint` has no tier rule, so the rename needs no lint-code change.

## Status

Implemented. The ladder lives in `docs/reference/model-effort-claude.toml`, `docs/reference/model-effort-codex.toml`, `docs/reference/power-grade-matrix.toml`, and `docs/reference/model-effort-policy.md`; `cog power-grade validate` gates the named pairings.

Amended by [ADR-0070](./0070-executor-prex-explicit-plan-review-split-and-review-oneshot-high.md) for `review-oneshot`: the `review-oneshot-*` family default recorded here stays XHIGH, but the `review-oneshot` skill itself is pinned to HIGH as a deliberate cost/latency exception via its `high` registry membership.
