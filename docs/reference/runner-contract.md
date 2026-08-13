# Runner contract

What a provider runner must do to be dispatchable. A runner is the component that turns one fresh-context step into one running agent and one set of durable artifacts: `cog codex-runner` today, `cog claude-runner` next. This is the vendor-neutral contract slice 006 builds both against.

Three contracts sit near each other and own different things. [Orchestrator contract](./orchestrator-contract.md) owns what a driver of `cog workflow` owes the engine. [Orchestration contract](./orchestration-contract.md) owns how cog's skills and agents compose Claude, Codex, queues, and subagents, and it owns the durable-job rules this page builds on. This page owns the provider boundary: what every runner normalizes, and what it deliberately leaves provider-shaped.

Parts of this contract are specified ahead of the runtime. Each is marked where it appears.

## What a runner is

A runner is a launcher, not a supervisor. It builds one argument vector, hands it to the durable-job engine, and returns. [ADR-0009](../decisions/ADR-0009-orchestration-and-durable-jobs.md) owns why: the process runs detached in its own session and process group, so the Bash tool's tree-SIGTERM cannot reach it, and the outcome is reconstructed from files rather than from an observer that may not survive.

A runner therefore owns exactly three things: the argument vector, the precondition report, and the artifact paths. It owns no credential, no model policy, no scheduling, and no interpretation of what the agent produced.

## Conformance fields

Ten fields. A runner is conformant when it supplies all ten and normalizes the ones marked as normalized; a field marked provider-owned is named here so a reader knows it exists, not standardized.

| Field               | Conformance requires                                                     | Normalized |
| ------------------- | ------------------------------------------------------------------------ | ---------- |
| Launch argv         | One vector built by cog, never a shell string a caller can extend        | No         |
| Durable state file  | One `cog.longrun.v1` document at a caller-named absolute path            | Yes        |
| Output artifact     | The agent's final message, as one file                                   | Yes        |
| Event stream        | The provider's own structured stream, captured whole                     | Yes        |
| Stderr capture      | A separate file; never merged into the event stream                      | Yes        |
| Exit classification | `0` done and ok, `1` done and failed, `75` still running                 | Yes        |
| Effort selection    | One rung of the provider's fixed ladder, resolved from the engine record | No         |
| Access posture      | Declared per launch and defaulting closed                                | Yes        |
| Account selection   | Named by the caller; the runner selects, never creates or rotates        | No         |
| Resume identity     | A durable handle that names the same conversation on a later call        | No         |

The five normalized fields are the ones a workflow driver reads. The five provider-owned fields are where the two CLIs genuinely differ, and normalizing them would mean inventing a shape neither provider has.

## Durable artifacts

The state file is `cog.longrun.v1`, which already carries every artifact path under one `artifacts` object: `stdout`, `stderr`, `output`, `exit_code_file`, and `done_marker`. A runner adds no schema of its own. Its provider-specific facts go in `engine` and `engine_meta`, which exist for exactly that.

Every artifact path is absolute. A relative path is resolved against the process's working directory, and a detached job's working directory is not the caller's to assume; `codex-runner` already enforces this as `codex-runner-abs-artifact-path` and every runner inherits the rule. Scratch lives under `cog rundir <prefix>`.

Artifacts are written by the job, never by the runner after the fact. The runner does not copy, rename, summarize, or truncate them, because a file the runner rewrote is a file whose contents no longer prove what the agent did.

## Classification

`finalize` is the only verb that classifies. It polls up to `--max-wall`, then decides from the exit-code file, the done marker, and the captured streams: `0` done and ok, `1` done and failed, `75` still running. A still-running job is never an error, and the orchestrator owns the repetition — it re-issues the bounded call while it sees `75`, which is the same `$?`-based retry the workflow engine's own `75` uses.

The durable lifecycle states are `running`, `exited`, `finalized-ok`, `finalized-failed`, `cancelled`, and `lost`. `lost` is reconstruction after a reboot or a vanished process group, not a timeout: duration is never a failure signal.

Beyond that, a runner may report a provider-shaped status of its own — `codex-runner explain-status` is the existing example — and those statuses are diagnostics, never a second classification. A caller branches on the exit code.

## Preconditions

A runner reports version and authentication preconditions and manages neither. [ADR-0031](../decisions/ADR-0031-preflight-provider-preconditions-before-the-durable-job.md) settles when: before the durable state file exists. Once a job exists its status belongs to the agent, so a precondition that would have failed the launch must be caught while the runner is still the thing answering.

