# Orchestrator contract

What a driver of `cog workflow` must be, must do, and must not do. An orchestrator here is any program that drives a workflow run to a terminal state — a Claude session, a Codex session, a CI job, or a shell script. This page is the conformance target slice 006's provider runners are written against.

Two neighbours own what this page deliberately does not. [Workflow contract](./workflow-contract.md) owns the grammar, the engine registry, and the validator rules. [CLI commands](./cli-commands.md) owns the verb grammar and the `0`/`1`/`2`/`75` exit protocol. [Orchestration contract](./orchestration-contract.md) is a different document about a different thing: how cog's own skills and agents compose Claude, Codex, queues, and subagents. Nothing on this page requires that one.

Parts of this contract are specified ahead of the runtime. Each is marked where it appears.

## Declaration

An orchestrator declares itself once, at `resolve`, through `--orchestrator <json>`:

```json
{"name": "claude-runner", "version": "1", "capabilities": ["inline", "subprocess", "ask-user"]}
```

`name` and `version` identify the driver in run state and in a conformance readout. `capabilities` is a set drawn from the closed vocabulary below; an unknown member is `InvalidInput`.

cog enforces rather than trusts. A capability the orchestrator did not declare is a capability cog refuses to exercise, so a driver that under-declares gets a run it can honor, and a driver that over-declares fails at the first directive it cannot honor rather than silently degrading. Declaration is not a hint to be second-guessed at dispatch time.

Specified, not yet enforced: `resolve` today accepts any JSON object and stores it verbatim. No verb reads `capabilities`.

## The capability vocabulary

Four members. Each row states the consequence of the capability being absent, because absence is the safe default and the thing a conformant driver must survive.

| Capability   | Absent ⇒                                               |
| ------------ | ------------------------------------------------------ |
| `parallel`   | `next` returns at most one dispatch directive          |
| `inline`     | a `context: inherit` node fails closed                 |
| `ask-user`   | a `requires_judgment` directive becomes a hard failure |
| `subprocess` | only `context: inherit` nodes are dispatchable         |

`next` already returns at most one node, so `parallel`'s absent-behavior is today's behavior for every driver. The capability is declared now so that widening the frontier later is not a contract change.

`inline` and `subprocess` range over the `context:` key on a node, owned by [workflow contract](./workflow-contract.md#execution-context) and decided by [ADR-0030](../decisions/ADR-0030-select-a-step-context-at-its-node.md). They are independent: a driver that can only fork declares `subprocess` alone and gets a run in which every `inherit` node fails closed rather than being quietly forked, and a driver that can only run in session declares `inline` alone. A driver that declares both may be handed a definition mixing the two.

`requires_judgment` is a directive cog emits, not a field an orchestrator invents. A `next` or `advance` body may carry it, with a reason, when the run cannot proceed without a human. Today the accepted grammar produces exactly one such case: a loop's `until:` criterion, which [ADR-0026](../decisions/ADR-0026-judge-loop-convergence-with-a-prose-criterion.md) makes a prose judgment cog stores and never parses, reaching `advance` as the `needs-user` reason already in its closed reason set. A driver holding `ask-user` surfaces the directive to a person; a driver without it stops.

Specified, not yet emitted: no verb writes a `requires_judgment` directive today. Grepping for it in `lib/` finds only an unrelated classification field in `cog gc`.

## Driver obligations

A conformant orchestrator must:

- run a shell command and read its stdout and its exit code;
- parse JSON;
- declare itself once, at `resolve`;
- drive `next` → `claim` → dispatch → `record` while the run is active, re-issuing on `75`;
- dispatch by any means it has — a subagent, a subprocess, an API call, or its own context;
- pass the claim token on `record` and the decision token on `advance`;
- hand each node the upstream directories cog names for it in `node.inputs`, rather than any path it derived itself;
- read a loop's `until:` criterion and the round's directories, then report its own judgment on `advance`;
- reconcile every durable `running` claim after a restart, before selecting new work;
- surface a `requires_judgment` directive to a human, or abort;
- stop on a terminal state.

## Driver prohibitions

It must not:

- edit `state.json` or `workflow.json`;
- write any `outputs.json` — `record` is the only writer;
- synthesize ids, handles, tokens, or counters;
- infer a round count, rather than reading the one cog reports;
- re-dispatch a `running` node without `reclaim`;
- treat any terminal state but `done` as success.

The prohibitions are what make single-writer discipline hold. A driver that edits state directly is not a slower conformant driver; it is a driver whose run cannot be recovered after a crash, because the durable record no longer describes what happened.

## What is explicitly not required

Subagents. A depth budget. Parallelism. Streaming. A tool-call protocol. Plan mode. MCP. A model, a provider, or an account.

This list is load-bearing rather than reassuring: it is the whole of what makes the contract vendor-neutral, and it is why a shell script that shells out to `cog workflow` and dispatches with `bash` is a conformant orchestrator. Anything added to the obligations above that a shell script cannot satisfy is a contract regression.

## Depth

`max-fresh-depth` is an opt-in contract, not a vendor base number.

Absent, cog enforces no depth ceiling and the orchestrator owns whatever limit its own runtime has. Present on `resolve`, it is the orchestrator's declared ceiling, and cog refuses a dispatch that would exceed it rather than letting the failure land at depth after real spend.

Claude Code's own fixed five-level subagent limit is a vendor fact owned by [orchestration contract](./orchestration-contract.md#depth-budget). It is not this contract's number and must not be restated here: a driver with no subagents has no such ceiling, and a driver with a different one declares it.

Specified, not yet enforced: `resolve` parses and stores `--max-fresh-depth` and nothing consults it.

## Terminal states

Terminal states live in the JSON `state` field, never in the exit code. The exit protocol is protocol only — `0` a valid result or an applied transition, `1` an internal state failure, `2` `InvalidInput`, `75` cannot advance yet — and [CLI commands](./cli-commands.md) owns it.

Only `done` is success. A driver that branches on the exit code alone will read a terminal `failed` run as a healthy one, because reporting that terminal state correctly is itself a `0`.
