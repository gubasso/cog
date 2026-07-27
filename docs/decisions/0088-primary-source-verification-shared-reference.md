# ADR-0088: Primary-Source-Verification Shared Reference

## Context and Problem Statement

A fixed "verify claims against primary official sources" directive was re-worded and re-inlined across
the review, implementation-review, review-plan, and test-review skill families (both twins), and echoed
by the `ask -w` web-search flag (which rendered its own paragraph from `data/ask-flags`). The wording
is not subject to any user option, so it is not a runtime-render-per-flag case (ADR-0087); it is shared
canonical prose each skill obeys in its own context. The duplication had no single source of truth and
could drift across the twins.

## Considered Options

- Leave each skill's inline wording as-is (status quo; duplicated, drift-prone).
- Stamp a canonical stanza into each skill, drift-pinned by a `skill-lint` rule (the gate mechanism).
- Put the directive in one `skill-refs/` reference doc that every consumer draws from.

## Decision Outcome

Chosen option: **one skill-refs reference doc**,
`skill-refs/research/primary-source-verification.md`, consumed two ways from a single source:

- **Reviewers** (read the directive in their own context) reference it via
  `cog skill-refs path research/primary-source-verification.md`, keeping their role-specific wiring
  (research targets, phases, examples) and delegating only the canonical directive to the doc.
- **`ask -w`** (injects the directive into a delegated research sub-prompt) reads the same doc's content
  and injects it. The `web-search` directive therefore graduates out of ask-private `data/ask-flags`
  (its `web-search` entry is removed; `-r/real-world` stays ask-private).

This is the established idiom for shared canonical prose that multiple skills must honor (e.g.
`orchestration/verdict-model.md`), and it is the right default whenever the content is *knowledge a
skill applies* rather than *a guarantee the system structurally enforces*.

## Consequences

- Good: one validated source; no cross-twin duplication or drift; rewording is a one-file edit.
- Good: `install.sh` already copies the whole `skill-refs/` tree, so no install wiring changes.
- Neutral: the directive is a runtime-resolved pointer for reviewers (they read it), and injected
  content for `ask -w`.
- This amends the web-search portion of [ADR-0087](0087-runtime-rendered-ask-flag-instructions.md):
  `-w` now sources from the shared doc; `cog ask-flag` retains only `real-world`.

## Status

Implemented. References [ADR-0023](0023-skill-refs-unified-resource-sot.md),
[ADR-0024](0024-skill-reference-self-containment-golden-rules.md),
[ADR-0019](0019-lean-positive-skill-prose.md), and [ADR-0087](0087-runtime-rendered-ask-flag-instructions.md).
