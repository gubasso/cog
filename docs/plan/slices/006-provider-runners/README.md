# 006 — Provider runners

## Goal

Claude and Codex fresh-context steps satisfy one runner contract and preserve durable artifacts.

## Appetite

3 implementation sessions. Chosen before the design below.

## Core

Both providers dispatch one fresh-context leaf through the conformance contract, leaving convenience diagnostics as remainder.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Add `claude-runner` alongside the existing `codex-runner` contract.
- Report version and authentication preconditions without managing credentials.
- Preserve absolute durable state, output, events, and stderr artifacts.
- Add provider parity and recovery tests. Optional human formatting is cut first.

## Out of scope

- Credential creation, storage, rotation, or provider account selection.
- A third provider or provider-specific workflow grammar.

## Governed by

- `docs/plan/slices/005-orchestrator-conformance/README.md` — vendor-neutral runner contract.
- `docs/decisions/ADR-0009-orchestration-and-durable-jobs.md` — durable job rules.
- `docs/explanation/orchestration.md` — current provider boundary.
- `docs/reference/orchestration-contract.md` — exact runner receipts.

## Acceptance

```text
When Claude or Codex dispatches a fresh-context leaf, each runner shall satisfy the same durable artifact contract. -> test/integration/cmd_provider_runners.bats
If a version or authentication precondition is absent, then the runner shall report it without managing credentials. -> test/integration/cmd_provider_runners.bats
```

## Rabbit holes

- Provider CLIs can diverge in lifecycle semantics — escape: normalize only the conformance fields and preserve provider diagnostics.
- Authentication work can expand scope — escape: stop at precondition reporting.

## Done when

Both provider paths pass the same named contract and milestone 006 flips to `done`.

## Revisions

Scope gains a retrofit: `In scope` said "add `claude-runner` alongside the existing `codex-runner` contract", which read as though the existing runner already conformed. It does not — the contract is being written now, and `codex-runner` has no preflight and no conformance-field self-check. Both runners are built against `docs/reference/runner-contract.md`, so the work is one new runner plus a conformance retrofit of the existing one. What changed it is that a contract derived from one implementation plus a hypothesis is a description of the implementation; deriving it from two forced the asymmetries below into the open.

Prose ahead of code: the contract landed as `docs/reference/runner-contract.md` while the workflow engine is under a code freeze, so neither runner and no `test/integration/cmd_provider_runners.bats` exists. The slice stays `shaped`. Nothing was cut.

Three findings the contract absorbs, each measured against `claude` 2.1.220 and `claude-session-rs` on 2026-08-13 rather than read from documentation. First, `claude-session` owns no exec verb: a headless run is a verbatim passthrough to `claude -p`, so a runner builds a wrapper prefix and a child suffix rather than a subcommand. Second, it requires a bound account and a resolved profile before any launch, which `codex-runner` has no concept of; account and profile resolution is named as a precondition and left provider-owned. Third, `claude --effort none` is rejected with a warning and the default effort is used, so the registry's `claude-haiku-4.5-none` row is dispatched by omitting the flag — a runner forwarding the rung name verbatim would run at a different effort than the engine record names.

One decision came out of the first finding. The Claude wrapper execs the child, leaving no post-flight and an exit range that overlaps the agent's, so classification from artifacts alone cannot tell "never launched" from "ran and failed". [ADR-0031](../../../decisions/ADR-0031-preflight-provider-preconditions-before-the-durable-job.md) resolves it by checking preconditions before the durable state file exists, which is also how this slice's second `Acceptance` line is satisfied without managing credentials.