Reportable preconditions are the standing ones a retry reproduces: the provider CLI is missing or not executable, no account is bound or selected, a required profile does not resolve, the underlying binary is below a version floor the provider enforces, or a credential is absent or refused. Each is reported with what was checked and what would satisfy it, and none is fixed by cog. Creating, storing, rotating, and selecting credentials are out of scope for every runner.

Specified, not yet implemented: no runner performs a preflight today. `codex-runner` gaining one is the conformance retrofit slice 006 owns.

## Two asymmetries

The providers are not shaped alike, and the contract absorbs the difference rather than assuming it away. Both were measured against `claude` 2.1.220 and `claude-session-rs` on 2026-08-13.

Claude has no exec verb. `codex-session` owns `exec`, so a Codex launch is a subcommand. The Claude wrapper owns no such verb: a headless run is a passthrough, and every token after the wrapper's own flags reaches `claude` verbatim. The runner therefore builds a wrapper prefix and a child suffix rather than one subcommand, and the contract requires a vector, not a verb.

Claude requires a bound account and a resolved profile before any launch. `codex-runner` has no profile concept at all. Account and profile resolution is a provider-owned step this contract names as a precondition and does not standardize: a runner reports that the binding is missing, and the shape of the binding stays the provider's.

One consequence of the first asymmetry is why [ADR-0031](../decisions/ADR-0031-preflight-provider-preconditions-before-the-durable-job.md) exists. The Claude wrapper execs the child rather than supervising it, so it leaves no post-flight and its own exit codes overlap the agent's: 64 is both `EX_USAGE` and a legal agent status. Preflight is what keeps "never launched" distinguishable from "ran and failed" without parsing provider prose.

## Provider mapping

Recorded so a reader can see the contract is written from two real CLIs. This is a snapshot of what each provider spells today, not a normalization: the left column is what `codex-runner` builds now, and the right is what `claude-runner` will build.

| Concept           | `codex-runner`                  | `claude-runner`                                            |
| ----------------- | ------------------------------- | ---------------------------------------------------------- |
| Launch            | `codex-session … exec`          | `claude-session-rs --account <a> --profile <p> -- -p`      |
| Effort            | `-c model_reasoning_effort=<e>` | `--effort <level>`, plus `--model` from the engine record  |
| Read-only posture | `--sandbox read-only`           | `--permission-mode`                                        |
| Write posture     | `--sandbox danger`              | `--dangerously-skip-permissions`                           |
| Event stream      | `--json` on stdout              | `--output-format stream-json --verbose` on stdout          |
| Final message     | `--output-last-message <file>`  | the final envelope's `.result`, extracted into the file    |
| Resume            | `exec resume <thread-id>`       | `--resume <session-id>`, pinned with `--session-id <uuid>` |
| Identity capture  | `thread-index.jsonl`            | the session id, read from the event stream                 |

Two mapping facts are measured rather than inferred, and both are the kind that a provider release can invalidate:

The `none` rung is an omission, not a value. `claude --effort none` is rejected with a warning and the default effort is used, so the registry's `claude-haiku-4.5-none` row is dispatched by passing no `--effort` flag at all. A runner that forwarded the rung name verbatim would silently run at a different effort than the engine record names.

The final message needs extracting on the Claude side. Codex writes it to a named file directly; Claude emits it inside the stream, so the runner reads the final envelope's `.result` and writes the output artifact itself. That is the one place a runner produces an artifact rather than letting the job write it, and it is why the output artifact is a conformance field rather than a provider detail.

## Registry coupling

Membership in `data/workflow-engines/` is the permission to dispatch, and the fifth registry invariant is that a row's provider declares a runner. Declaring one is not the same as having one: `data/workflow-engines/meta.yaml` carries a `runner_status` per provider, either `available` or `planned`. `codex` is `available` and `claude` is `planned`.

That field is the honest reason `claude` rows validate today while only `codex` can be dispatched. Slice 006 flipping `claude` to `available` is the change that makes those rows live, and nothing should flip it before a runner satisfies this page.

Specified, not yet enforced: `runner_status` is read by no code. The validator checks only that a runner name is declared.

## What is not normalized

Provider diagnostics are preserved rather than translated. A runner does not map a provider's own error taxonomy into cog's, does not rewrite its stderr, and does not summarize its event stream. Everything the provider said stays readable in the artifacts under its own vocabulary, and the normalized fields above are what a caller branches on.

The reason is the rabbit hole slice 006 names: two provider CLIs will keep diverging in lifecycle semantics, and a translation layer over that divergence is a layer that has to be corrected on every provider release. Normalizing ten fields and preserving the rest is the smaller standing obligation.
