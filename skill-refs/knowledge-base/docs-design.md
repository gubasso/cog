# Documentation design canon (knowledge-base bootstrap reference)

Language-agnostic principles for organizing the `docs/` specs of a knowledge-base or software project. The `bootstrap-knowledge-base` worker reads this canon to tailor the scaffold it deploys; the deployed project receives a distilled, self-sufficient subset under its own `docs/`. This file is the in-repo source of truth for that design system, so the repository depends on no external shelf.

Sources for further reading: <https://diataxis.fr/>, <https://diataxis.fr/how-to-use-diataxis/>, and <https://www.writethedocs.org/guide/writing/docs-principles/>.

## Product and specs

In a knowledge base the product is the knowledge itself — the content directories and markdown files. `docs/` holds the specs about that product, exactly as a code project's `docs/` describes its code. Knowledge goes in the content tree; rules about the knowledge base go in `docs/`.

## Defaults

- Use four zones: `decisions/`, `guides/`, `reference/`, `explanation/`.
- Put decisions in lean ADRs; keep filled bodies at or below 350 words.
- Never delete accepted decisions; mark them superseded or rejected and link forward.
- Keep drafts outside the shipped tree, normally under a gitignored `.draft/`.
- Write each durable fact once at its owning home and cross-link elsewhere.
- Keep index files (`README.md`, `AGENTS.md`) as purpose maps; never replicate the directory tree.
- Carry an `AGENTS.md` digest in each substantial content area, derived from its sources.

## Diataxis zones

Documentation is organized by reader need, because one document cannot serve every mode well.

| Need          | Reader question                            | Zone          |
| ------------- | ------------------------------------------ | ------------- |
| Task          | What do I do next?                         | `guides`      |
| Lookup        | What is the exact value, rule, or symptom? | `reference`   |
| Understanding | How does this area fit together?           | `explanation` |
| Decision      | Why did the project choose this shape?     | `decisions`   |

Zone comes first, topic second. A top-level topic folder mixes reader needs and forces readers to infer intent from prose. Operational material follows the same map: runbooks are guides; diagnostics and case studies are reference.

## Lean ADRs

A decision record captures the decision, not the whole debate: problem, serious options, chosen option, consequences, status. Lifecycle is `Proposed → Accepted → Implemented → Superseded |
Rejected`. Never delete an accepted or implemented decision; supersede or reject and link forward. Supporting data too large for the ADR lives in reference or explanation, linked from the ADR.

## Comments and code as source of truth

Where a knowledge base ships example code or scripts, code owns behavior and comments own the rationale code cannot express: boundary conditions, invariants, surprising constraints, and links to the owning decision. Delete comments that narrate obvious code; prefer better names and types.

## Single source of truth

Write once at the owning home and link from other places. Restatement drifts. Project-wide rules live in author instructions; decisions in ADRs; exact facts in reference. Resolve a conflict by editing the non-owner to link to the owner. A digest is a map; source chapters and project docs own the guidance.

Structure is a durable fact the filesystem already owns. The directory listing is the source of truth for what exists; index files (`README.md`, `AGENTS.md`) explain a directory's purpose — its domains, concepts, and rules — and never maintain a parallel copy of the file tree. When a listing aids discovery, give each entry a purpose (`- [docker](./docker.md) — daemon setup`), not a bare path the filesystem already shows: if deleting the listing loses nothing the filesystem does not carry, it was a duplicated tree, not an index. The exception is a block a tool regenerates from the tree — an auto-generated table of contents — where the generator owns and syncs the copy.

## Drafts and promotion

Drafts live outside shipped docs. Promotion rewrites the draft into the right zone and deletes the draft; it does not move the draft unchanged. Split a mixed draft by reader need before promotion. Promote a rejected path as a rejected ADR only when the rejection has future value.

## AI agent considerations

Documentation bloat is context pollution: every duplicated rule, stale draft, and oversized ADR competes with the agent's real task. Lean, well-named, single-owner docs reduce retrieval ambiguity. Author-instruction files (`CLAUDE.md`, `AGENTS.md`) are the entry point and should carry a documentation-maintenance section. Per-area `AGENTS.md` digests summarize source files and never become the source of truth. Agents update docs for durable behavior, operations, or decisions — not every detail.

## The AGENTS.md digest standard

Each substantial content area carries an `AGENTS.md` digest: a concise map of that area, loaded first by an agent, derived from the area's files. It carries frontmatter — `digest-of`, `last-synced`, `source-files`, `token-estimate` — so staleness is visible, and is regenerated when a source file changes or is added. When a digest and a source disagree, the source wins and the digest is regenerated. Keep source-file ordering stable so context loaders can compare revisions.

## Tracking and revalidation

A perishable fact — a price, benchmark, model roster, or external API shape — carries an owner, a revalidation cadence, and a `last_checked` date in a small machine-readable registry. The tracked artifact stays the source of truth; the registry keeps it from going stale. Overdue scanning is deterministic; revalidation is judgment and should surface uncertain drift.

## Known issues

Track a bug in an external system under test as a known-issue case under `reference/known-issues/`, not a top-level topic folder. One case is one directory `KI-<NNNN>-<slug>/` keyed on the internal id, with a small skeleton (index, metadata, investigation, escalation, evidence; a mask ledger only when a workaround exists). Lifecycle is `open → investigating → mitigated | masked → monitoring → resolved`; on resolution the directory collapses to one summary (issue, root cause, resolution, recurrence signal) with the raw trail left in version-control history.

## Review checklist

Before merging a documentation or content change, confirm: single reader need and correct zone; no restated facts; cross-links to owners; no pasted filesystem trees; placeholders in project-agnostic material; lean ADRs with one canonical status and no deleted decisions; drafts kept outside shipped docs; semantic filenames and stable headings; regenerated digests that add no new rules; passing link, spelling, and markdown hooks; and a nameable source of truth for every durable fact touched.
