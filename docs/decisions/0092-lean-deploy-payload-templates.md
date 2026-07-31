# ADR-0092: Lean deploy-payload templates

## Context and Problem Statement

[ADR-0019](./0019-lean-positive-skill-prose.md) requires lean, positively-framed prose in `SKILL.md` files, justified by runtime context cost. Nothing governed the artifacts `bootstrap-*` skills deploy into a user's project through `skill-refs/templates/**`. Those carry a different cost — every generated project inherits and maintains them — and the gap let one drift: `templates/nix/python/.envrc` grew a 28-line fatal guard over a hand-synced tool list, 56% of the file, while its four sibling `.envrc` templates stayed at 7 lines. The guard's `exit 1` aborted before `use flake` exported `poetry`, so the shell it failed in could not run the `poetry sync` its own error message demanded.

## Considered Options

- Leave emitted templates to author discretion (status quo).
- Extend the leanness principle to `skill-refs/templates/**` as prose judgment, with cross-file invariants asserted in the template hygiene suite.
- Add a mechanical lint over template size or guard shapes.

## Decision Outcome

Chosen option: **extend the principle to deploy-payload templates**. A template ships the minimum that makes its domain work. An invariant is recorded where it is actionable — a comment beside the thing it constrains — rather than re-implemented as runtime checking code. A defensive guard earns its place only when the failure it catches is otherwise silent or misattributed; a failure already loud at its real point of use needs none. When a guard is warranted, the remedy it prints must be runnable from the state it fails into. Cross-file invariants belong in `test/unit/templates_*.bats`, never in a list a maintainer hand-mirrors across files. Size lint was rejected: line count is a symptom, and a threshold would fire on legitimately large payloads such as `installer/*/install.sh`.

## Consequences

- Good: generated projects inherit less code to maintain, and divergence between sibling templates becomes a visible review signal.
- Bad: like ADR-0019's positive-framing half, this rests on review judgment; whether a given guard is load-bearing stays a per-case call.
- The hygiene suite already asserts the cross-file invariant that motivated the removed guard, so coverage did not regress.

## Status

Implemented. Enacted by `08355d6`: the guard was removed from `skill-refs/templates/nix/python/.envrc`, the invariant relocated to a `PRECONDITION` note in the paired `flake.nix`, `skills/claude/bootstrap-nix/SKILL.md` step 5 updated, and `test/unit/templates_precommit_hygiene.bats` realigned.
