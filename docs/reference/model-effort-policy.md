# Model/Effort Policy

This is the human-readable source of truth for choosing `model:` and `effort:` in `cog` skills and
for selecting Codex model/effort profiles through `cog codex-runner` or `codex-session`.

The machine-readable policy data lives in:

- [`model-effort-claude.toml`](model-effort-claude.toml)
- [`model-effort-codex.toml`](model-effort-codex.toml)

## Hard Rule

Never use `model: sonnet` in a `cog` skill. Use `model: opus` with `effort: low` instead.

This is an authoring rule for skill frontmatter and model selection. It is not a runtime file that
skills load mid-execution.

## Defaults

Exploration and planning skills normally set no `model:` or `effort:` override. They ride the
session default:

- Claude: Opus + high.
- Codex: `gpt-5.5` + medium.

A skill author may override the default for a specific case when the task justifies it, but the
override should be documented where the model choice is made.

## Tiers

The TOML files are the machine-readable source of truth for exact values and descriptive fields. Use
this table as the human-readable rationale:

| Tier | Use when | Authoring action |
| --- | --- | --- |
| Exploration | Open-ended reasoning, planning, codebase exploration, design review, or question answering. | Set no skill frontmatter override; use the session default. |
| Procedural | A detailed procedure or plan already exists, deterministic mechanics are delegated to `cog`, and bounded judgment remains. | Pin the procedural tier from the provider TOML. For Claude this is the never-Sonnet replacement tier. |
| Routine | The task is thin orchestration over deterministic mechanics with no meaningful reasoning. | Pin the routine tier from the provider TOML. For Claude Haiku, omit `effort`. |

## How To Classify Work

1. Read the relevant provider TOML file.
2. Match the task against each tier's `use_when`, `signals`, and `anti_signals`.
3. Set `model:` and `effort:` only when `set_frontmatter = true`.
4. For Claude routine tasks on Haiku, omit `effort`; Haiku returns an error when effort is sent.
5. For Codex, choose the `cog codex-runner` or `codex-session` profile according to
   `model-effort-codex.toml`.

Do not pin `-codex` models for subscription-auth Codex. The Codex policy pins only `gpt-5.5`,
`gpt-5.4`, or `gpt-5.4-mini` for that path.

## Review And Verification Work

Reviewing or verifying an already-reasoned artifact (plan review, code review) is exploration-tier
work: it rides the session default (Claude opus + high; Codex gpt-5.5 + medium) and sets no
frontmatter override. Generator-verifier asymmetry makes critique cheaper than generation, but
correctness judging is non-trivial, so the high default is the right floor rather than a reduced
tier. Reserve the xhigh/max exception tiers for reviews that span many subsystems, are
security-critical, are expensive to reverse, or run as evaluations. See ADR-0027 and the
research-shelf entry tagged `verifier-asymmetry`.

## Evidence And Revalidation

This policy is backed by dated reference files:

- [`models-reference-claude.md`](models-reference-claude.md), data collected `2026-06-19`.
- [`models-reference-codex.md`](models-reference-codex.md), data collected `2026-06-19`.

Revalidate this policy when those evidence files are revalidated, or sooner on model, pricing,
availability, or effort-support changes.

## Follow-Ups

The following are intentionally out of scope for this round:

- Building a `cog model-policy` lookup command.
- Changing `cog codex-runner` wiring.
- Re-grading existing skill frontmatter.
