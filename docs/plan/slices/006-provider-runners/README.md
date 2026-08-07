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

None.
