# 99 — Checklist

The pre-merge gate for a documentation diff. Every box is answerable yes or no from the diff or from a command; a box that only restates a path is not here, because the diff already shows the path. This file is derived — it may restate a rule in test form, but it never owns one, and it carries no rationale, definitions, or citations. If a box and its owning chapter disagree, the chapter wins.

## Ownership

Owner: [00 — Foundations](./00-foundations.md).

- [ ] Every durable fact touched by the change has exactly one owner, and the reviewer can name it.
- [ ] No file restates a fact another file owns; non-owners link instead.
- [ ] Cross-links name the reason to follow them, and no index replicates a directory tree.
- [ ] The current design of a subsystem is in `<project>/docs/explanation/<subsystem>.md`, not spread across decision records; see [03 — Subsystem Pages](./03-subsystem-pages.md).
- [ ] Comments added with the change are load-bearing, and behavior contracts are carried by names, types, and tests where they can be.

## Placement

Owner: [01 — Diataxis Zones](./01-diataxis-zones.md).

- [ ] The docs root matches the project's product: `docs/` for a codebase, `_docs/` for a knowledge base, and nothing that is product content sits under it.
- [ ] Each file has one primary reader need and lives in the matching zone. Plan-zone documents are exempt: they may carry intent, scope, and status together.
- [ ] Operational material is zone-first: runbooks and setup in guides, diagnostics and case studies in reference, never a topic directory beside the zones.
- [ ] Binding forward-looking material lives in `<project>/docs/plan/`, not in the drafts workspace.
- [ ] The root docs README is still an index.

## Decisions

Owner: [02 — Lean ADRs](./02-lean-adrs.md).

- [ ] The decision cleared the threshold: cross-cutting, hard to reverse, constraining, or rejecting a plausible alternative. A run of ADRs on one area means a subsystem page is missing.
- [ ] The filename carries the `ADR-` prefix and a slug: `ADR-<number>-<decision>.md`. Templates and index files in the decisions directory carry no prefix.
- [ ] The filled body is at or below 350 words and uses the five template sections.
- [ ] Exactly one `Status`, from `Ideation`, `Proposed`, `Accepted`, `Implemented`, `Deprecated`, `Superseded`, `Rejected`.
- [ ] Implemented records link what enacts them; superseded link the successor; deprecated say why they stopped applying; rejected explain enough to prevent repeated debate.
- [ ] A record changed only in part keeps its status and carries an `Amended by ADR-NNNN` line.
- [ ] No accepted or implemented decision was deleted, and none was rewritten to describe the present.
- [ ] Supporting data too large for the record lives in reference or explanation and is linked.

## Drafts

Owner: [05 — Drafts and Promotion](./05-drafts-and-promotion.md).

- [ ] Drafts stay outside `<project>/docs/`, and no draft is the only home for a real decision.
- [ ] Promotion rewrote the draft into one zone rather than moving it, and removed temporary reasoning.
- [ ] The draft is deleted or remains clearly local and ignored.

## Plan and slices

Owners: [06 — Appetite and Scope](./06-appetite-and-scope.md) and [07 — Plan and Slices](./07-plan-and-slices.md).

- [ ] The unit of work names an appetite fixed before the design, in the project's one chosen unit.
- [ ] It declares a non-negotiable core apart from a negotiable remainder, and the core leaves room to cut inside the appetite.
- [ ] It is one directory under `<project>/docs/plan/slices/` with `README.md` as the entry document, committed before the work started, using the fixed heading list.
- [ ] `tasks.md` exists only because implementation crosses a context reset and restates nothing from `README.md`; `requirements.md` only because acceptance is many-to-many onto tests; no `design.md` exists.
- [ ] `Governed by` names individual files and records, never a directory, a zone, or "the docs".
- [ ] Acceptance lines are EARS-phrased and each names a test, and a hook fails when a named test cannot be found — or the naming was dropped.
- [ ] Every rabbit hole carries a pre-authorized escape rather than only a warning.
- [ ] Any change to `Goal`, `Core`, `Appetite`, or `Acceptance` after the work started is a committed edit with a `Revisions` line saying what was learned; any appetite change also cites the condition met and what was cut first.
- [ ] No unit of work was brought inside its appetite by dropping tests, review, or a security control.
- [ ] Status lives only in `milestones.md`, using the closed vocabulary, and open-questions entries name what they block.
- [ ] `milestones.md` puts live work first: every terminal status sits under `## closed`, every slice appears in exactly one section, and `## closed` is still short enough to scroll.
- [ ] The slice `README.md` and `milestones.md` each have a heading shape under `.markdownlint/`, and a new section was added by amending that array rather than by removing the shape from the hook.

## Agent readiness

Owner: [04 — Agent Context](./04-agent-context.md).

- [ ] Filenames and headings expose purpose from search results, without opening the file.
- [ ] The author-instructions file does not contradict the docs and stays under 200 lines.
- [ ] Any `AGENTS.md` digest summarizes source files only and introduces no new guidance.
- [ ] Work in flight has one entry document naming the sources a session should load.

## Reference artifacts

Owners: [08 — Tracking and Revalidation](./08-tracking-and-revalidation.md) and [09 — Known Issues](./09-known-issues.md).

- [ ] Perishable facts have an owner, a cadence, and an up-to-date `last_checked` entry.
- [ ] A bug in an external system under test is a case under `<project>/docs/reference/known-issues/` with a stable id, the expected skeleton, and a registry row that matches the directory.
- [ ] Any temporary mask carries a revert trigger and checklist, and the code site references the id; a resolved case is collapsed to one summary.

## Markdown

Owner: [10 — Lean Markdown](./10-lean-markdown.md).

- [ ] The file contains no bold and no italics.
- [ ] Identifiers, paths, flags, commands, and status values are inline code.
- [ ] Binding requirements use uppercase RFC 8174 keywords, and only in normative documents.
- [ ] Every fenced code block declares a language; use `text` when none applies.
- [ ] No paragraph is doing a heading's job.
- [ ] Any exception carries an `<!-- allow-emphasis: <reason> -->` comment.
- [ ] Every fixed shape has exactly one `MD043` array, in its own file under `.markdownlint/`, and no free-form document is gated by one.
- [ ] One hook entry names that file and selects the documents it applies to; an array no hook reads is decoration, so the shape was proven to fail before it was trusted.
- [ ] The project config does not mention `MD043` at any value, including `false`, which would override every shape while the hooks stay green.
- [ ] A project with repository-invariant tests gates that absence and the hook-to-shape wiring there, rather than trusting a checklist for two failures the linter reports as success.
- [ ] No document carries a `markdownlint-configure-file` comment.

## Verification

- [ ] Cross-links pass the project's link-check hook, and relative links resolve.
- [ ] Spelling and markdown hooks pass.
- [ ] Project-agnostic docs use `<angle>` placeholders for project-specific names.
- [ ] Any generated digest was regenerated from its sources.
