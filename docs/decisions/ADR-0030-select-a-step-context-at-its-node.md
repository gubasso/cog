# ADR-0030: Select a step's execution context at its node

## Context and Problem Statement

`workflow/meta.yaml` carries `context:` as one of three closed workspace defaults, and no node may set it. [ADR-0023](./ADR-0023-select-workflow-engines-at-definition-or-call-site.md) recorded the selector as inert, because at the time nothing read it.

The orchestrator contract changes that. Two of its four capabilities — `inline` and `subprocess` — are capabilities about exactly this choice: whether a node may run inside the orchestrator's own context or must cross into a fresh one. A capability needs something to range over. With the selector fixed for a whole workspace, a definition could never mix an inline node with a subprocess node, which is the shape the executor workflows are expected to have: judge the input in session, cross a boundary only for the work that needs isolation.

## Considered Options

- Keep `context:` a workspace default and scope the capabilities to the whole run
- Promote `context:` to an optional key on a node
- Derive the context from the engine's provider

## Decision Outcome

Chosen option: `Promote context: to an optional key on a node`. A `step:` may carry `context:` taking the literal `fresh` or `inherit`. Absent, the node takes the workspace default from `meta.yaml`. The value is a file literal, never an expression, and there is no call-site override map — the same one-writer discipline ADR-0023 chose for `engine:`.

Deriving it from the provider was rejected because a same-provider fork is a legitimate reason to cross a boundary: `plan-vetted` forks a Claude reviewer from a Claude coordinator so the reviewer never sees the verdict. Context is a boundary question, not a vendor one.

## Consequences

- `inline` and `subprocess` become per-node capabilities, so one definition may mix both.
- ADR-0023's aside that the selector is inert no longer holds; the choice that record owns — one engine writer, no precedence rule — is unchanged and this record follows it.
- The validator gains one rule it does not yet enforce, because the workflow engine is landing no further code for now. The grammar is accepted ahead of its enforcement, as the loop rules already are.

## Status

Accepted
