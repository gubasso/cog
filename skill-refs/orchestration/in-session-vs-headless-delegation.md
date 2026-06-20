# In-session subagent delegation vs headless `claude -p`

Decision record + canon for how orchestrating skills run a fresh, full Claude execution (a delegated
unit of work that may itself spawn subagents — e.g. `/executor-prex`, which delegates plan review, code
review, and a review loop).

## Decision

Run delegated agentic work as **in-session foreground subagents**, not via a headless `claude -p`
subprocess. A generic `claude-delegate` subagent is the reusable primitive; orchestrators (e.g.
`plan-queue-runner`) dispatch each unit to it via the **Agent tool**.

## Why headless `claude -p` was wrong

Headless / print mode has **no event loop after the model's final turn**. Per the official docs, a
background Bash task started during a `claude -p` run is **terminated ~5 s after Claude returns its
final result**. So an orchestrated round that backgrounded its long Codex call (rationalizing "I'll
be re-invoked when it completes") had the detached Codex **reaped before later stages ran** — work
landed partially, review stages never ran, the unit silently stayed incomplete, and the process
still exited `0`. A prose "never background" mandate is advisory and was overridden on large units.

The `claude -p` host existed only because subagents historically could not spawn subagents, and a
unit like `/executor-prex` must delegate internally. That constraint is gone.

## What changed

Claude Code **v2.1.172** (2026-06-10) added **nested subagents**:

- A subagent can spawn its own subagents. **Foreground subagents can spawn at any depth** — each
  level blocks its parent until it returns, so the chain is self-limiting (the main conversation
  waits on the whole chain). Background subagents are capped at depth 5.
- A subagent **inherits all tools when `tools` is omitted** (so it gets `Agent` + `Skill` and can
  both run skills and nest). The full CLAUDE.md / memory hierarchy loads at every level.
- A subagent **inherits the parent's permission mode** (`bypassPermissions` propagates), so
  unattended privilege is preserved with no per-process flags.

See <https://code.claude.com/docs/en/sub-agents> ("Spawn nested subagents") and
<https://code.claude.com/docs/en/headless> ("Background tasks at exit").

## Considered options

1. **Headless `claude -p` + prose mandate** — rejected: no post-turn event loop; backgrounded Codex
   reaped; mandate advisory.
2. **Headless `claude -p` + a deterministic `PreToolUse` hook denying backgrounded Codex calls** —
   viable, but adds a hook and keeps the fragile per-round process host. Deferred.
3. **In-session foreground subagents** — chosen.

## Consequences

- Good: synchronous blocking; shared live event loop (background tasks owned by the long-lived
  parent, not reaped per unit); no per-round process spawn; native nesting; a single uniform
  delegation primitive; inherited permission mode.
- Bad: the orchestrating session must stay alive for the whole run; we rely on foreground discipline
  rather than a hard hook.

## The standing rules (unchanged, and why)

- **Never background a Codex `exec`/`resume`**, regardless of host (headless **or**
  in-session/forked subagent). Run it in the foreground (`run_in_background` false/omitted, Bash
  timeout `600000ms`, blocks until exit). Backgrounding breaks synchronous result classification and
  risks reaping. A unit that cannot finish in the foreground budget is a planning error (split it),
  never a reason to detach. This rule lives inline in every Codex-driving skill (`executor-prex`,
  `review-loop`, `plan-writer-multi`, `ask`); the runtime behavior is owned by `cog codex-runner`,
  and the maintenance-time canon is `docs/reference/codex-conventions.md` (a maintenance-only doc,
  not a runtime-loaded reference).
- **Use the `Agent` tool, never the `Skill` tool, for nested delegation** — `Skill` inline-injects
  the child body and the orchestrator stops mid-workflow (`anthropics/claude-code#17351`). Nesting
  being supported does not change this: the Agent tool is still the boundary. See
  `../skills-and-orchestration.md` (Dispatch vs Delegation).

We initially shipped this as prose-only (architecture-only), reasoning that foreground blocking plus
the orchestrator's deterministic completion check (re-reading `QUEUE.yaml` for `status == done`)
made the reaping failure unlikely. That proved insufficient: under in-session delegation a delegate
can still background its **own** Codex Bash call one level down and end its turn, getting the child
SIGTERM-reaped (observed 2026-06-17, `plan-queue-runner` → `claude-delegate` → `executor-prex` stage 3). The
"option-2" guard is now **implemented** as a `PreToolUse(Bash)` hook —
`agent-helper hook-guard codex-foreground` — which fires inside subagents too (confirmed: PreToolUse
runs for subagent tool calls, carrying `agent_id`) and blocks any Codex call that is backgrounded or
declares a Bash timeout below `600000ms` (the default ~120000ms also SIGTERMs Codex mid-run). Prose
remains the rationale; the hook is the guarantee. Multi-level completion stays independently
backstopped by the QUEUE-status check. The lock dir is a single source of truth (`rundir_lock_dir`)
shared by the producer and the now-thin Stop-gate hook, so the two can no longer diverge.

## Status

Accepted / Implemented (2026-06-17). Enacted in dotfiles by
`claude/.claude/agents/claude-delegate.md`, `claude/.claude/skills/plan-queue-runner/SKILL.md`, and
`claude/.claude/skills/executor-prex/SKILL.md`. Mirrored as ADR-0001 in the dotfiles and `cog` repos.
