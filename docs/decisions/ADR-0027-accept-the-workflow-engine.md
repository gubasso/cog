# ADR-0027: Accept the workflow engine

## Context and Problem Statement

Slice 002 held a moratorium on workflow-engine code until one record accepted or rejected the proposal and fixed its grammar and invocation boundary. Q-001 through Q-004 have now all exited, and the contract they blocked is materially narrower than the one first proposed: engines are literals set at a definition or its direct call site, artifacts pass by directory, exclusion is expressed with `needs:`, and loop convergence is judged rather than computed.

## Considered Options

- Reject the proposal and cut slices 003 through 009
- Accept the proposal as originally shaped
- Accept the narrowed contract

## Decision Outcome

Chosen option: `Accept the narrowed contract`. A workflow is a directed acyclic graph of steps; a step is exactly one of three call forms; `needs:` is the only edge key. A unit whose repetition count is unknown until something runs is an ordinary leaf whose skill prose owns its internal loop, so it carries a required `engine:` like any other step definition. The durable contract lives in [workflow contract](../reference/workflow-contract.md), and its design rationale in this record and the question records it closes.

## Consequences

- Slices 003 through 009 are unblocked, and the charter no-go on activating implementation before this record is satisfied.
- Q-002 exits here. The grammar already admitted exactly one legal shape for a queue-draining unit, and that shape needs no new key.
- The engine seed is accepted against a power-grade matrix whose revalidation window is open, and it is registered for tracking so it is re-checked rather than assumed.
- Nothing is enacted yet. This record fixes a contract; the first code lands in slice 003.

## Status

Accepted
