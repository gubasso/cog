# Documentation Design

Language-agnostic principles for organizing a software project's `docs/` directory: clear document ownership, lean decision records, operational docs that are easy to find, a plan zone for what is next, and source-of-truth rules that humans and LLM agents can both follow. It is intentionally small — enough structure to prevent drift, not enough to turn documentation into a separate process.

## Problem

Most project documentation decays for predictable reasons. A rule starts in a design note, gets copied into a README, is restated in an onboarding guide, and then changes in only one place. A draft records useful reasoning but never becomes a decision. A troubleshooting page grows into a mixed bag of runbooks, diagnostics, background, and stale conclusions. Eventually readers stop trusting the docs and fall back to guessing from code, chat history, or old issues.

The cure is not more ceremony. It is a small set of homes with clear ownership: each fact has one source of truth, each document serves one reader need, and each decision stays short enough to be reviewed, indexed, and superseded when it stops being true.

## Chapters

| #        | Chapter                                                        | One-line hook                                                       |
| -------- | -------------------------------------------------------------- | ------------------------------------------------------------------- |
| 0        | [Foundations](./00-foundations.md)                             | Which artifact owns a fact, and what wins when two disagree.        |
| 1        | [Diataxis Zones](./01-diataxis-zones.md)                       | The docs root, the five homes by reader need, and operational docs. |
| 2        | [Lean ADRs](./02-lean-adrs.md)                                 | MADR-minimal records, a 350-word cap, and a never-delete lifecycle. |
| 3        | [Subsystem Pages](./03-subsystem-pages.md)                     | The living design page: records freeze, descriptions stay live.     |
| 4        | [Agent Context](./04-agent-context.md)                         | Context pollution, semantic names, and one entry document per job.  |
| 5        | [Drafts and Promotion](./05-drafts-and-promotion.md)           | Keep drafts out of shipped docs and promote by reader need.         |
| 6        | [Appetite and Scope](./06-appetite-and-scope.md)               | Fix the budget, vary the scope, and gate every change to it.        |
| 7        | [Plan and Slices](./07-plan-and-slices.md)                     | The plan zone's documents and one directory per unit of work.       |
| 8        | [Tracking and Revalidation](./08-tracking-and-revalidation.md) | Track perishable facts and revalidate their sources on a cadence.   |
| 9        | [Known Issues](./09-known-issues.md)                           | Track bugs in external systems under test; expand then collapse.    |
| 10       | [Lean Markdown](./10-lean-markdown.md)                         | Spend markdown on structure; drop bold, italics, and decoration.    |
| 99       | [Checklist](./99-checklist.md)                                 | The pre-merge review gate for a documentation diff.                 |
|          | [Glossary](./glossary.md)                                      | One sentence per term, each naming the chapter that owns it.        |
| Template | [ADR](./template-adr.md)                                       | Drop-in lean ADR.                                                   |
| Template | [Slice](./template-slice.md)                                   | Drop-in entry document for one unit of work.                        |
| Template | [Plan zone](./template-plan-zone.md)                           | Drop-in charter, milestones, and open-questions skeletons.          |
| Template | [Docs rules](./template-docs-rules.md)                         | Drop-in maintenance block for a project's author-instructions.      |

## Reading

Read the chapters in number order. Ownership comes before location, so the zone chapter can be a placement map rather than a re-argument; the frozen record and the living description are adjacent because their whole doctrine is the contrast between them; the agent constraint precedes the process chapters that build on it; and style and the review gate come last, applied to material you already know how to produce.

An agent should not read the shelf linearly. Load [AGENTS.md](./AGENTS.md), find the owning chapter in its routing table, and read that chapter plus the sources it names — the corpus load is exactly what [04 — Agent Context](./04-agent-context.md) forbids.

## Adopting this shelf

Copy [template-docs-rules.md](./template-docs-rules.md) into the project's author-instructions file, take the layout from [01 — Diataxis Zones](./01-diataxis-zones.md), copy [template-adr.md](./template-adr.md), add [template-slice.md](./template-slice.md) and [template-plan-zone.md](./template-plan-zone.md) if the project plans before it builds, and use [99 — Checklist](./99-checklist.md) at review time.

For a new project, start small: create only the zones that have real content and keep the same placement rules. Empty structure is not the goal; predictable ownership is. For an existing project, migrate by ownership — decisions first, then operational guides and reference material, leaving broad explanation until the factual sources of truth are clear.

Apply this to any project with a `docs/` directory, more than one maintainer, recurring design decisions, operational procedures, or an agent in the loop. Do not spend time on it for a throwaway spike with no readers beyond the author, do not create empty directories to signal maturity, and do not write an ADR for a choice that a type name already expresses. If applying it creates more documents than the project can keep truthful, shrink the inventory and keep the placement rules.

## House format

The markdown rules are [10 — Lean Markdown](./10-lean-markdown.md), which this shelf obeys. What is specific to the shelf's own layout:

- Frontmatter: only `AGENTS.md` carries it.
- One `#` per file. `##` for sections, `###` only for genuinely parallel sub-parts. Never `####`.
- An unheaded opening of two to four sentences states what the file owns, then normative sections, then `## Anti-patterns` where the chapter has failure modes, then `## Sources`.
- No `## See also`. This table and inline links are the navigation.
- Paragraphs carry one point, normally three sentences or fewer.
- Cite inline at the claim when one claim uses a source; a trailing `## Sources` block only where a chapter carries three or more. A URL appears in two chapters only when each supports a different claim.
- In-shelf links take the form `[NN — Title](./NN-slug.md)`.
- `<angle>` placeholders for anything project-specific; no real project name appears in the shelf.
- Hand-wrap at 100 columns; the formatter maintains wrapping rather than reflowing it.
