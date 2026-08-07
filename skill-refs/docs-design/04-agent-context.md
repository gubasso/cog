# 04 — Agent Context

LLM agents consume documentation differently from humans, but they suffer from the same failure modes: unclear ownership, stale repetition, vague names, and oversized context. A docs system that is easy for a maintainer to navigate is usually easier for an agent to use. This chapter states the audience constraint that the process chapters after it build on.

## Context pollution

Documentation bloat is context pollution. Every duplicated rule, stale draft, and oversized ADR competes with source code, test output, and the user's current request. Agents do not need more text; they need the right text at the right path.

The cost is practical. The agent may miss the active rule because an older copy appears earlier in search results, may summarize a draft as if it were project state, or may spend tokens comparing two duplicated tables instead of editing the code. Agents also amplify stale docs: a human might notice a page is old from surrounding context, while an agent quotes it confidently when the path and heading look authoritative. That is another reason drafts stay out of shipped docs and superseded decisions link forward.

Lean docs help because they reduce retrieval ambiguity. Short documents are not automatically good, but focused ones are easier to retrieve and verify. The same logic appears in context-engineering work, where retrieval quality and context selection matter as much as raw model capacity; see <https://arxiv.org/html/2510.21413v1>.

## Semantic names

Names are retrieval hints. Use names that expose purpose before the file is opened: `ADR-<number>-<decision>.md`, `<task>-runbook.md`, `<topic>-diagnostics.md`, `<subsystem>-architecture.md`, `template-adr.md`. Avoid `notes.md`, `misc.md`, `new-plan.md`, and `final-v2.md`; they force humans and agents to inspect content and make search results noisy. Avoid local jokes, temporary codenames, and issue-only identifiers, which are meaningful during implementation and weak months later.

Headings matter too. Stable, direct headings such as `## Status values` and `## Verification` let agents skim and anchor edits. Use consistent vocabulary across files: if the project calls a document a runbook in one place and a recovery play in another, retrieval weakens.

## Entry points

An author-instructions file is the entry point for agents, whether the project calls it `CLAUDE.md`, `AGENTS.md`, or something else. It tells agents where documentation rules live and which docs are canonical, using the zone layout from [01 — Diataxis Zones](./01-diataxis-zones.md). When an agent asks where to edit, the entry point answers with ownership rather than prose volume: edit the ADR for why, the reference page for exact values, the guide for the task sequence.

Entry points should also say what not to do. The most useful negative rules are: do not duplicate facts, do not paste file trees, do not commit drafts into docs, and do not invent a new zone for one topic.

Do not let an agent digest become the source of truth. Digests summarize; chapters and project docs own the rules.

## Budget the always-loaded files

An author-instructions file is paid for on every session, whether or not it is relevant, so its length is a standing tax rather than a one-time cost. Keep the root file under 200 lines, and aim for 50 to 100; push detail into path-scoped files using the seam below. Anthropic's guidance sets the same bounds: <https://claude.com/blog/using-claude-md-files>.

Two habits keep it there: write each rule once and link rather than restate it, and keep the prose lean. A file paid for every session is the worst place for decorative formatting; see [10 — Lean Markdown](./10-lean-markdown.md).

## Modular author-instructions for large subtrees

Author-instruction files load eagerly and grow. When one accumulates rules that only matter inside a particular subtree, every session pays for that detail even while working elsewhere. The fix mirrors single-source-of-truth placement: move subtree-local rules into a nested author-instructions file scoped to where they are used.

- Move the subtree-local rules out of the root file into a nested one placed in that subtree; it becomes the single home for those rules.
- Bridge for the tool that reads only its own filename. Claude Code reads `CLAUDE.md`, not `AGENTS.md`, and lazy-loads a nested `CLAUDE.md` only when it touches a file in that subtree. A one-line `<subtree>/CLAUDE.md` containing `@AGENTS.md` forwards the nested rules — an import path resolves relative to the importing file, so the sibling is `@AGENTS.md`, not a repo-root path.
- Point, do not import, from root. An eager `@import` would pull the detail back into every session and defeat the split.
- Keep cross-cutting rules in root: anything that applies while editing code outside the subtree stays where every session sees it.

The caveat that decides what may move is that not every agent lazy-loads. Some `AGENTS.md`-native tools build their instruction chain eagerly from the repo root down to the working directory once at launch, so a nested file is invisible to a run started at the root. Move only rules used inside the subtree, and verify the active tool's loading behavior from its public documentation.

This targets the rules files and is orthogonal to the per-area digest role above, where an `AGENTS.md` is a derived map and never a rules home.

## One entry document per unit of work

A large documentation corpus cannot be loaded, and an agent told to "read the docs" will either truncate or drown. The fix is not a smaller corpus but a smaller entry: each unit of work has exactly one document naming the sources needed for it, so a session reads that document plus the files it names and nothing else.

```text
   a filter that names its sources        a filter that describes them

   session                                session
     │                                      │
     ▼                                      ▼
   plan/slices/007-rate-limit/README.md    "read the docs"
     │                                      │
     │  Governed by:                        ├─► docs/guides/**
     ├─► docs/explanation/auth.md           ├─► docs/reference/**
     └─► ADR-0031                           ├─► docs/decisions/**
                                            └─► docs/explanation/**
     3 files loaded
                                            truncate, or drown
```

That is the whole argument, and it is why the filter MUST name its sources rather than describe them. Where the entry document lives depends on the timescale. For work in flight it is the slice `README.md`, whose `Governed by` section is the filter; see [07 — Plan and Slices](./07-plan-and-slices.md). For a subsystem being maintained, the subsystem page plays the role; see [03 — Subsystem Pages](./03-subsystem-pages.md). Both work for the same reason.

## Maintenance instructions

Every project that expects agent help should carry a `## Documentation Maintenance` section in its author-instructions file. Copy [template-docs-rules.md](./template-docs-rules.md) rather than restating this shelf, then state local exceptions such as a different author-instructions filename or ADR numbering width. The `ADR-` filename prefix is not a local choice; see [02 — Lean ADRs](./02-lean-adrs.md). The section is project-specific by design; a pasted copy of a generic shelf is another always-loaded cost with no local information in it.

Agents should update docs only when the change affects durable behavior, operations, or decisions, not for every implementation detail. Small local rationale belongs in a load-bearing comment.

Finally, agents should report doc changes by ownership: which source of truth changed, which links were added, and which hooks passed. That report is easier to review than a broad claim that docs were updated.

## Sources

> Citation note: the research below includes 2025–2026 work that may postdate an LLM reviewer's training cutoff — e.g. `arXiv:2510.21413` ("Context Engineering for AI Agents in Open-Source Software", Mohsenimofidi et al.), verified real on 2026-06-15. Do not flag a citation as fabricated for being future-dated; fetch and verify first.

- Context engineering survey: <https://arxiv.org/html/2510.21413v1>
- Agent context guide: <https://mem0.ai/blog/context-engineering-ai-agents-guide>
- Anthropic on always-loaded instruction files: <https://claude.com/blog/using-claude-md-files>
