# 02 — Lean ADRs

Architecture decision records preserve why a project chose one path over serious alternatives. They are not tutorials, meeting notes, or design novels. A useful ADR is short, statused, and durable enough that future maintainers can trust it.

## When a choice earns an ADR

Write an ADR when at least one of these holds:

- The choice is cross-cutting: more than one area has to know about it.
- It is expensive to reverse once code depends on it.
- It constrains future work, so later decisions must be made inside it.
- It rejects a plausible alternative that someone will otherwise propose again.

Everything else belongs where the work is planned, or in the code and its tests. A choice that is local, obvious, and fully expressed by a type name or a function signature is not a decision record.

This threshold exists because the other rules here, applied without it, reward document count. The word cap says a record that will not fit should be split, and splitting is usually correct — but leanness enforced per file is unbounded in aggregate. A subsystem can be designed in 350-word installments across a dozen records, each individually clean, with no single artifact stating what the subsystem is, leaving a reader to reconstruct the design from the decisions.

The signal to watch is a run of consecutive ADRs about one area. When that appears, the missing artifact is a design document the decisions hang off, not another decision. That document is the subsystem page; see [03 — Subsystem Pages](./03-subsystem-pages.md). Writing it does not retire the decisions — it gives them somewhere to hang.

## Default template

Use the drop-in [ADR template](./template-adr.md). A filled ADR has five sections:

- `Context and Problem Statement`: the problem and why it matters.
- `Considered Options`: the serious alternatives, not every idea mentioned in chat.
- `Decision Outcome`: the chosen option and the shortest honest reason.
- `Consequences`: positive and negative trade-offs.
- `Status`: one canonical lifecycle value.

This is a MADR-minimal shape: enough structure to compare decisions consistently, not enough to invite filler. Do not add project-specific sections without an active, repeated need; if a field is consistently empty, remove it from the local template or stop creating ADRs for that class of choice.

Name files `ADR-<number>-<decision>.md` or the local equivalent. The number gives stable references in comments, reviews, and follow-up ADRs; the slug gives humans and agents enough context from filenames alone. Avoid status or date-only names. The title names the choice, not the implementation task: "Use `<system>` for artifact storage" records a decision, "Implement storage support" sounds like a ticket.

## Word cap

Filled ADR bodies MUST be at or below 350 words. The cap is a forcing function:

- One page is reviewable in code review.
- Short records are easy for agents to load and compare.
- A hard limit exposes decisions that should be split.
- The record stays focused on the durable choice, not the whole discovery trail.

If the record needs more room, first remove narrative detail; if it still needs more room, split the decision into a small series — one for storage format, one for API shape, one for migration behavior. The cap applies to the filled body, not to index pages or templates. Diagrams, large option matrices, benchmark data, exact API fields, and migration steps belong in reference or explanation, linked from the ADR, which says why those artifacts exist and which option they enact.

## Lifecycle

```text
   Ideation ──► Proposed ──► Accepted ──► Implemented
  (deletable)      │             │             │
                   │             └──────┬──────┘
                   ▼                    │
                Rejected                ├──► Superseded   a successor exists
           (backed away before          ├──► Deprecated   context evaporated,
            it was ever chosen)         │                 no successor
                                        └──► Rejected     explicitly not chosen

   never-delete applies from Proposed onward
   "Amended by ADR-NNNN — <what changed>" is a line under Status, not a state
```

Use exactly one status value per record:

- `Ideation`: captured while fresh; not binding, not yet ready for review, and deletable.
- `Proposed`: open for review.
- `Accepted`: chosen, not necessarily implemented.
- `Implemented`: enacted by the project.
- `Deprecated`: no longer applies; no successor exists.
- `Superseded`: replaced by a later ADR.
- `Rejected`: explicitly not chosen.

Every implemented ADR links the code, configuration, or documentation that enacts it when a stable target exists. Every superseded ADR links its successor. Every deprecated ADR says why it stopped applying. Every rejected ADR explains enough that the option is not reopened without new evidence.

Do not invent synonyms such as `Done`, `Canceled`, or `Obsolete`; synonyms make filtering and agent reasoning harder. Status is data — reviewers, scripts, and agents should be able to grep for `Status` and classify the decision without reading the file.

