# ADR-0022: cog-owned durable long-running jobs

## Context and Problem Statement

ADR-0010 assumed long Bash timeouts (`BASH_*_TIMEOUT_MS=600000`) keep a long Codex call inside the
foreground window. Claude Code's Bash tool actually enforces a hard ~600s ceiling that no env var
raises (anthropics/claude-code #34138, #25881), and the timeout SIGTERMs the whole foreground process
tree (#45717), orphaning Codex and losing its exit report. A coding agent must run as long as it
needs; duration is never a failure or quality signal.

## Considered Options

- Keep synchronous foreground Codex calls and "split the round" when a stage exceeds 600s.
- Background Codex ad hoc with `&` / `run_in_background`.
- Make `cog` own the process: launch it detached in its own session, poll a durable state file.

## Decision Outcome

Chosen option: **cog owns long runs as durable jobs**. `cog longrun` and `cog codex-runner run-exec`
launch the process via `setsid` (its own session / process group), so a Bash-tool tree-SIGTERM cannot
reach it, and write an atomically-updated JSON state file. The job's result lives in one verb,
`finalize`: it polls the durable state up to `--max-wall` seconds (default 0 = instant) and then
classifies the outcome from durable artifacts, so a killed observer loses nothing. Generic supervision
lives in `cog::fn::longrun::*`; `codex-runner` supplies the Codex argv and reuses the existing status
classifier.

This is orthogonal to `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`, which governs the Claude harness
auto-backgrounding its own tool calls and subagents. cog detaching its own child is not the model
backgrounding a tool call; that agency distinction is what `cog skill-lint` enforces. Foreground
discipline still applies to Agent-tool subagent delegation. Durable jobs cost zero subagent depth.

### Golden rules

- **GR1** — A coding agent runs as long as it needs. Duration is never a failure or quality signal.
- **GR2** — Every `codex-session` run is a durable job (always detached + durable state).
- **GR3** — Long-process supervision is generic; any one-off command wraps into the same protocol via
  `cog longrun`.
- **GR4** — The exit code is the signal. `finalize` reports its outcome through its process exit code;
  the caller branches on `$?` and reads the JSON body only for details. The contract is identical for
  `cog longrun` and `cog codex-runner` — one pattern, no per-command special cases.

### Result contract (GR4)

| exit | meaning | caller action |
| --- | --- | --- |
| `0` | terminal & ok | done — read body for details (thread_id, account) |
| `1` | terminal & not ok (failed / cancelled / unrecoverable lost) | done, failed — read body/stderr for why |
| `75` (`EX_TEMPFAIL`) | still running (max-wall elapsed, or instant call on a live job) | poll again |
| `64`/`66`/`70` (`EX_*`) | cog-level error (bad flags, missing `--state`, internal) | abort — a tool error, not a job outcome |

`finalize` never classifies a still-`running` job (its events file is mid-write) and never hard-errors
on one — it emits the running snapshot and exits `75`. The ~600s Bash ceiling forbids burying the poll
loop in a single blocking call, so the **orchestrator owns the repetition**: it re-issues the bounded
`finalize --max-wall` Bash tool call while it sees `75`. cog owns all the logic; the loop is a trivial
`$?`-based retry across tool calls, never a shell `while` inside one >600s invocation.

## Consequences

- Good: agent runtime is never time-gated; long Codex runs survive the 600s ceiling and keep durable reports.
- Good: monitoring is deterministic and DRY; any one-off command wraps into the same protocol.
- Bad: callers launch then re-issue a bounded `finalize` until it stops returning 75, instead of
  issuing one blocking call.

## Status

Accepted. Supersedes the long-Bash-timeout-keeps-Codex-foreground claim in
[ADR-0010](0010-orchestration-env-first.md) and
[foreground orchestration](../explanation/foreground-orchestration.md); keeps the env-first
no-backgrounding guarantee and depth model otherwise intact. Implemented by
`lib/functions/fn_longrun.sh`, `lib/commands/cmd_longrun.sh`, the `cog codex-runner`
`run-exec`/`run-resume`/`status`/`finalize`/`cancel` surface, and the `skill-lint`
`orchestration-background-codex` durable-job whitelist.
