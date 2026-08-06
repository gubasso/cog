# 03 — Subsystem Pages

One explanation page per subsystem, `<project>/docs/explanation/<subsystem>.md`, owns that subsystem's current design. It is the explanation zone's load-bearing artifact rather than an optional extra: it is what [02 — Lean ADRs](./02-lean-adrs.md) points at when a run of decisions on one area shows a design document is missing, and what a slice's `Governed by` section names instead of listing eleven records.

## What the page holds

One to three pages: what the subsystem is, its components and boundaries, the constraints that currently hold, and one diagram when a diagram earns its place. It ends with an `Unresolved` list naming contradictions and gaps rather than deciding them — the value of writing two constraints on one page is that their conflict becomes visible before code exists.

Write the page when a subsystem exists and a unit of work would otherwise make a reader reconstruct it from the decision records. Do not create empty pages for subsystems that have not been built.

## Records freeze, descriptions stay live

The page is living and the decision records are not. That split is the settled convention in mature proposal systems: Python's PEP 1 states that once resolution is reached a PEP is a historical document rather than a living specification, with expected behavior documented in the language and library references instead, and Rust RFCs say accepted records should not be substantially changed.

Applied here, three artifacts each own one job:

- The subsystem page owns the current design. It is corrected in place whenever it stops being true.
- An ADR owns why one option was chosen over others, at the time it was chosen. It is never rewritten to match the present; it gains a status change or an amendment pointer instead.
- Code owns exact current behavior. The page describes shape and boundaries, not field lists.

So the page links the ADR that owns each choice, and the ADR does not have to be revisited when the design moves on. A reader who wants to know how the subsystem works reads one page; a reader who wants to know why it works that way follows one link.

Keeping both jobs in one document is what produces either a record that has lost its history or a page nobody trusts.

## Anti-patterns

- Subsystem page as decision record: a page that decides rather than describes leaves the choice invisible to everyone who does not open that subsystem, and leaves nothing to supersede when the choice is reversed.
- Page as field list: exact behavior belongs in the code, and exact values in reference; see [00 — Foundations](./00-foundations.md).
- Empty scaffold: a page created for a subsystem that does not exist yet, which readers then trust.

## Sources

- Python PEP 1, on a resolved PEP being a historical document rather than a living specification: <https://peps.python.org/pep-0001/>
- Rust RFC process, on not substantially changing accepted records: <https://github.com/rust-lang/rfcs>
