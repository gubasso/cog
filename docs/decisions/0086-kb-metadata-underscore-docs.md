# ADR-0086: Knowledge-base metadata lives under `_docs/`

## Context and Problem Statement

ADR-0081 introduced knowledge-base bootstrap with a `docs/` specs scaffold. The user-facing model has since been sharpened: in a knowledge base, every free-form root directory can be library content. A bare `docs/` directory therefore looks like content, while project metadata needs a visually distinct home.

## Considered Options

- Keep all knowledge-base metadata under `docs/`.
- Move only the knowledge-base specs scaffold to `_docs/`, while governance ADRs stay under `docs/decisions/`.
- Move the whole knowledge-base metadata namespace, including governance ADRs, to `_docs/`.

## Decision Outcome

Chosen option: **move the whole knowledge-base metadata namespace to `_docs/`**. The knowledge-base product is the library: the root content tree of directories and markdown files. `_docs/` is the one specially-marked directory that is not library content; it holds specs, definitions, guides, explanations, and decisions about the library.

Governance still owns the ADR scaffold, but in a knowledge base it deploys that scaffold to `_docs/decisions/`. In non-KB projects, governance keeps the default `docs/decisions/` destination.

## Consequences

- Good: KB library content is not confused with project metadata.
- Good: specs and decisions share one metadata namespace in a KB.
- Bad: governance apply/detect must be parameterized by destination docs directory.

## Status

Implemented. Refines ADR-0081 while preserving its accepted history.
