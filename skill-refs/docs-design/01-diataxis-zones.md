# 01 — Diataxis Zones

Diataxis organizes documentation by reader need, because one document cannot serve every mode well. A reader doing a task wants steps; a reader debugging a field wants lookup material; a reader learning a system wants explanation; a maintainer reviewing a design wants the decision record. This chapter defines the homes. Which home a given fact belongs to is decided in [00 — Foundations](./00-foundations.md).

## The docs root

Every zone sits under a docs root, and where that root goes depends on what the project's product is.

In a code project the product is the codebase. Documentation describes something that is not itself prose, so a plain `docs/` at the repository root is unambiguous: what is outside it is the product, what is inside it is about the product.

In a knowledge base the product is the content — the directories and markdown files the library exists to serve. Documentation about the library is also markdown at the root, so a plain `docs/` would sit inside the product's own namespace and read as one more subject area. The root is therefore `_docs/`, whose leading underscore sorts it clear of the content listing and marks it as the one top-level directory that is not library content.

```text
code project                          knowledge base
────────────                          ──────────────
src/     ┐                            <subject>/  ┐
lib/     ├ the product                <subject>/  ├ the product — the library
tests/   ┘                            <subject>/  ┘

docs/    → about the product          _docs/      → about the product
```

The difference is the root's name, not its contents. The zones below, their reader promises, and the placement rules are identical under either root. This shelf writes `docs/` throughout; in a knowledge base, read every such path as `_docs/`.

One test decides which side a file falls on: is this about how the project works, or is it the thing the project produces? A page explaining the library's own conventions is about the project and goes under `_docs/`. A page of the knowledge the library exists to serve goes in the content tree, and never under `_docs/` — the boundary only holds if it holds in both directions.

## The zones

| Zone        | Default path                  | Reader question                                      | Holds                                             |
| ----------- | ----------------------------- | ---------------------------------------------------- | ------------------------------------------------- |
| Guides      | `<project>/docs/guides/`      | What do I do next?                                   | Task sequences, runbooks, setup, migrations       |
| Reference   | `<project>/docs/reference/`   | What is the exact value, field, command, or symptom? | Schemas, option tables, diagnostics, case studies |
| Explanation | `<project>/docs/explanation/` | How does this area fit together?                     | Architecture, subsystem pages, design forces      |
| Decisions   | `<project>/docs/decisions/`   | Why did the project choose this shape?               | Lean ADRs                                         |
| Plan        | `<project>/docs/plan/`        | What are we building next, and what bounds it?       | Charter, milestones, open questions, slices       |

The zones are not content categories; they are reader promises. A guide promises sequence and completion. A reference page promises stable lookup and precise facts. An explanation promises context and trade-offs. A decision record promises the choice and its consequences.

Treat the need as a mode, not a reader identity. The same maintainer is a learner in the morning, a task-doer during a release, and a reviewer in the afternoon. The path should tell them which mode the document supports before they read the first paragraph.

A project may add topic directories inside a zone when volume requires it, as `<project>/docs/guides/<topic>/`. The topic comes after the reader need, never before it.

## The plan zone

Diataxis organizes what exists: all four reader needs are asked about a system that is already there. It does not model intent over time, and does not claim to. A project that defines its artifacts before implementing them needs a home for what is being built next, what bounds it, and what is still undecided — material that is not a task, not lookup, not a mental model, and not a settled decision.

```text
               what exists  (Diataxis)
┌──────────────────────────┬──────────────────────────┐
│ guides/                  │ reference/               │
│ "what do I do next?"     │ "what is the exact       │
│                          │  value, field, symptom?" │
├──────────────────────────┼──────────────────────────┤
│ explanation/             │ decisions/               │
│ "how does this area      │ "why did the project     │
│  fit together?"          │  choose this shape?"     │
└──────────────────────────┴──────────────────────────┘
                  ▲
                  │  all four are asked about a system
                  │  that is already there
─ ─ ─ ─ ─ ─ ─ ─ ─ ┼ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   second axis: intent
                  │
┌─────────────────┴─────────────────────────────────────┐
│ plan/                                                 │
│ "what are we building next, and what bounds it?"      │
│ the only zone whose contents are expected to go stale │
└───────────────────────────────────────────────────────┘
```

