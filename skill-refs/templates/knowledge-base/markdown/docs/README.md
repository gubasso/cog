# `<project>` docs

This directory holds the **specs about the product**. In `<project>` the product is the
knowledge base itself — the directories and markdown files that hold the actual knowledge. This
`docs/` tree does not hold that knowledge; it holds the definitions, decisions, architecture,
conventions, and patterns that govern how the knowledge base is built and maintained, exactly as a
code project's `docs/` describes its code.

This file is an index only. Each durable fact lives once in its owning zone; everything else links
to it.

## Zones

Documentation is organized by reader need (Diataxis):

| Zone                          | Reader need                          | What lives here                                 |
| ----------------------------- | ------------------------------------ | ----------------------------------------------- |
| [`decisions/`](./decisions/)  | Why was this chosen?                 | Lean ADRs recording durable decisions.          |
| [`guides/`](./guides/)        | How do I do this task?               | Runbooks and step-by-step procedures.           |
| [`reference/`](./reference/)  | What is the exact value or rule?     | Lookup material, conventions, diagnostics.      |
| [`explanation/`](./explanation/) | How does this fit together?       | Architecture and conceptual background.         |

## Start here

- [Knowledge-base architecture](./explanation/knowledge-base-architecture.md) — the product↔docs
  relationship and the AGENTS.md digest standard.
- [Documentation conventions](./reference/docs-conventions.md) — placement, lean ADRs,
  single-source-of-truth, drafts, and the digest standard.
- [Documentation review checklist](./reference/docs-review-checklist.md) — the pre-merge guard for
  documentation and content changes.

## Rules

- Put each durable fact in one owning zone and link to it from everywhere else.
- Keep this README an index; move any rule, procedure, or decision that lands here into its zone.
- Let the filesystem own structure. Index files (`README.md`, `AGENTS.md`) explain a directory's
  purpose and give each listed entry a purpose, not a bare path; they never paste a hand-maintained
  file tree (an auto-generated table of contents is the exception). See
  [documentation conventions](./reference/docs-conventions.md).
