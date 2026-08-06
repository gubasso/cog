---
digest-of: ../../skill-refs/docs-design
last-synced: 2026-08-06
source-files:
  - README.md
  - 00-foundations.md
  - 01-diataxis-zones.md
  - 02-lean-adrs.md
  - 03-subsystem-pages.md
  - 04-agent-context.md
  - 05-drafts-and-promotion.md
  - 06-appetite-and-scope.md
  - 07-plan-and-slices.md
  - 08-tracking-and-revalidation.md
  - 09-known-issues.md
  - 10-lean-markdown.md
  - 99-checklist.md
  - glossary.md
  - template-adr.md
  - template-docs-rules.md
  - template-plan-zone.md
  - template-slice.md
token-estimate: 31045
---

# AGENTS

## Scope

Language-agnostic documentation design canon. Ownership and placement of durable facts; the Diataxis zones plus a plan zone; the artifacts — decision records, subsystem pages, known-issue cases, tracking registries, slices; the process — drafts and promotion, appetite and scope, the plan zone; and the house style plus the pre-merge gate.

## How to use this shelf

Load this file, find the owning chapter in the routing table below, then read that chapter and the sources it names. Do not read the shelf linearly — that is the corpus load [04 — Agent Context](./04-agent-context.md) forbids.

## Rule ownership

| Question the agent arrives with                                         | Owning file                       |
| ----------------------------------------------------------------------- | --------------------------------- |
| Two files state the same fact — which one wins?                         | `00-foundations.md`               |
| Should this be a comment, a name, a test, or a doc?                     | `00-foundations.md`               |
| May I paste a directory tree?                                           | `00-foundations.md`               |
| Where does this document go?                                            | `01-diataxis-zones.md`            |
| Is this the product, or is it about the product?                        | `01-diataxis-zones.md`            |
| Does the docs root go in `docs/` or `_docs/`?                           | `01-diataxis-zones.md`            |
| What does a runbook, case study, or diagnostic page contain?            | `01-diataxis-zones.md`            |
| Does this choice deserve an ADR, and what shape?                        | `02-lean-adrs.md`                 |
| What status does this decision carry now?                               | `02-lean-adrs.md`                 |
| Where is the current design of a subsystem written?                     | `03-subsystem-pages.md`           |
| What should a session load, and how large may an always-loaded file be? | `04-agent-context.md`             |
| Where do scratch notes live, and how do they ship?                      | `05-drafts-and-promotion.md`      |
| How big is this unit of work, and may that change?                      | `06-appetite-and-scope.md`        |
| What files may a unit of work have, and what headings?                  | `07-plan-and-slices.md`           |
| What shape does a plan, a milestone line, or a task list take?          | `07-plan-and-slices.md`           |
| A fact that will be wrong in a month                                    | `08-tracking-and-revalidation.md` |
| A bug in an external system under test                                  | `09-known-issues.md`              |
| May I use bold here?                                                    | `10-lean-markdown.md`             |
| What do I check before merging a docs change?                           | `99-checklist.md`                 |
| What does this shelf mean by `<term>`?                                  | `glossary.md`                     |

## Non-negotiables

- One owner per durable fact; every other mention is a link.
- Docs never live inside the product: `docs/` for a codebase, `_docs/` for a knowledge base.
- Never delete an accepted decision; supersede, deprecate, reject, or amend it.
- Drafts stay out of `docs/`; a binding plan is project state, not a draft.
- No bold and no italics, anywhere.
- Every fenced block declares a language.
- Never paste a tree of a directory that already exists.

## Maintenance

- Regenerate when any source file changes.
- This file is a map and never a rules home; introduce no rule here that a chapter does not own.
- When this file and a chapter disagree, the chapter is authoritative.
- Keep `source-files` ordering stable so context loaders can diff revisions predictably.