The plan zone is the only zone whose contents are expected to become false. A guide that stops being true is a bug; a milestone that stops being current is the normal course of the work. That is why plan documents carry statuses and the other four do not, and why a plan document may serve intent, scope, and status at once instead of one reader need. Work that finishes leaves the zone the way any fact does: the durable result moves to the zone that owns it and the plan keeps only the pointer.

What bounds a unit of work is in [06 — Appetite and Scope](./06-appetite-and-scope.md); what documents the zone holds is in [07 — Plan and Slices](./07-plan-and-slices.md).

## Operational material

Operational documentation often grows outside the model because it starts under pressure: a fix becomes a runbook, a failure analysis becomes a case study, a diagnostic command becomes a reference page. The zones still apply — runbooks and setup walkthroughs are guides, diagnostics and case studies are reference.

A runbook is written for execution under pressure and contains preconditions, ordered actions, verification, rollback or stop conditions, and links to the diagnostics it uses. Every destructive or irreversible action names its confirmation point before the action, and a destructive command shows the dry-run or inspection form first where the tool supports one. A runbook that requires understanding the whole architecture before acting is not a runbook; move that background to explanation and link it.

A diagnostic page is optimized for lookup and contains symptom, signal or command, expected result, interpretation, and a link to the guide that uses it. It helps a reader decide which bucket a failure is in; it does not need to solve every bucket inline.

A case study records what happened, what signals were present, what fixed it, and what durable lesson remains. It is not the only home for a new rule: when a case study changes policy, write the ADR or update the author-instructions file and link to it.

Workflows and setup walkthroughs are guides with a clear start state, end state, and verification step. Setup docs are not a mirror of every configuration option; link to configuration reference for accepted values and defaults.

Place all of it zone-first: `<project>/docs/guides/<topic>/runbooks/`, `<project>/docs/reference/<topic>/case-studies/`, diagnostics directly under `<project>/docs/reference/<topic>/`. If operational docs become hard to scan, improve the indexes inside each zone rather than adding a top-level operational bucket.

## Boundary tests

Ask before creating or moving a file:

- Actively trying to finish work → guides.
- Comparing exact values, fields, statuses, or symptoms → reference.
- Trying to understand a subsystem → explanation.
- Asking why a choice was made → decisions.
- Asking what is being built next or what bounds it → plan.
- Needs multiple homes → choose the owner and link from the others.

The last rule matters most. Cross-links are cheap; duplicate facts are expensive. When a page is hard to place, write its intended first sentence as a user need — "I need to deploy `<feature>`", "I need the exact status values", "I need to know why this exists". The sentence usually names the zone.

## Anti-patterns

- Docs root inside the product: a knowledge base with a bare `docs/` at its root, which a reader cannot distinguish from a subject area, and which invites knowledge articles to be filed as metadata.
- Topic-first top level: a `<topic>/` directory as a sibling of the zones, holding a runbook, a decision, and an overview together, so every reader must open files to infer intent.
- README as junk drawer: the root docs README is an index into the zones, not the canonical home for decisions, procedures, and troubleshooting.
- Guide as encyclopedia: task docs embedding complete reference tables instead of linking them.
- Explanation as policy: project-wide rules living only in background prose.
- Case study as runbook: a past event informing a runbook is fine, but the event belongs in reference and the repeatable procedure in guides.
- Decision hidden in guide: a guide saying "we always do X because Y" when the durable why belongs in an ADR the guide links.
- Plan zone as a fifth topic folder: if `plan/` holds anything a reader would consult after the work ships, that content belongs in one of the four reader-need zones.

## Sources

- Diataxis: <https://diataxis.fr/>
- How to use Diataxis: <https://diataxis.fr/how-to-use-diataxis/>
