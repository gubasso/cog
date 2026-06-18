# ADR-0010: Orchestration env-first

## Context and Problem Statement

ADR-0007 chose in-session foreground subagent delegation over headless `claude -p`, but its hook
stance predated the corrected finding: Claude Code can auto-background long-running Bash at runtime.
The architecture needs a durable rule for Codex and recursive orchestration calls that a
`PreToolUse(Bash)` hook cannot provide.

## Considered Options

- Keep foreground discipline as prose plus the removed `codex-foreground` hook.
- Make session environment the no-backgrounding guarantee and have `cog` assert it.
- Return to headless `claude -p` and avoid nested subagents.

## Decision Outcome

Chosen option: **make session environment the guarantee and have `cog` assert it**. `claude-session`
sets `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` with long Bash timeouts; `cog` preflights the runtime
state fail-closed. A `PreToolUse(Bash)` hook sees requested tool input only, not the later runtime
auto-background decision, so hook-based enforcement is the wrong tool.

Skills chain inline in the same context at zero depth cost. Agent delegation uses a foreground
subagent with its own context, blocks the parent, and spends one subagent level. Workflows are
background fan-out, not synchronous recursion. Headless `claude -p` remains the abandoned
reap-prone host model. Claude Code has a fixed five-level subagent cap: changelog v2.1.172 enabled
subagents up to five levels deep, v2.1.181 applied the same depth limit to foreground subagents, and
the current sub-agents doc agrees that depth counts foreground and background levels, depth five
does not receive the Agent tool, and the limit is not configurable.

The durable-queue trampoline is documented as a future option for composition beyond depth five, not
built here. `prex-stop` stays, including the Round 1 `stage3-impl-report.txt` check.

## Consequences

- Good: no-backgrounding is enforced by runtime state instead of an observationally-blind hook.
- Good: depth is explicit; skills spend Agent levels only at isolation boundaries.
- Bad: orchestration sessions still require the correct `claude-session` environment.

## Status

Accepted. Supersedes the hook stance in [ADR-0007](0007-in-session-subagent-delegation.md) and
keeps the mechanics boundary from [ADR-0008](0008-skill-script-boundary.md).
