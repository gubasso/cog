# 00 — Foundations

Documentation stays trustworthy when every durable fact has one owner. This chapter decides which artifact owns a fact, what wins when two artifacts disagree, and where rationale belongs when the right home is the code rather than a document. Every other chapter applies these rules to one artifact class.

## ARID

Avoid Repetition In Documentation. The principle is practical, not aesthetic: repeated facts drift, drift makes readers choose between conflicting pages, and once readers stop trusting the docs they return to chat logs, old issues, or guesswork.

ARID does not forbid short summaries. The test is disposability: if deleting a summary leaves the canonical fact intact and discoverable, it is a summary; if deleting it removes the only current statement of the rule, it has become a source of truth and belongs at the owning home.

## Placement

A durable fact gets exactly one home. Ask these questions in order and stop at the first yes.

```text
a durable fact needs a home
│
├─ does it bind every file in the project?
│    yes → the author-instructions file (CLAUDE.md or equivalent)
│
├─ is it why one option was chosen over others, at the time?
│    yes → docs/decisions/ADR-NNNN-<slug>.md            frozen
│
├─ is it how one subsystem is built today?
│    yes → docs/explanation/<subsystem>.md              living
│
├─ is it what the project builds next, and what bounds it?
│    yes → docs/plan/                                   perishable
│
├─ is it a sequence a reader follows to finish a task?
│    yes → docs/guides/<topic>/
│
├─ is it a value, field, symptom, or past case a reader looks up?
│    yes → docs/reference/<topic>/
│
├─ is it why this local code looks surprising?
│    yes → a load-bearing comment beside the code
│
└─ can a name, type, or test carry it instead?
     yes → the code. prose is the wrong home.
```

The four documentation zones and the plan zone are defined in [01 — Diataxis Zones](./01-diataxis-zones.md); this chapter decides which one a fact belongs to, and that chapter defines what each one promises its reader. It also decides where the docs root itself goes, which depends on whether the product is a codebase or the content tree.

Behavior contracts belong as close to execution as possible. A function name, type signature, schema, or test is stronger than prose because it participates in change. Documentation points readers at the contract and explains the surrounding context; a prose page is never the only place a required argument, status value, or invariant exists.

Generated material follows the same rule. Generated API docs, schemas, or digests can be useful entry points, but generation does not make them canonical unless the generator's source is the owner. Know whether readers should edit the generated output, the source file, or neither.

## Structure is owned by the filesystem

Directory structure is a durable fact and the filesystem already owns it. Index files — `README.md`, `CLAUDE.md`, `AGENTS.md`, and equivalents — explain what a directory is for: its purpose, domains, concepts, and rules. They do not reproduce a tree of every file and subdirectory. A pasted tree drifts the moment a file is added, renamed, or removed, and the stale copy then competes with the real structure.

When a listing genuinely aids discovery, give each entry a purpose, not a bare path. A line naming `./docker.md` as daemon setup and daily commands tells the reader why to open the file; a line carrying only the path restates what the directory listing already shows.

A tree describing a layout the reader should create in their own project is a specification, not a duplicated fact, and is allowed. A tree of a directory that already exists is a duplicated fact and is forbidden.

## Cross-link discipline

Write once. Link everywhere else. A cross-link names the reason to follow it: cleanup order is defined by ADR-`<number>`, accepted status values live in `<project>/docs/reference/<topic>/`. Avoid vague links such as "see docs" — a specific link tells future editors where to update the fact and tells agents which context to load.

Do not paste the same table into a guide, a reference page, and an ADR. Do not copy a rule from the author-instructions file into every chapter. Do not turn an agent digest into the canonical source; a digest is a map, and the chapters remain the territory.

Prefer relative links inside the project so files keep working across branches, forks, and local checkouts. Use absolute URLs only for outside sources, and prefer canonical documentation URLs that a link checker can verify.

## Precedence

When two files disagree, this ladder decides the owner:

- Project-wide editing rules beat chapter summaries.
- ADRs beat explanation pages for why a decision was made.
- Subsystem pages beat ADRs for what the design is now.
- Reference pages beat guides for exact values.
- Guides beat reference pages for task sequence.
- Code beats prose for current behavior.
- Load-bearing comments beat distant explanation for local invariants.
- Slice documents beat everything for what is being built next, and nothing for what is true.

The second and third rules are one rule seen from both sides, and the pair keeps either document from being edited into the other's job; see [02 — Lean ADRs](./02-lean-adrs.md) and [03 — Subsystem Pages](./03-subsystem-pages.md).

After choosing the owner, edit the non-owner to link to it. Do not leave both claims in place, and do not resolve a conflict by adding a third summary page — that hides the drift while preserving both stale claims. If the conflict reveals a changed decision, supersede the older ADR or add an `Amended by` pointer.

When ownership is ambiguous, choose the page whose readers suffer most if the fact is stale. Status values stale in reference break debugging. Decision rationale stale in an ADR breaks future design review. Task sequence stale in a guide breaks execution.

## Code and comments

Code is the source of truth for behavior. Documentation should not restate behavior the code can express with names, types, and structure, and comments are reserved for rationale that would disappear if it were not written next to the code.

The test is reader-centered: would removing this comment confuse a future reader? If yes, keep or improve it. If no, delete it or rename the code. It does not ask whether the comment is true or whether it was useful while writing. Ousterhout argues complexity drops when comments capture what is not obvious from code; Fowler's catalog treats a comment as a smell when it compensates for unclear names. Keep comments that explain why; remove comments that only narrate what. See <https://www.informit.com/articles/article.aspx?p=2952392&seqNum=24> and <https://martinfowler.com/bliki/CodeSmell.html>.

Use proximity as the placement rule. Rationale for one branch goes beside that branch; rationale for a module boundary goes in the module header; a project-wide rule goes in its owning doc, linked from the code only when local code would otherwise look surprising.

Keep comments that explain:

- Rationale for a surprising branch.
- Boundary conditions from an external system, such as a service that treats missing and empty values differently.
- Non-obvious invariants that must not be violated.
- A deliberate trade-off that looks wrong without context.
- A link to the ADR that owns a broader decision.

Good comments are short, stable, and falsifiable. A comment needing frequent edits because it mirrors code behavior belongs in a name, type, test, or reference table instead. "This is important" gives a maintainer nothing to check; "`<system>` rejects requests when the token is normalized twice" states a condition that can be verified.

Delete comments that restate the next line:

```python
# Bad: increments the retry count.
retry_count += 1
```

Rename code when the comment compensates for a vague name:

```python
# Bad: check if the operation can run now.
if ok(item):
    run(item)

# Better.
if command_window_allows(item):
    run(item)
```

Move reference material out of comments entirely. A status matrix belongs in `<project>/docs/reference/<topic>/`, leaving only the local invariant behind. For broader rationale, point at the owner rather than restating it:

```python
# ADR-<number>: cleanup runs after upload so retries can inspect artifacts.
cleanup_after_upload()
```

The comment explains why the local code shape is not accidental; the ADR owns the decision. When a comment and code disagree, trust neither blindly — read the owning ADR, reference page, tests, and current behavior, then update the non-owner.

Do not use comments as a parking lot for TODOs unless the project has an explicit policy for them. Open work belongs in the issue tracker, the backlog, or the plan zone.

## Sources

- Write the Docs, documentation principles: <https://www.writethedocs.org/guide/writing/docs-principles/>
- Ousterhout, comment purpose: <https://www.informit.com/articles/article.aspx?p=2952392&seqNum=24>
- Fowler, code smells: <https://martinfowler.com/bliki/CodeSmell.html>
