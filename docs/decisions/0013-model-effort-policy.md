# ADR-0013: Model/Effort Policy

## Context and Problem Statement

Skill model/effort choices were an implicit convention: exploration skills usually set no override,
procedural skills usually use Opus at low effort, and routine skills use Haiku. The predecessor of
the project-local `.claude/skills/review-implementation-plans/SKILL.md` skill was the lone
`model: sonnet` + `effort: high` outlier. Round-1 pricing and quality evidence backs Opus at lower
effort over Sonnet.

## Considered Options

- Keep the implicit convention.
- Allow Sonnet for selected skill classes.
- Define a `docs/reference/` source of truth with descriptive TOML and a no-Sonnet rule.

## Decision Outcome

Chosen option: **Define a `docs/reference/` source of truth with descriptive TOML and a no-Sonnet
rule** - skill model/effort selection needs a reviewable policy, and `model: sonnet` is forbidden in
favor of `model: opus` + `effort: low`.

The source of truth is `docs/reference/model-effort-policy.md`,
`docs/reference/model-effort-claude.toml`, and `docs/reference/model-effort-codex.toml`.

## Consequences

- Good: Skill authors classify work by tier and declare or omit frontmatter consistently.
- Good: Future model refreshes update the evidence and policy in one documented place.
- Bad: Existing outliers must be re-graded; Round 3 re-grades the renamed
  `review-implementation-plans` skill to Opus at low effort.

## Status

Accepted
