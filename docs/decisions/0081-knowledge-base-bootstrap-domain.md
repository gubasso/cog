# ADR-0081: Knowledge-base as a bootstrap domain with a docs-as-specs scaffold

## Context and Problem Statement

A common project type is a knowledge base: a library of knowledge organized as directories and
markdown files. `cog`'s `bootstrap-*` skills covered only code-project domains. Two gaps blocked
support: `cog classify-project` detected only code languages, so a pure-markdown repo yielded empty
`languages` and every template auto-detection failed; and no skill owned the knowledge-base's own
architecture — its content conventions, its `docs/` specs, or the per-area `AGENTS.md` digest
standard.

## Considered Options

- Extend `bootstrap-governance` with a knowledge-base variant.
- A single self-contained `bootstrap-knowledge-base` worker plus markdown project-type detection.
- Detection only, leaving authors to invoke the existing markdown templates by hand.

## Decision Outcome

Chosen option: **a self-contained `bootstrap-knowledge-base` worker plus KB detection**. The product
of a knowledge base is the knowledge itself (the content tree); `docs/` holds the specs about that
product, exactly as a code project's `docs/` describes its code. `classify-project` now reports
`markdown` and `project_types: ["knowledge-base"]` when markdown dominates and no code language is
present, and `fn_template` resolves `markdown` as a fallback match — so pre-commit and editorconfig
auto-target markdown. The new worker owns the content-library conventions, a lean Diataxis `docs/`
specs scaffold, and the per-area content-digest `AGENTS.md` standard, delegating deterministic
detection/copying to `cog kb-detect`/`kb-apply`. Per the one-domain rule it authors none of the peer
files: root `CLAUDE.md`/`AGENTS.md` and `docs/decisions/` stay with governance, markdown hooks with
pre-commit, `.editorconfig` with editorconfig, and `.gitignore`/`LICENSE`/`README` with repo. It is a
conditional worker (like `bootstrap-installer`), not a `bootstrap-audit` domain, so a code project
never reads a missing knowledge base. Extending governance was rejected because it would split the
`docs/` scaffold across two workers; detection-only was rejected because it leaves the KB architecture
unowned.

## Consequences

- Good: knowledge-base projects gain a first-class scaffold and the existing markdown templates
  finally auto-target.
- Good: the docs-design canon is copied in-repo (`skill-refs/knowledge-base/docs-design.md`), keeping
  the repository self-contained (ADR-0071).
- Bad: the governance↔KB seam (root author-instructions `AGENTS.md` versus per-area content-digest
  `AGENTS.md`; `docs/decisions/` versus the other zones) must be respected by both workers.

## Status

Implemented — `lib/commands/cmd_classify_project.sh`, `lib/functions/fn_template.sh`,
`lib/functions/fn_bootstrap_review.sh`, `lib/commands/cmd_kb_detect.sh`,
`lib/commands/cmd_kb_apply.sh`, `skill-refs/templates/knowledge-base/`,
`skill-refs/knowledge-base/docs-design.md`, and `skills/claude/bootstrap-knowledge-base/SKILL.md`.
Relates to ADR-0016 (prefix taxonomy), ADR-0062 (template-refresh review), and ADR-0071
(self-containment). The knowledge-base detection described here is refined by ADR-0082
(reliable, prose-immune classification): KB is now gated on content dominance plus the absence of a
build manifest and negligible code, and is mutually exclusive with `cli`.
