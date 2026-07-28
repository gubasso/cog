# ADR-0043: Best-Constructed Input Standard

## Context and Problem Statement

ADR-0035 required delegated briefs to carry the original request **verbatim and in full** and never summarize. In practice the best input for a worker is not a raw transcript: a real session accumulates context, decisions, research, findings, and often a generated plan, and a prompt like "given this context, implement this" depends on all of it. A verbatim-only mandate blocks the well-oriented summarization that makes input clear, while still risking lost substance. We want one unified standard that maximizes the _quality_ of input every skill receives.

## Considered Options

- Keep ADR-0035's verbatim-and-in-full rule unchanged.
- Replace it with a summary-only standard.
- Replace it with a best-constructed standard: oriented summary + raw request attached + full substantive context and artifacts, kept unbiased.

## Decision Outcome

Chosen option: **A best-constructed standard** — every input-builder produces a brief that leads with a well-oriented Objective (crafted from the whole session), attaches the raw request verbatim as cheap insurance, and carries the full substance (decisions, research, findings) and artifacts (e.g. a generated session plan) that bear on the task. Summarize narrative for clarity, but never drop substantive content to be terse; reference large or external artifacts by path. The coordinator's own verdict stays omitted for bias isolation.

This **supersedes ADR-0035**. The structural shape is the v2 context-brief contract (`skill-refs/orchestration/context-brief-contract.md`); `cog context-brief build --request` injects the raw request mechanically. The `input-fidelity` lint marker and rule keep their names for stability; their meaning is now _fidelity to intent and substance_, not verbatim copying.

## Consequences

- Good: workers get clear, well-oriented input that still carries full session substance and artifacts.
- Good: the raw request is always attached, so summarization cannot silently drop a requirement.
- Good: one unified standard across every input-builder.
- Bad: brief quality now depends on good summarization judgment, not a mechanical verbatim copy.
- Bad: the `input-fidelity` name no longer literally describes "verbatim" (documented here).

## Status

Implemented — supersedes [ADR-0035](./0035-input-fidelity-enrichment-only-briefs.md). Enacted by `lib/commands/cmd_context_brief.sh`, `lib/functions/fn_context_brief.sh`, `skill-refs/orchestration/context-brief-contract.md`, and the input-fidelity skills.
