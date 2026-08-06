# Bootstrap

Bootstrap reconciles one project domain at a time from reviewed in-repo templates. [ADR-0019](../decisions/0019-bootstrap-domain-architecture.md) and [ADR-0020](../decisions/0020-project-classification-and-precommit-overlays.md) own the domain and classification architecture.

## Components and boundaries

The audit command reports domain presence and unmet requirements. Coordinators select language and domain workers, which detect current state, refresh template review evidence, and install or reconcile the bounded payload.

Classification ignores prose signals, reports ambiguity, and selects environment-aware execution. Pre-commit overlays compose Markdown, spelling, and Nix requirements without replacing a project's language policy.

## Current constraints

Repository identity is resolved before identity-bearing fields are written. Publishing authentication stays script-local, knowledge-base metadata uses `_docs/`, and reviewed templates remain self-contained.

## Unresolved

- Ambiguous mixed-language repositories still require an explicit operator choice.
