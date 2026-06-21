# ADR-0019: Lean, Positively-Framed Skill Prose

## Context and Problem Statement

`SKILL.md` files are loaded into a runtime context window on every invocation, so every token is a
runtime cost. Skills had accumulated two recurrent kinds of waste: preemptive "what this skill is
not" scoping that duplicated guardrails already stated elsewhere, and source-repo meta — twin/canon
cross-references to another skill's source path (e.g. `skills/claude/<name>/SKILL.md`) — that has no
meaning in an end user's installed runtime, where each skill resolves under that user's own tree.

## Considered Options

- Leave skill prose to author discretion.
- Require lean, positively-framed prose; document it; lint the mechanical part.
- Mechanically lint tone/negation as well as source paths.

## Decision Outcome

Chosen option: **require lean, positively-framed prose** — describe what a skill IS and MUST DO, not
what it isn't. Preemptive negative guardrails without an empirical reason are removed; negative or
exclusion statements are allowed only when explicitly requested or when correcting a recurrent drift.
Runtime skill files carry no source-repo meta; such meta belongs in `docs/`. The source-path
prohibition is enforced mechanically by the `skill-source-path-reference` rule in `cog skill-lint`;
the positive-framing principle stays prose judgment, since a tone/negation linter would be noisy and
would itself violate this rule.

## Consequences

- Good: leaner runtime context; positive prose is clearer; the high-confidence source-path lint
  catches the one mechanically-detectable class without false positives on authoring placeholders
  (`skills/claude/<name>/SKILL.md`) or runtime-installed paths (`$HOME/.claude/skills/...`).
- Bad: positive-framing relies on review judgment, not automation; deciding whether a negative is a
  legitimate drift guardrail or preemptive noise is a per-case call.

## Status

Implemented. Enforced by the `skill-source-path-reference` rule in
`lib/commands/cmd_skill_lint.sh`; contract recorded in
`docs/reference/skill-contract.md` ("Lean positive prose").
