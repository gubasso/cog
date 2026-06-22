# Foreground Orchestration

`cog` orchestration is built around one live Claude Code session, foreground all the way down. The
parent session delegates to a foreground subagent when it needs isolation, then waits while that
subagent does its work. If that subagent delegates again, the same call-stack shape continues until
the chain returns.

This is different from background fan-out. Foreground delegation is synchronous: the parent remains
alive, the event loop remains present, and the parent can verify durable state when control returns.
Workflow-style background work is useful for independent parallel tasks, but it is not the primitive
for recursive orchestration.

## Corrected Backgrounding Finding

Claude Code can auto-background long-running Bash work at runtime. A `PreToolUse(Bash)` hook sees
only the requested tool input before execution begins. It cannot observe or block the later runtime
decision to auto-background a command.

That distinction matters. A field case used a foreground Codex call with `timeout: 600000`; the hook
allowed the request, and the call was still auto-backgrounded later. The fix is environment, not a
hook: `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` disables background-task functionality.

## Long Codex Runs Are Durable Jobs, Not Foreground Bash Calls

An earlier version of this note claimed long Bash timeouts keep a long Codex call inside the
foreground window. That is false: the Bash tool enforces a hard ~600s ceiling that no env var raises,
and the ceiling SIGTERMs the foreground process tree, orphaning the child. So a long agent run is not
a single foreground Bash call. `cog` launches it as a durable job — detached in its own session via
`setsid`, with an atomically-updated state file — and the orchestrator brings it to a result with one
verb, `finalize --max-wall <secs>`, which polls then classifies from durable artifacts even if the
polling call was killed. Duration is never judged. **The exit code is the signal**: `finalize` exits
`0` (ok), `1` (failed), or `75` (still running); the orchestrator re-issues the bounded `finalize`
*tool call* while it sees `75` — a `$?`-based retry across tool calls, not a shell `while` inside one
>600s call. This is cog detaching its own process, distinct from the model backgrounding a tool call
(still banned). See the orchestration contract's "Durable Long-Running Jobs" and
[ADR-0022](../decisions/0022-cog-owned-durable-longrun.md).

## Future Durable-Queue Trampoline

Claude Code's subagent depth budget is fixed at five levels below the main conversation. Most
composition should avoid spending that budget by chaining skills inline when they can share context,
and by using foreground Agent delegation only at real isolation boundaries.

If a future workflow truly needs more than five isolated delegation levels, flatten the recursion
through a durable queue. The current chain writes the next unit of work to durable state, verifies
that state, and returns. A fresh foreground chain then starts from the queued item. This trampoline
keeps each live call stack within the depth budget while preserving deterministic handoff through
queue state. It is documented here as a future option; this round does not build it.
