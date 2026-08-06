<!-- markdownlint-disable-file MD041 -->

Copy this block into `<project>/CLAUDE.md` or the local author-instructions file under a `## Documentation Maintenance` heading. Link this shelf rather than pasting it, then state local exceptions below the block. Drop any rule the project has no artifact for; an unused rule is noise a session pays for on every load.

## Documentation Maintenance

- Keep documentation out of the product's own namespace: `<project>/docs/` when the product is a codebase, `<project>/_docs/` when the product is the content tree. In a knowledge base, read every `docs/` path below as `_docs/`, and never file a knowledge article there.
- Put decisions in `<project>/docs/decisions/`, task docs and runbooks in `<project>/docs/guides/`, lookup and diagnostics in `<project>/docs/reference/`, and architecture and background in `<project>/docs/explanation/`.
- Put scope, milestones, and open questions in `<project>/docs/plan/` when the project defines its work before building it; a binding plan is project state, not a draft.
- Keep the current design of a subsystem in `<project>/docs/explanation/<subsystem>.md`. It stays live; the ADRs it links stay frozen.
- Keep filled ADRs at or below 350 words with exactly one `Status`.
- Never delete an accepted decision. Supersede it, deprecate it, or reject it; a partial change keeps the status and adds an `Amended by ADR-NNNN` line.
- Give every unit of work a fixed appetite and a declared non-negotiable core, and change the appetite only by a committed edit citing the condition met.
- Give every unit of work one directory under `<project>/docs/plan/slices/`, entered through its `README.md`, with no sibling file that has not met its gate.
- Pin every fixed-shape document's headings with an `MD043` array in a `markdownlint-configure-file` comment under its H1 — the slice `README.md` and `milestones.md` at minimum — and add a section by amending that array, never by deleting the comment.
- Until the current slice is implemented, do not add a specification page and do not open an ADR outside it. A question that arises goes to `<project>/docs/plan/open-questions.md`.
- Work from the current slice and the sources its `Governed by` section names, and nothing else.
- Write each durable fact once at its owning home and cross-link from everywhere else.
- Let the filesystem own structure: index files explain purpose and never replicate a directory tree.
- Keep drafts in `<project>/.draft/` or another gitignored workspace, out of `<project>/docs/`.
- Keep code comments load-bearing: rationale, invariants, boundary conditions, and links to owning decisions.
- Track bugs in external systems under test as cases under `<project>/docs/reference/known-issues/`; expand while hot, collapse to one summary when resolved.
- Track perishable facts in a machine-readable registry with a cadence and a `last_checked` date.
- Use no bold and no italics. Put identifiers, paths, flags, and status values in inline code, and binding requirements in uppercase RFC 8174 keywords. Every fenced block declares a language.
- Preserve `<angle>` placeholders in project-agnostic material.
- Update docs when a change affects durable behavior, operations, or decisions — not for every implementation detail — and report the change by ownership: which source of truth changed, which links were added, which hooks passed.
