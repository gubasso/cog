# 07 — Plan and Slices

[01 — Diataxis Zones](./01-diataxis-zones.md) adds a plan zone for what is next. [06 — Appetite and Scope](./06-appetite-and-scope.md) says what bounds a unit of work inside it. This chapter says what documents the zone holds and what shape the unit of work takes on disk.

The shape is deliberately small. Every artifact has to survive one question: what does a reader or an agent session lose if this file does not exist? Anything that fails that question is ceremony, and ceremony is indistinguishable from diligence until you count.

## The plan zone's documents

```text
<project>/docs/plan/
  charter.md         What the project is for, its pillars, and its no-gos. Two pages at most.
                     Written once, revised per release, never per slice.
  milestones.md      The ordered slices, one line each, with a status. The single status surface:
                     a reader consults this and nothing else to know where the work stands.
  open-questions.md  Questions that could change a decision, and what each one blocks.
  slices/            One directory per unit of work.
```

`charter.md` and `milestones.md` are the only documents a reader consults without a slice in hand. Keep both short enough that they are read rather than skimmed. Use the drop-in [plan-zone template](./template-plan-zone.md) for all three.

### `milestones.md`

Two sections, live work first. One line per slice, ordered by id inside its section, in a fixed grammar:

```text
<id> <slug> — <status> — <appetite>[ — <note>]
```

```text
## in flight

- 007 rate-limit-login — active — 3 passes
- 008 audit-log-export — shaped — 2 passes
- 009 session-store-v2 — shaped — 1 pass

## closed

- 004 session-store — reshaped — 1 pass — re-shaped as 009
- 005 bulk-import — cut — 2 passes — remainder cut, core shipped
- 006 password-reset-email — done — 2 passes
```

A list rather than a table, because the maintenance falls on the wrong person. A table's columns must be re-aligned by hand every time a slug or a note changes width, and a note long enough to be useful pushes the row past any sane line length. The raw file is what an agent session and a `git diff` actually read, and a table gets harder to read there the more slices the project has. The list costs nothing to maintain, diffs one line per change, and greps cleanly by id or by status. A table is still the right instrument for a comparison or an exact mapping; see [10 — Lean Markdown](./10-lean-markdown.md). A growing status surface is neither.

The grammar is fixed so it can still be parsed: em dash separators, fields in that order, the note optional and last. Nothing else goes on the line.

- `shaped` — the slice document is committed and the work has not started.
- `active` — implementation is in progress.
- `done` — the named tests pass unskipped.
- `cut` — the slice shipped its core and its remainder was cut. This is a success, not a failure.
- `reshaped` — the work was stopped uphill and re-shaped; the note names the successor id.

The section split is the same distinction Emacs Org-mode draws with the vertical bar in its `#+TODO:` sequences, which separates the states that need action from the states that need none; see <https://orgmode.org/manual/Workflow-states.html>. `shaped` and `active` need action. `done`, `cut`, and `reshaped` do not. A slice moves to `## closed` when its status becomes terminal, and never moves back.

Split there rather than per status because the split has to pay for itself. Two sections keep ids ascending within each run, keep a status flip a one-line edit, and make only the one-way transition a move — which is the transition that already has a ceremony in this chapter. Five sections, one per status, would fragment the id order five ways and turn every status change into a move for no further gain.

Order the sections live work first because that is the order the reader's question is asked in. A reader opens this file to learn what is happening now, and the answer has to be at the top. The part that grows without bound is the part nobody opens the file for.

Which is the failure this format postpones rather than solves. `## closed` grows monotonically and `## in flight` does not, so on a long-lived project the status surface eventually violates the rule that it be read rather than skimmed — by arithmetic, not by bad writing. When it does, move `## closed` wholesale to `<project>/docs/plan/milestones-closed.md` and leave one link behind. That file is history, not a second status surface: a slice that leaves `milestones.md` is no longer part of what a reader consults to know where the work stands. It is the same one-way door [09 — Known Issues](./09-known-issues.md) opens when a resolved case collapses out of its hot directory.

`milestones.md` SHOULD derive whatever it can from the slices themselves so it cannot silently disagree with them. A status surface maintained by hand goes stale between the moment the work changes and the moment someone remembers.

