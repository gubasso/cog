# ADR-0033: Bind the approval gate to one artifact

## Context and Problem Statement

`cog gate` asks the operator for a `--round-id` and a `--round-path`, and its contract defines the gate as a queue round the executor flips to `done`. [ADR-0032](./ADR-0032-remove-the-plan-vault-and-the-round-layer.md) removed the round layer, so nothing produces a round, reads one, or knows whether one is done. The gate still works — it hashes whatever file it is handed — but it names a concept the system no longer has, in the one place a human types a command.

## Considered Options

- Rename the gate onto the artifact it already binds.
- Keep the round vocabulary as a historical alias.
- Retire the gate with the layer that named it.

## Decision Outcome

Chosen option: `rename the gate onto the artifact it already binds` — the mechanism is sound and still needed at every executor terminus, and the flags are what an operator reads, so a stale alias costs more than the rename.

## Consequences

- Good: the gate reads as what it is, and its record names the artifact under approval.
- Good: nothing outside a loop that counts its own rounds uses the word.
- Bad: `--round-id` and `--round-path` break; a caller passing them fails closed on an unknown option.
- Bad: approval records written before the rename no longer match the current key set.

## Status

Implemented

Enacted by [slice 011](../plan/slices/011-approval-gate-artifact-binding/README.md) and [`cmd_gate.sh`](../../lib/commands/cmd_gate.sh).

Amends [ADR-0022](./ADR-0022-forge-resistant-approval.md) — the approval binds an artifact rather than a round; the hash, the expiry, and the forge resistance are unchanged.
