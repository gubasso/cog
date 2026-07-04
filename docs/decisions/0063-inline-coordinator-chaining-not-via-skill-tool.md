# ADR-0063: Chain a disable-model-invocation coordinator via Agent delegation, not the Skill tool

## Context and Problem Statement

Several Claude coordinators told the model to chain another coordinator "inline via the `Skill` tool"
(`plan-vetted` → `plan-multi`; `plan-builder-to-queue` → `plan-oneshot`;
`plan-builder-to-queue-vetted-multi` → `plan-vetted`/`review-plan-multi`; both builders →
`review-plan-complexity`/`plan-split`). Every one of those targets sets
`disable-model-invocation: true`, so the harness's `Skill` tool refuses the model-initiated call. The
flag is intended — these coordinators must be invoked deliberately, not autonomously by description
match — so the prose is the defect, not the frontmatter.

## Considered Options

- Remove `disable-model-invocation` from the chained targets so the `Skill` tool accepts them.
- Keep the flag; invoke the target through foreground Agent-tool delegation — a `claude-delegate`
  subagent, or an inline-chain that reads the target's `SKILL.md` and follows it — never the `Skill`
  tool.

## Decision Outcome

Chosen option: **keep the flag; invoke the target through foreground Agent-tool delegation, never the
`Skill` tool.** Two established, equivalent primitives resolve the chain:

- A **`claude-delegate`** subagent (ADR-0007) — a fresh, full Claude run that itself spawns the target's
  subagents (e.g. `plan-multi`'s dual planning engines and forked Codex worker). This is the
  consolidated nested-orchestration primitive the runners and executors already use.
- An **inline-chain** — read `$HOME/.claude/skills/<target>/SKILL.md` and follow it in the caller's own
  context. This is how `executor-vetted` and `executor-prex` already chain `plan-vetted`.

The choice follows the Orchestration Guards: chain inline when same-context is enough; delegate through
`claude-delegate` at an isolation boundary or when the target must itself spawn subagents. Either way,
the harness `Skill` tool is never used for a `disable-model-invocation` target (it stays reserved for
non-DMI skills such as `context-builder`). Operator interviews survive both forms: inline-chaining lets
the target's own `AskUserQuestion` reach the operator through the caller's context, and a delegated run
works from decisions the launching coordinator settled upfront and carried in the brief.

## Consequences

- Good: the broken sites work at runtime through the same primitives the runners and executors already
  use; a `cog skill-lint` guard (`inline-skill-tool-dmi`) prevents Skill-tool regression; no frontmatter
  flags change; the `claude-delegate` nested-orchestration architecture is honored.
- Bad: the author picks the delegation form (inline vs `claude-delegate`) per site.

References ADR-0007 (in-session `claude-delegate` subagent delegation) and the "Orchestration Guards".

## Status

Accepted (2026-07-04)
