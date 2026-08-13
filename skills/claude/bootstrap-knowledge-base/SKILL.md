---
name: bootstrap-knowledge-base
description: >
  Scaffold a knowledge-base project's architecture: the content-library
  conventions, a lean _docs/ metadata namespace describing the content tree, and
  a per-area AGENTS.md digest in every substantial content area. Use when the
  user says "bootstrap-knowledge-base", "knowledge base project", "set up a
  knowledge base", "_docs specs scaffold", or "AGENTS.md digests".
model: opus
effort: low
---

<!-- trigger-tests: "bootstrap-knowledge-base", "knowledge base project", "set up a knowledge base", "AGENTS.md digests" -->

# Bootstrap knowledge base

Scaffold the architecture of a knowledge-base project: a library of knowledge organized as directories and markdown files.

**In a knowledge base the content tree is the product.** `_docs/` is the one specially-marked metadata namespace _about_ that product, exactly as a code project's `docs/` describes its code. That distinction drives everything here — including the trap it implies: a bare root `docs/` directory in a knowledge base is most likely library content, and must be inspected before anything treats it as scaffold metadata.

Every substantial content area carries an `AGENTS.md` digest: a current map of that area, loaded first, derived from its files, never the source of truth. These digests carry `digest-of` frontmatter and are distinct from the single root author-instructions `AGENTS.md`, which belongs to the governance domain.

This skill owns the content-library conventions, the lean `_docs/` scaffold (`guides/`, `reference/`, `explanation/`, the docs index, the documentation conventions and review checklist), and the per-area digest standard. The root `CLAUDE.md`, the root `AGENTS.md`, and `_docs/decisions/` belong to governance; markdown hooks and `.editorconfig` to the lint domain; `.gitignore` (including `.draft/`), `LICENSE`, and `README` to the repo domain. Point at them; never author their files.

Follow the shared routine at `$(cog skill-refs path bootstrap/domain-worker-routine.md)`:

```bash
cog bootstrap-template-review check --domain knowledge-base --type "$TYPE" --json
```

A fresh review means reuse the cached `summary`; stale or missing means research the docs-design canon at `$(cog skill-refs path knowledge-base/docs-design.md)` — optionally enriched with current Diataxis guidance — update `skill-refs/templates/knowledge-base/<type>/` when justified, and `stamp` before reconciling.

## Detect and deploy

```bash
cog kb-detect [--type "$TYPE"] --json
cog kb-apply --type "$TYPE" --conflict "$POLICY" --json
```

Detection resolves `markdown` when markdown dominates the repository and no code language is present. On no match, confirm with the user that this really is a knowledge base — never scaffold a KB over a code project on a weak signal.

Reconcile a project that already carries `_docs/` structure in prose: read the existing files and merge, rather than overwriting metadata the project already tuned. Treat a bare `docs/` tree as library content until inspection proves otherwise.

## Tailor

- Map the existing top-level content directories to the content-library conventions, and describe the product-versus-metadata boundary in the deployed `_docs/explanation/knowledge-base-architecture.md` using the repository's real subject areas.
- Seed the digests: copy `_docs/reference/agents-digest-template.md` into each substantial content area as its `AGENTS.md`, fill the `digest-of` / `last-synced` / `source-files` / `token-estimate` frontmatter, and summarize the area from its own files.
- Point the docs index and conventions at the peer domains that own the rest, without authoring their files.

Keep each durable fact in one owning home. The deployed docs are an index-and-conventions layer, not a second copy of the knowledge.

## Content languages

The knowledge base's content languages are this skill's judgment to determine — from its material and from the user — because the spell checker depends on them:

```bash
cog precommit-spell-select --languages "$LANGUAGES" --json
```

English-only content resolves to `typos`; content including any non-English language resolves to `cspell`. Record the resolved `spell` value in the summary so the lint domain applies the matching variant.

Report the scaffold deployed or reconciled, the conventions mapped to the project's real areas, the digests seeded, the declared content languages and resolved spell variant, and the peer domains a follow-up run should invoke.