`Ideation` exists to make the vocabulary usable. A lifecycle whose lowest state already means "ready for review" has no low-commitment entry, so every idea either waits outside the record entirely or enters as a decision. The observable symptom is a corpus that is almost entirely `Accepted`, with no `Proposed` and no `Rejected` — not because the project never hesitated, but because hesitation had nowhere to live. Oxide's RFD process solves this the same way, with explicit ideation states and the rule that notes be timely rather than polished; see <https://rfd.shared.oxide.computer/rfd/0001>. Keep an ideation record short and honest about its own uncertainty; if it cannot yet name the options, it is a draft and belongs in the drafts workspace.

Status changes are edits to history, not rewrites of it. Moving to `Implemented` keeps the original context and outcome and adds the implementation link. Moving to `Superseded` adds a short pointer and stops there; the successor owns the new reasoning.

### Amendments: partial change without supersession

A later ADR often changes one aspect of a decision that otherwise stands — renames a command the old ADR describes, closes an item it deferred — without reversing it. Marking the old record `Superseded` would be false, but leaving it untouched misleads: a reader or agent loading it follows stale details as if current.

Handle this with an amendment pointer: keep the status, and add a line under `## Status` in the form `Amended by ADR-NNNN — <one line: what changed>`. Edit the old body only where its wording would actively mislead; never rewrite it to pretend the later design was the original choice. The amending ADR owns the new reasoning and names what it amends. `Amended by` is an annotation on a status, not a status value — the vocabulary stays closed.

## Never delete

Do not delete accepted, implemented, superseded, or rejected ADRs. They are project history, and deleting them makes old reviews, commits, and comments harder to understand.

Deletion is appropriate for drafts and for `Ideation` records, neither of which ever became project state. That is what makes the ideation state cheap enough to use: entering costs nothing and leaving costs nothing. Once a record reaches `Proposed`, change its status instead of removing it.

Never-delete does not mean never-correct — and it does not mean never-mislead. Fix typos, broken links, and misleading wording; correct metadata that was wrong when written. Do not edit an old ADR to pretend a later design was the original choice. An old ADR that reads as current when it is not is a trap for every future reader and agent.

This mirrors durable proposal systems — Rust RFCs, Python PEPs, and Kubernetes KEPs all preserve decision history because later readers need the trail, not just the latest state. Those systems draw a second line that matters as much: the record freezes and current truth lives elsewhere. An ADR left alone for two years is not stale; staleness is a property of documents that claim to describe the present, and an ADR does not. The living description is the subsystem page; see [03 — Subsystem Pages](./03-subsystem-pages.md).

## Comparisons

| Form         | Shape                                                       | Typical size | Use when                                         |
| ------------ | ----------------------------------------------------------- | ------------ | ------------------------------------------------ |
| Nygard       | Title, status, context, decision, consequences              | ~200 words   | The project has no need to list options.         |
| MADR-minimal | Adds considered options and keeps consequences visible      | ~250 words   | Review should show what was considered.          |
| Y-Statement  | One sentence: context, forces, choice, neglected, qualities | ~40 words    | A one-line reminder in an index or release note. |

The practical default is the lean MADR-minimal ADR: short enough for review, structured enough for future readers, explicit enough for agents to classify. Do not replace an ADR with a Y-Statement when the project needs status, consequences, or links to implementation.

## Anti-patterns

- ADR as tutorial: a decision record teaching the whole system instead of recording the choice.
- ADR rewritten to match the present: an accepted record edited until it describes the current design destroys the trail it existed to keep, and the subsystem page already owns that job.

## Sources

- Nygard ADR article: <https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions>
- MADR: <https://adr.github.io/madr/>
- MADR primer: <https://ozimmer.ch/practices/2022/11/22/MADRTemplatePrimer.html>
- Rust RFC process: <https://rust-lang.github.io/rfcs/0002-rfc-process.html>
- Kubernetes KEP process: <https://github.com/kubernetes/enhancements/blob/master/keps/sig-architecture/0000-kep-process/README.md>
