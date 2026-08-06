<!-- markdownlint-disable-file MD041 MD043 -->

Copy each block below into the named file under `<project>/docs/plan/`. Create only the documents the project actually maintains; an empty charter is worse than no charter. The slice entry document has its own template — see [template-slice.md](./template-slice.md). Rules for all three are in [07 — Plan and Slices](./07-plan-and-slices.md).

## `charter.md`

```markdown
# <project> — Charter

## What this is for

<Two or three sentences. The outcome the project exists to produce, not the mechanism.>

## Pillars

- <A property every slice is judged against.>
- <Another.>

## No-gos

- <Something this project will not do, and the reason.>
- <Another.>

## Appetite unit

<Calendar time | human review passes | implementation sessions.> One unit, kept for the project's life.
```

Two pages at most. Revised per release, never per slice.

## `milestones.md`

```markdown
# Milestones

<!-- markdownlint-configure-file { "MD043": { "headings": ["# Milestones","## in flight","## closed"] } } -->

The single status surface. A reader consults this and nothing else to know where the work stands.

One line per slice, ordered by id inside its section: `<id> <slug> — <status> — <appetite>[ — <note>]`.

Two sections, live work first. A slice moves to `## closed` when its status becomes terminal — `done`, `cut`, or `reshaped` — and never moves back.

## in flight

- 002 <slug> — active — <n>
- 003 <slug> — shaped — <n>

## closed

- 001 <slug> — done — <n>
```

Status is one of `shaped`, `active`, `done`, `cut`, or `reshaped`. A `reshaped` line names its successor id in the note. A `cut` line names what was cut. When `## closed` outgrows scrolling, move it wholesale to `milestones-closed.md`, leave one link, and drop `## closed` from the heading array above; that file is history, not a status surface.

Keep the `markdownlint-configure-file` comment: it pins these three headings so no fourth section arrives, and it works with no project config beyond a markdownlint hook. See [10 — Lean Markdown](./10-lean-markdown.md#pinning-a-fixed-heading-shape).

Derive whatever can be derived from the slices themselves so this cannot silently disagree with them.

## `open-questions.md`

```markdown
# Open questions

Triage, not a queue. Every entry names what it blocks and leaves by one of three exits: an ADR, a `Revisions` line in a slice, or a recorded measurement.

## Q-001 — <the question, as a question>

Blocks: <the slice id and heading, the decision, or the acceptance line this holds up>. Raised: <when and in what context>. Exit: <ADR | slice revision | measurement>, <what specifically closes it>.
```

An entry that blocks nothing is a note, and notes belong in the drafts workspace; see [05 — Drafts and Promotion](./05-drafts-and-promotion.md).
