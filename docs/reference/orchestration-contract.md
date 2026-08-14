# Orchestration Contract

This reference defines how `cog` skills and agents compose Claude, Codex, workflows, and subagents. Skills keep sequencing and judgment in prose; deterministic checks and workflow mechanics stay in `cog`.

## Recursion Primitives

| Primitive                            | Runtime shape                                            | Depth cost                | Contract                                                                                            |
| ------------------------------------ | -------------------------------------------------------- | ------------------------- | --------------------------------------------------------------------------------------------------- |
| Skill-inline                         | Same context window                                      | 0                         | Use for same-context chaining when no isolation boundary is needed.                                 |
| Agent-delegate / foreground subagent | Own context; parent blocks until the chain returns       | 1 subagent level          | Use at true isolation boundaries. Hard cap is 5 levels.                                             |
| Workflow                             | Background parallel fan-out                              | Not synchronous recursion | Use for independent parallel work, not call-stack style orchestration.                              |
| Headless `claude -p`                 | Separate process without the live interactive event loop | Avoid                     | Abandoned for recursive orchestration because backgrounded work can be reaped after the final turn. |

The `Workflow` row above means background parallel fan-out. It is a harness primitive, not a cog surface — cog ships no workflow engine.

## Environment Requirements

The primary no-backgrounding lever is:

```text
CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
```

This disables background-task functionality, including Bash and subagent `run_in_background`, auto-backgrounding, and Ctrl+B. It keeps subagent spawns synchronous.

This env var governs the Claude harness — its auto-backgrounding of tool calls and subagents. It does not extend how long a single Bash call may run. The Bash tool enforces a hard ceiling of about 600s that no environment variable raises (`BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS` are non-functional in many versions), and when that ceiling fires it SIGTERMs the whole foreground process tree. A genuinely long external command therefore cannot be a single foreground Bash call — it runs as a cog-owned durable job (see below).

`claude-session` configuration is the source of truth for env and hook registration. `cog` asserts the observed runtime state fail-closed before orchestration work that depends on this contract.

## Durable Long-Running Jobs

A coding agent runs for as long as it needs; duration is never a failure or quality signal. `cog` owns long-running processes instead of the Bash tool: `cog longrun` and `cog codex-runner run-exec` launch the process detached in its own session/process group (via `setsid`), so the Bash-tool tree-SIGTERM cannot reach it, and record an atomically-updated JSON state file. The result lives in one verb, `cog … finalize --max-wall <secs>`: it polls up to `--max-wall` then classifies the outcome purely from durable artifacts (exit-code file, done-marker, captured stdout/stderr), so an observer killed at the ceiling loses nothing.

The exit code is the signal. `finalize` exits `0` (done, ok), `1` (done, failed), or `75` (`EX_TEMPFAIL` — still running) — the caller branches on `$?` and reads the JSON body only for details. A still-`running` job is never classified and never an error; finalize emits its snapshot and exits `75`. Because the ~600s ceiling forbids one blocking call, the orchestrator owns the repetition: it re-issues the bounded `finalize --max-wall` tool call while it sees `75`. That is a trivial `$?`-based retry across tool calls, never a shell `while` inside one >600s invocation. The contract is identical for `cog longrun` and `cog codex-runner`.

Access is declared per launch and defaults closed. `run-exec --access write` is admitted only by `--mode danger`; every other mode is read-only. `run-resume` takes the same `--access` flag and also defaults to `read-only`, because a resume inherits no sandbox from the thread it resumes: `codex exec resume` accepts no `--sandbox` flag, so cog expresses read-only through the `sandbox_mode` config override and reserves `--dangerously-bypass-approvals-and-sandbox` for `--access write`. `finalize` reports the access the round actually ran under, so a caller can prove a read-only reviewer stayed read-only rather than trusting prompt wording.

This is the only sanctioned form of non-blocking execution. cog detaching its own child is not the model backgrounding its own tool call; ad-hoc shell backgrounding (`&`, `run_in_background: true`) on Codex or orchestration work stays prohibited, and `cog skill-lint` enforces the distinction. Every `codex-session` run is a durable job. See [ADR-0009](../decisions/ADR-0009-orchestration-and-durable-jobs.md).

## Delegate And Verify

Every orchestration boundary must verify a durable postcondition after the delegate returns. A parent must re-read state such as a report file, a run-directory artifact, or a test result rather than trusting a returned summary.

An orchestrator may invoke a review subagent as a foreground sibling boundary after a committed unit. The review subagent is a sibling of the work delegate (a +1 from the orchestrator's depth 0), not nested beneath it, so the boundary stays flat against the depth cap; it spends one depth level and must verify a clean, committed postcondition before selecting more work.

## Depth Budget

Claude Code permits a fixed maximum of five subagent levels below the main conversation. The limit applies regardless of whether each level is foreground or background. A subagent at depth five does not receive the Agent tool and cannot spawn further; the limit is fixed and not configurable.

Spend depth only when isolation is valuable. Chain skills inline when same-context composition is enough. When a design would exceed depth five, flatten it into durable iteration: persist the next unit of work, return to the parent, and start a fresh foreground chain from that durable state.

Cog-owned durable jobs (above) are processes cog supervises, not Agent-tool subagents, so they cost zero subagent levels: the polling orchestrator stays at its current depth regardless of how long the job runs.

## External References

- <https://code.claude.com/docs/en/tools-reference>
- <https://code.claude.com/docs/en/env-vars>
- <https://code.claude.com/docs/en/sub-agents>
- <https://code.claude.com/docs/en/changelog>
- <https://code.claude.com/docs/en/hooks>
- <https://code.claude.com/docs/en/hooks-guide>
- <https://code.claude.com/docs/en/interactive-mode>
- <https://code.claude.com/docs/en/workflows>
- <https://developers.openai.com/codex/cli/reference>
