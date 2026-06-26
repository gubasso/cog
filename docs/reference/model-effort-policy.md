# Model/Effort Policy

This is the human-readable source of truth for choosing `model:` and `effort:` in `cog` skills and
for selecting Codex model/effort profiles through `cog codex-runner` or `codex-session`.

The machine-readable policy data lives in:

- [`model-effort-claude.toml`](model-effort-claude.toml)
- [`model-effort-codex.toml`](model-effort-codex.toml)
- [`power-grade-matrix.toml`](power-grade-matrix.toml)

The provider TOML files define policy tier selection. `power-grade-matrix.toml` is the source of
truth for profile capability grades, source-cited profile evidence, named policy pairings, validation
severity, and compound-pass math.

## Hard Rule

Never use `model: sonnet` or `model: fable` in a `cog` skill. For the Sonnet case, use `model: opus`
with `effort: low` instead. The forbidden set is the machine SoT in `model-effort-claude.toml`
(`forbidden_models`).

This is an authoring rule for skill frontmatter and model selection. It is not a runtime file that
skills load mid-execution.

## Defaults

High-tier skills (open-ended reasoning, planning, plan review) normally set no `model:` or `effort:`
override. They ride the session default:

- Claude: Opus + high.
- Codex: `gpt-5.5` + medium.

A skill author may override the default for a specific case when the task justifies it, but the
override should be documented where the model choice is made.

## Tiers

The canonical tier vocabulary is a five-rung named ladder — `XHIGH`, `HIGH`, `MEDIUM`, `LOW`,
`CHEAP` — adopted in ADR-0041. It supersedes the former `exploration`/`procedural`/`routine` tier
names and the `exploration`/`single-pass-escalation`/`routine` power-grade pairings. Each rung maps
to one Claude cell and one Codex cell:

| Tier | Claude cell | Codex cell | Use when | Authoring action |
| --- | --- | --- | --- | --- |
| XHIGH | opus-4.8@xhigh | gpt-5.5@high | Hardest single-pass work or a full from-scratch review that rebuilds an entire codebase, plan, and diff. | Pin the xhigh rung (Claude `opus`+`xhigh`). |
| HIGH | opus-4.8@high | gpt-5.5@medium | Open-ended reasoning, planning, plan review, or question answering. This is the session default. | Set no override; ride the session default. |
| MEDIUM | opus-4.8@medium | gpt-5.5@low | Executor default and resumed warm re-review: implement a prepared plan with bounded judgment. | Pin the medium rung (Claude `opus`+`medium`). |
| LOW | opus-4.8@low | gpt-5.4@medium | A detailed procedure exists, deterministic mechanics are delegated to `cog`, and bounded judgment remains; also verbatim dispatch. | Pin the low rung. For Claude this is the never-Sonnet replacement tier. |
| CHEAP | haiku (no effort) | gpt-5.4-mini@medium | Thin orchestration over deterministic mechanics with no meaningful reasoning. | Pin the cheap rung. For Claude Haiku, omit `effort`. |

The TOML files (`model-effort-claude.toml`, `model-effort-codex.toml`) are the machine-readable
source of truth for exact values and descriptive fields per rung.

### Prefix-to-tier defaults

The skill-prefix taxonomy maps to default rungs (override per skill only with recorded justification):

- `plan-*` → HIGH.
- `executor-*` → MEDIUM by default; a reasoning executor that judges, re-evaluates, directs, or fixes
  (e.g. `executor-prex`) may ride HIGH.
- `review-plan-*` → HIGH (reviewing an already-distilled plan/spec).
- `review-oneshot-*` → XHIGH (fresh-context full review).
- `runner-*` → LOW for verbatim prompt-opaque dispatch; higher only when it does routing policy,
  triage, or retry decisions.

## How To Classify Work

1. Read the relevant provider TOML file.
2. Match the task against each rung's `use_when`, `signals`, and `anti_signals`.
3. Set `model:` and `effort:` only when `set_frontmatter = true` (HIGH rides the default and sets no
   override).
4. For Claude CHEAP tasks on Haiku, omit `effort`; Haiku returns an error when effort is sent.
5. For Codex, choose the `cog codex-runner` or `codex-session` profile according to
   `model-effort-codex.toml`.

Do not pin `-codex` models for subscription-auth Codex. The Codex policy pins only `gpt-5.5`,
`gpt-5.4`, or `gpt-5.4-mini` for that path.

## Power Grade Profiles

Power Grade profiles are model/effort capability cells used by `cog power-grade`. The matrix defines
a 1-10 difficulty-ceiling scale, one executable profile per supported model/effort cell, non-fatal
`needs_verification` evidence markers for genuine public-data gaps, and named policy pairings:

- `xhigh`: Opus 4.8 at xhigh effort / `gpt-5.5` at high effort.
- `high`: Opus 4.8 at high effort / `gpt-5.5` at medium effort (the session default).
- `medium`: Opus 4.8 at medium effort / `gpt-5.5` at low effort.
- `low`: Opus 4.8 at low effort / `gpt-5.4` at medium effort.
- `cheap`: Haiku 4.5 with no effort / `gpt-5.4-mini` at medium effort.

Use `cog power-grade validate --json` to check the matrix, `cell` to inspect one profile, `classify`
to find policy-selectable profiles that can handle a grade (non-selectable and informational cells
are excluded), and `compound` to compute pass-sequence capability from the matrix-owned formula.

## Review And Verification Work

Review effort tracks how much context the reviewer must reconstruct (ADR-0041, refining ADR-0027):

- `review-plan-*` → **HIGH**. Reviewing an already-distilled plan/spec rides the session default.
  Generator-verifier asymmetry makes critique cheaper than generation, tempered by the difficulty of
  correctness judging, so HIGH is the right floor.
- `review-oneshot-*` → **XHIGH**. A fresh-context full review must rebuild the entire codebase, plan,
  and diff before it can judge; that reconstruction cost erodes the asymmetry discount, so the floor
  rises to XHIGH.
- `review-loop` → **round 1 HIGH, rounds 2+ MEDIUM**. Round 1 is a fresh from-scratch review with full
  input. Rounds 2+ resume the prior reviewer context (warm, not cold) and both re-check prior findings
  and re-review for new regressions; the retained context earns one rung of discount (to MEDIUM), not
  two (LOW would be unsafe while new fix-code regressions remain in scope).

See ADR-0041 and ADR-0027, and the research-shelf entry tagged `verifier-asymmetry`.

## Evidence And Revalidation

This policy is backed by dated reference files:

- [`models-reference-claude.md`](models-reference-claude.md), data collected `2026-06-19`.
- [`models-reference-codex.md`](models-reference-codex.md), data collected `2026-06-19`, re-verified
  `2026-06-24`.
- [`power-grade-matrix.toml`](power-grade-matrix.toml), data collected `2026-06-24`.

Revalidate this policy when those evidence files are revalidated, or sooner on model, pricing,
availability, or effort-support changes.

## Follow-Ups

The following are intentionally out of scope for this round:

- Building a `cog model-policy` lookup command.
- Changing `cog codex-runner` wiring.
- Re-grading existing skill frontmatter.
