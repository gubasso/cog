# ADR-0042: Context-Builder Shared Capability

## Context and Problem Statement

A delegated or forked worker does not inherit the orchestrator's conversation, so each brief-building
delegator (plan-multi, plan-writer-multi, review-plan-multi, review-loop, executor-prex) hand-rolled
its own enrichment-only brief inline, duplicating the same rules. There was no single source of truth
for the structural shape of a rich-context handoff, and no deterministic check that a brief was
complete. ADR-0035 fixed fidelity (verbatim, enrichment-only) but left the structure unspecified.

## Considered Options

- Keep brief construction fully inline per skill, duplicating the rules.
- A passive reference contract only, with no command or skill.
- A canonical `context-builder` skill plus a `cog context-brief` command and a general context-brief
  input convention.

## Decision Outcome

Chosen option: **A canonical `context-builder` skill plus a `cog context-brief` command and a general
context-brief input convention** — one SoT contract under `skill-refs/orchestration/`, deterministic
scaffold/build/validate in `cog`, and one inline-chained skill that any orchestrator reuses. The brief
section set and the best-constructed standard are defined by
[ADR-0043](0043-best-constructed-input-standard.md), which supersedes ADR-0035; this ADR complements
ADR-0025 and ADR-0026.

`review_loop_input.json` gains an optional `context` key as the review-loop bridge; the canonical
5-key envelope is unchanged when it is absent.

Context-building runs **inline in the caller's context** — the conversation lives in the orchestrator,
so it cannot be delegated to a blind subagent. No Codex twin exists yet (no Codex brief-building
coordinator needs one). A bespoke context-brief lint rule was considered and rejected: structural
conformance is a runtime property enforced by `cog context-brief validate` failing closed, and
fidelity reuses the existing `input-fidelity` marker.

## Consequences

- Good: one reviewable SoT for handoff structure; deterministic fail-closed validation.
- Good: the raw request is attached mechanically (`build --request`), not promised in prose.
- Bad: the curated `input-fidelity` set grows by two entries.
- Bad: the dual-engine coordinators adopt the contract by reference; full validated-brief assembly is
  wired only for review-loop's single-worker handoff.

## Status

Implemented — `lib/commands/cmd_context_brief.sh`, `lib/functions/fn_context_brief.sh`,
`skill-refs/orchestration/context-brief-contract.md`, `skills/claude/context-builder/SKILL.md`.
