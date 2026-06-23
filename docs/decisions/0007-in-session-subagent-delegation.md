# ADR-0007: In-session subagent delegation over headless `claude -p`

## Context and Problem Statement

cog's orchestration skills (`runner-all`, `runner-plan`, and the historical `prex`) drive multi-step
agentic work. The dotfiles ancestor drove each unit by shelling out to a headless `claude -p` process
running `/prex`. Headless mode has no event loop after the model's final turn: a backgrounded
Bash/Codex task is killed ~5 s after the result. So a unit that backgrounded its long Codex
implementation was reaped before its later review stages ran — it silently stayed incomplete while
the process exited `0`. The `claude -p` host existed only because subagents historically could not
nest, and `/prex` must delegate internally (plan review, code review, review loop).

## Considered Options

- Headless `claude -p` + a prose "never background" mandate — advisory only; overridden on large
  units.
- Headless `claude -p` + a deterministic PreToolUse hook denying backgrounded Codex calls — works,
  but adds a hook and keeps the fragile per-unit process host.
- In-session foreground subagents — Claude Code ≥ v2.1.172 supports nested subagents; foreground
  calls block the parent until the whole chain returns.

## Decision Outcome

Chosen: **in-session foreground subagents**. A generic `claude-delegate` subagent is the reusable
primitive; orchestrators dispatch each unit (and the `/gc` commit) to it via the Agent tool. Unit
completion is verified deterministically (e.g. re-reading `queue-rounds.yaml` for `status == done`). We
deliberately did **not** add the backgrounding hook (architecture-only); the "never background a
Codex call" rule stays inline in every Codex-driving skill as the prose safeguard.

## Consequences

- Good: synchronous blocking; shared live event loop; no per-unit process; native nesting; one
  uniform delegation primitive; inherited permission mode for unattended runs.
- Bad: the orchestrating session must stay alive for the run; relies on foreground discipline rather
  than a hard hook. If a fully-detached headless-orchestrator use re-emerges, revisit the hook.

## Status

Accepted. Hook stance amended by ADR-0010 (env-first guarantee). Ported from dotfiles ADR-0001.
Queue filename terminology amended by ADR-0011 (decisions/0011-directory-plan-queue-format.md).
Runner dispatch semantics are amended by ADR-0030 (runner verbatim queue dispatch).
Canon: `skill-refs/orchestration/in-session-vs-headless-delegation.md`.