The slice document carries no status of its own, deliberately. Two status surfaces disagree, and the one a reader did not open is the one that is wrong. A reader holding a slice finds its status one grep away in `milestones.md`.

Its two sections are a fixed shape and the project MUST pin them the same way, with the exact list `# Milestones`, `## in flight`, `## closed`. The pin is what stops the third section — a `## backlog`, a `## someday`, a per-status split — from arriving as a small helpful edit and turning the single status surface back into a plan. See [10 — Lean Markdown](./10-lean-markdown.md#pinning-a-fixed-heading-shape) for the mechanism; the [plan-zone template](./template-plan-zone.md) ships it. A project that has moved `## closed` out to `milestones-closed.md` drops that heading from its own array.

### `open-questions.md`

One block per question, with a stable id so a slice or a commit can reference it:

```text
## Q-003 — Does the rate limiter need to survive a restart?

Blocks: 007 acceptance line 2.
Raised: while shaping 007.
Exit: ADR, decision on persistence.
```

`Blocks` names what the question holds up and is mandatory; an entry that blocks nothing is a note, and notes belong in the drafts workspace. Every entry leaves by exactly one of three exits: it becomes an ADR, it becomes a line in the slice under `Revisions`, or it is recorded as measured and closed.

The register is a triage desk, not a queue. The failure mode it guards against is becoming a place discovery goes to be filed rather than acted on — a plan that always wins because the thing that would have changed it was moved to another document. If questions accumulate faster than they exit, the shaping is wrong, not the register.

## One directory per slice

A slice is one directory, always, whatever its size:

```text
<project>/docs/plan/slices/<id>-<slug>/
  README.md         Always. The entry document.
  tasks.md          Only when implementation will cross a context reset.
  requirements.md   Only when acceptance maps many-to-many onto tests.
```

`<id>` is a zero-padded sequential number, `001` onward, matching the `ADR-NNNN` and `KI-NNNN` schemes so ids read cleanly in commit messages and grep alike. Ids are never reused and never renumbered: a re-shaped slice takes the next free id rather than the old one, so the two remain separately addressable.

The directory is the default rather than an escalation because escalation has a cost of its own. A slice that starts as `slices/<id>-<slug>.md` and later needs a second file must be renamed, and the rename breaks every reference already pointing at it — the milestone line, the open questions, the commit messages. That happens exactly when the work is already in trouble, which is when a restructuring step is least likely to be taken. A directory that grows a file costs nothing and breaks nothing.

`README.md` is the entry document. The name is deliberate: forges render it when a reader opens the directory, so the human entry point and the agent entry point are the same file.

The additional files are gated, and the gates are prohibitions rather than permissions:

- `tasks.md` MUST NOT exist unless implementation will cross a context reset. Its job is durable state across a boundary that erases working memory. Inside a single session the ordered work is already in the session.
- `requirements.md` MUST NOT exist unless acceptance maps many-to-many onto tests, or spans more than one test lane, so a flat list in `README.md` can no longer be audited by reading it.
- `design.md` MUST NOT exist. Current subsystem design is owned by the explanation zone; see [03 — Subsystem Pages](./03-subsystem-pages.md).

State them this way because a slice directory looks like an invitation to fill it. Tools trained on other spec-driven workflows will produce a full set of files unprompted, and a positive rule does not survive that pull as well as a negative one.

The signal that the gates have failed is countable rather than felt: a run of slices whose `tasks.md` restates what `README.md` already said. Look for it during review, not per slice — one slice never looks like ceremony from the inside.

### `tasks.md`, when its gate is met

A flat ordered checklist and nothing else. One line per task, each a concrete action a session can finish and check off:

```text
- [x] Add the token bucket to `RateLimiter`.
- [x] Wire the 429 response path.
- [ ] Backfill `test_rate_limit_429`.
- [ ] Remove the temporary in-memory store.
```

It carries no goal, no scope, no acceptance criteria, and no rationale — `README.md` owns all four, and restating them is the failure signal above. It is working state, not a record: it is deleted with the slice's `done` transition rather than kept as history, because the commits are the history.

### `requirements.md`, when its gate is met

The `Acceptance` lines expanded to a table mapping each assertion to the tests that prove it, in the same EARS phrasing. It replaces the flat list in `README.md`; the two MUST NOT both carry acceptance.

## The slice document

`README.md` has a fixed heading list, and the project MUST pin it so it cannot drift into a second charter. The pin is an `MD043` heading array carried inside the document, opening with `*` because the H1 varies per slice; the mechanism is in [10 — Lean Markdown](./10-lean-markdown.md#pinning-a-fixed-heading-shape), and the [slice template](./template-slice.md) ships the comment already filled in. The headings:

```text
Goal          One sentence naming the observable outcome. Not the mechanism.
Appetite      The fixed budget, in the project's chosen unit. See chapter 06.
Core          The non-negotiable outcome this slice guarantees. Never cut.
In scope      The negotiable remainder, ordered so the least valuable is cut first.
Out of scope  Explicit no-gos for this slice.
Governed by   Every source a session must load, named individually.
Acceptance    One line per assertion, each naming the test that proves it.
Rabbit holes  Known traps, each with a pre-authorized escape.
Done when     The objective completion condition.
Revisions     One line per change to this document after the work started.
```

`Core` and `In scope` are separate headings because [06 — Appetite and Scope](./06-appetite-and-scope.md) requires the non-negotiable outcome to be declared apart from the remainder that funds it. Collapsing them into one scope list is the everything-is-core anti-pattern with better formatting.

`Out of scope` does more work than its length suggests. It is the only heading that constrains by subtraction, and it is what stops a session from helpfully building the adjacent thing.

Use the drop-in [slice template](./template-slice.md).

## Governed by is the context filter

An agent session loads `README.md` and the sources `Governed by` names. Nothing else. This is the concrete form of the one-entry-document rule in [04 — Agent Context](./04-agent-context.md), and it works because it names sources instead of describing them.

A `Governed by` entry that names a whole directory is a defect. If the session needs the directory, the slice is too large; if it needs three files in it, name the three. The general principle is that context is a finite budget, spent well by carrying lightweight identifiers and resolving them at load time rather than preloading everything that might matter; see <https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents>.

## Acceptance lines and EARS

Each `Acceptance` line states one assertion and names the test that proves it:

```text
When a client exceeds 5 login attempts in 60 seconds, the system shall respond 429.
  -> test_rate_limit_429
```

The assertions are phrased in EARS, the Easy Approach to Requirements Syntax — a constrained template for requirements, first published in 2009 by Alistair Mavin and colleagues at Rolls-Royce, and used at Airbus, Bosch, Dyson, Honeywell, Intel, NASA, Rolls-Royce and Siemens. Five patterns plus their combination:

| Pattern            | Template                                                                     |
| ------------------ | ---------------------------------------------------------------------------- |
| Ubiquitous         | The `<system>` shall `<response>`.                                           |
| State driven       | While `<precondition>`, the `<system>` shall `<response>`.                   |
| Event driven       | When `<trigger>`, the `<system>` shall `<response>`.                         |
| Optional feature   | Where `<feature is included>`, the `<system>` shall `<response>`.            |
| Unwanted behaviour | If `<trigger>`, then the `<system>` shall `<response>`.                      |
| Complex            | While `<precondition>`, when `<trigger>`, the `<system>` shall `<response>`. |

The value is that the opening keyword declares which kind of requirement follows before the content is read, and that the unwanted-behaviour pattern gives error cases a named slot instead of leaving them to be remembered. It is the same discipline as the uppercase keywords in [10 — Lean Markdown](./10-lean-markdown.md), one level up: normativity carried by a fixed vocabulary rather than by tone.

Two honest limits. EARS constrains phrasing, not correctness — a precisely phrased wrong requirement passes. And the requirement-to-test naming above is not part of EARS; the official notation says nothing about testability. It is borrowed from safety-critical traceability practice, and it carries that practice's failure mode: a named test that does not exist yet is a forward reference that goes stale silently when a test is renamed.

So a project that names tests in acceptance lines MUST also carry a hook that fails when a named test cannot be found. Without the hook, drop the naming and keep the assertions — an unenforced reference is worse than none, because it reads as verified.

## The pre-production gate

One line in the project's author-instructions file:

```text
Until the current slice is implemented, do not add a specification page and do not open an ADR
outside that slice. A question that arises goes to docs/plan/open-questions.md.
```

This is the circuit breaker on documentation itself. Without it a project specifies indefinitely, because specifying is cheaper than building and always feels productive. It is worth more than any choice about file layout.

The gate binds agents in particular. A session that hits an undecided question will decide it, write the record, and continue — producing a decision nobody made.

## A slice is a bet, not a contract

The slice document is committed before the work starts. Committed at the end it is a report; committed at the start it is the thing later commits are read against.

It is not frozen by being committed. Google's design-doc practice is explicit that a document should be updated when what it describes has not shipped yet, which is exactly a slice's condition for its whole life; see <https://www.industrialempathy.com/posts/design-docs-at-google/>. A plan that cannot absorb what implementation taught is a plan that quietly stops being read.

The revision rule is the same one [06 — Appetite and Scope](./06-appetite-and-scope.md) applies to the appetite. A change to `Goal`, `Core`, `Appetite`, or `Acceptance` after the work has started MUST be a committed edit that adds one line under `Revisions` naming what changed and what was learned that changed it. Cutting the remainder is not a revision; it is the designed response to a binding appetite and needs no ceremony beyond the commit that does it.

That keeps both properties at once. The plan can move, so it stays true; every movement is in a diff, so a project that routinely rewrites its slices mid-flight can see that it does. An unrecorded revision is the only kind that teaches nothing.

## When a slice ends

The directory stays where it is. It is the artifact later commits were read against, and deleting it removes the only record of what was promised before the work started.

Every ending moves the milestone line from `## in flight` to `## closed`, in the same commit that ends the work. What differs is the status it carries there.

- Finished: the line reads `done`, `tasks.md` is deleted if it existed, and the durable results migrate to the zones that own them — the design to a subsystem page, the choices to ADRs, exact values to reference. The plan keeps only the pointer.
- Cut: the line reads `cut` and the note names what was cut. The `In scope` list is left as written; it is the record of what was traded, and editing it after the fact erases that.
- Re-shaped: the line reads `reshaped` and names the successor id. The successor is a new directory with a new appetite; the old slice's `Revisions` carries one line saying the work was stopped uphill.

## Anti-patterns

- Slice as second charter: project-wide context restated in a unit of work. That is `charter.md`.
- Slice as design document: how a subsystem is built, written where what to build belongs. That is the explanation zone.
- Slice as decision record: a choice made in the slice instead of an ADR, so it is invisible to every future reader who does not read this slice.
- Directory filled by default: `tasks.md` and `requirements.md` created because the shape suggested them.
- `tasks.md` restating `README.md`: goal, scope, or acceptance copied into the checklist.
- `Governed by` naming a directory, a whole zone, or "the docs".
- Acceptance lines with no test named, or naming tests no hook verifies.
- Rabbit holes listed without escapes, which records a risk without doing anything about it.
- Silent revision: `Goal` or `Core` changes and `Revisions` does not.
- Status in two places: a `Status` heading in the slice competing with the milestone line.
- Open questions as an archive: entries that name nothing they block and never exit.
- Milestones maintained by hand until they disagree with the slices they summarize.
- A terminal status left in `## in flight`, or a slice listed in both sections.
- `## closed` grown past the point anyone scrolls it, so the live work is no longer what the file shows.

## Sources

- Shape Up, Write the Pitch (problem, appetite, solution, rabbit holes, no-gos): <https://basecamp.com/shapeup/1.5-chapter-06>
- EARS, official notation reference: <https://alistairmavin.com/ears/>
- Org-mode workflow states (the bar between states that need action and states that do not): <https://orgmode.org/manual/Workflow-states.html>
- Design docs at Google (write before code; update while unshipped): <https://www.industrialempathy.com/posts/design-docs-at-google/>
- Effective context engineering for AI agents (just-in-time context): <https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents>
- Amazon, working backwards (write the launch document first): <https://www.allthingsdistributed.com/2006/11/working_backwards.html>
