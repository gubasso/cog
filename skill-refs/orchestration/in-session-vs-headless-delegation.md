# In-session subagent delegation vs headless `claude -p`

Decision record + canon for how orchestrating skills run a fresh, full Claude execution (a delegated unit of work that may itself spawn subagents — e.g. `/executor-prex`, which delegates plan review, code review, and a review loop).

## Decision

Run delegated agentic work as **in-session foreground subagents**, not via a headless `claude -p` subprocess. A generic `claude-delegate` subagent is the reusable primitive; orchestrators (for example `runner-all` and `runner-plan`) dispatch each unit to it via the **Agent tool**.

## Why headless `claude -p` was wrong

Headless / print mode has **no event loop after the model's final turn**. Per the official docs, a background Bash task started during a `claude -p` run is **terminated ~5 s after Claude returns its final result**. So an orchestrated round that backgrounded its long Codex call (rationalizing "I'll be re-invoked when it completes") had the detached Codex **reaped before later stages ran** — work landed partially, review stages never ran, the unit silently stayed incomplete, and the process still exited `0`. A prose "never background" mandate is advisory and was overridden on large units.

The `claude -p` host existed only because subagents historically could not spawn subagents, and a unit like `/executor-prex` must delegate internally. That constraint is gone.

## What changed

Claude Code **v2.1.172** (2026-06-10) added **nested subagents**:

- A subagent can spawn its own subagents. **Foreground subagents can spawn at any depth** — each level blocks its parent until it returns, so the chain is self-limiting (the main conversation waits on the whole chain). Background subagents are capped at depth 5.
- A subagent **inherits all tools when `tools` is omitted** (so it gets `Agent` + `Skill` and can both run skills and nest). The full CLAUDE.md / memory hierarchy loads at every level.
- A subagent **inherits the parent's permission mode** (`bypassPermissions` propagates), so unattended privilege is preserved with no per-process flags.

See <https://code.claude.com/docs/en/sub-agents> ("Spawn nested subagents") and <https://code.claude.com/docs/en/headless> ("Background tasks at exit").

## Considered options

1. **Headless `claude -p` + prose mandate** — rejected: no post-turn event loop; backgrounded Codex reaped; mandate advisory.
2. **Headless `claude -p` + a deterministic `PreToolUse` hook denying backgrounded Codex calls** — viable, but adds a hook and keeps the fragile per-round process host. Deferred.
3. **In-session foreground subagents** — chosen.

## Consequences

- Good: synchronous blocking; shared live event loop (background tasks owned by the long-lived parent, not reaped per unit); no per-round process spawn; native nesting; a single uniform delegation primitive; inherited permission mode.
- Bad: the orchestrating session must stay alive for the whole run; we rely on foreground discipline rather than a hard hook.

## The standing rules (unchanged, and why)

- **Every Codex `exec`/`resume` is a cog-owned durable job**, regardless of host (headless **or** in-session/forked subagent). Launch it with `cog codex-runner run-exec`/`run-resume --state`, then bring it to a result with one verb: `cog codex-runner finalize --state <file> --max-wall <secs>`, which polls up to `--max-wall` then classifies from durable artifacts. cog runs the process in its own session with a durable state file, so the run is never time-gated (the Bash tool's hard ~600s ceiling cannot kill it) and an interrupted observer loses nothing. **The exit code is the signal**: `finalize` exits `0` (ok), `1` (failed), or `75` (still running) — re-issue the bounded `finalize` tool call while it returns `75` (a `$?`-based retry across tool calls, never a shell `while` in one
  > 600s call). Duration is never judged: a long unit is never a reason to split it. The orchestrator's own tool calls stay foreground; the model still never backgrounds its own tool calls. This applies in every Codex-driving skill (`executor-prex`, `review-loop`, `plan-multi`, `ask`); runtime behavior is owned by `cog codex-runner`, and the durable-job contract is recorded in `docs/decisions/0009-orchestration-and-durable-jobs.md`.
- **Use the `Agent` tool, never the `Skill` tool, for nested delegation** — `Skill` inline-injects the child body and the orchestrator stops mid-workflow (`anthropics/claude-code#17351`). Nesting being supported does not change this: the Agent tool is still the boundary. See `../skills-and-orchestration.md` (Dispatch vs Delegation).

The current guarantee is env-first: `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` is asserted before orchestration work that depends on foreground execution. Multi-level completion stays independently backstopped by durable postcondition checks such as queue status, scan/verify artifacts, and parsed commit result lines.

## Status

Accepted / Implemented (2026-06-17). Current queue orchestration uses `runner-all`, `runner-plan`, `claude-delegate`, and executor skills. Recorded in-repo as [ADR-0009](../../docs/decisions/0009-orchestration-and-durable-jobs.md).
