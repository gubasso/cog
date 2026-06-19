# Orchestration Contract

This reference defines how `cog` skills and agents compose Claude, Codex, queues, and subagents.
Skills keep sequencing and judgment in prose; deterministic checks and workflow mechanics stay in
`cog`.

## Recursion Primitives

| Primitive | Runtime shape | Depth cost | Contract |
| --- | --- | --- | --- |
| Skill-inline | Same context window | 0 | Use for same-context chaining when no isolation boundary is needed. |
| Agent-delegate / foreground subagent | Own context; parent blocks until the chain returns | 1 subagent level | Use at true isolation boundaries. Hard cap is 5 levels. |
| Workflow | Background parallel fan-out | Not synchronous recursion | Use for independent parallel work, not call-stack style orchestration. |
| Headless `claude -p` | Separate process without the live interactive event loop | Avoid | Abandoned for recursive orchestration because backgrounded work can be reaped after the final turn. |

## Environment Requirements

The primary no-backgrounding lever is:

```text
CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
```

This disables background-task functionality, including Bash and subagent `run_in_background`,
auto-backgrounding, and Ctrl+B. It keeps subagent spawns synchronous.

The defensive complement is to set both Bash timeout variables to integers at least `600000`:

```text
BASH_DEFAULT_TIMEOUT_MS=600000
BASH_MAX_TIMEOUT_MS=600000
```

The timeout pair does not replace `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`. It prevents short Bash
timeouts from pressuring the model or harness toward backgrounding a long Codex call.

`claude-session` configuration is the source of truth for env and hook registration. `cog` asserts
the observed runtime state fail-closed before orchestration work that depends on this contract.

## Delegate And Verify

Every orchestration boundary must verify a durable postcondition after the delegate returns. A parent
must re-read state such as a queue item, report file, or test artifact rather than trusting a returned
summary.

For queue-driven work, the usual postcondition is:

```text
inner queue-rounds.yaml round status == done
top-level queue-plans.yaml plan status == done
```

Plan directories are flat siblings, a single level under `.implementation-plans/plans/`; ordering
between plans lives only in `queue-plans.yaml` `depends_on`, never in the filesystem. The runner and
the revision boundary both rely on this: `cog runner-queue-resolve-plan` requires each resolved
plan to be a direct child of `plans/`, and `cog review-implementation-plans-scan` fails closed on any nested plan.

A queue runner may invoke a revision subagent as a foreground sibling boundary after a committed item.
The revision subagent is a sibling of the round delegate (a +1 from the runner's depth 0), not nested
beneath it, so the boundary stays flat against the depth cap; it spends one depth level and must
verify a clean, committed postcondition before selecting more work.

## Depth Budget

Claude Code permits a fixed maximum of five subagent levels below the main conversation. The limit
applies regardless of whether each level is foreground or background. A subagent at depth five does
not receive the Agent tool and cannot spawn further; the limit is fixed and not configurable.

Spend depth only when isolation is valuable. Chain skills inline when same-context composition is
enough. When a design would exceed depth five, flatten it into durable queue iteration: persist the
next unit of work, return to the parent, and start a fresh foreground chain from queue state. This
durable-queue trampoline is a documented future option, not a new mechanism in this round.

## External References

- https://code.claude.com/docs/en/tools-reference
- https://code.claude.com/docs/en/env-vars
- https://code.claude.com/docs/en/sub-agents
- https://code.claude.com/docs/en/changelog
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/hooks-guide
- https://code.claude.com/docs/en/interactive-mode
- https://code.claude.com/docs/en/workflows
- https://developers.openai.com/codex/cli/reference
