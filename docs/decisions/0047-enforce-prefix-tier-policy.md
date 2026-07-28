# ADR-0047: Enforce prefix→tier policy via skill-lint with a registry escape hatch

## Context and Problem Statement

[ADR-0041](./0041-named-tier-ladder.md) and the model/effort policy say every governed Claude skill should ride a named power/capability tier (`xhigh|high|medium|low|cheap`), but nothing verified that a skill's `model:`/`effort:` frontmatter actually matched its expected tier. The policy was prose-only, so drift between a skill's stated cell and its policy tier was silent. The deliberate exceptions (delegation launchers ride low, `executor-prex` rides high, `review-loop` round-1 rides high) made a naive "one tier per prefix" rule wrong.

## Considered Options

- Leave it prose-only and rely on review.
- Hardcode a curated skill→tier exception map in `cog skill-lint` (a second copy of the policy).
- Make the per-tier skill lists already in `model-effort-claude.toml` the authoritative registry and enforce against it, with a prefix-default fallback.

## Decision Outcome

Chosen option: **registry-driven enforcement** — the per-tier `skills = [...]` lists in `docs/reference/model-effort-claude.toml` (renamed from `examples`) are the authoritative governed-tier registry and the single escape hatch. The `model-effort-tier` `cog skill-lint` rule resolves a Claude skill's expected tier as registry pin > prefix default > `exempt`, resolves its actual tier from frontmatter (absent `model`/`effort` = session default HIGH; `opus`+`high` is equivalent; `haiku` = cheap), and fails on mismatch. The known exceptions live as registry pins, not as code. `cog power-grade profile --name <tier>` and `cog power-grade skill-tier --skill <name>` expose the same SoT to authors. This refines ADR-0041/ADR-0013 without superseding them.

## Consequences

- Good: drift is caught mechanically; one SoT (the policy TOML) feeds both lint and lookup; exceptions are explicit, greppable, and self-documenting.
- Good: the current skill tree already passes — adding the rule broke nothing.
- Bad: a deviating skill must be added to a registry list, coupling the policy TOML to lint behavior; `examples`→`skills` is a rename the codex twin mirrors for symmetry only.

## Status

Implemented. `cog::fn::skill::expected_tier`/`tier_for_frontmatter` in `lib/functions/fn_skill.sh`; the `model-effort-tier` rule in `lib/commands/cmd_skill_lint.sh`; `profile`/`skill-tier` verbs in `lib/commands/cmd_power_grade.sh` and `lib/functions/fn_power_grade.sh`.
