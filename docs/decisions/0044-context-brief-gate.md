# ADR-0044: Context-Brief Gate on Fresh-Context-Boundary Orchestrators

## Context and Problem Statement

[ADR-0043](0043-best-constructed-input-standard.md) defined the best-constructed input standard and
`cog context-brief build/validate`, but honoring it stayed a matter of prose: a delegator could
name-drop the contract and still hand a thin prompt to a fresh context. The repo already proves the
render → stamp → drift-lint loop for the plan-mode gate ([ADR-0037](0037-plan-mode-gate-canonical-render.md)).
The obligation "build a validated context brief for every fresh-context callee" needs the same
treatment: one canonical rule, injected, machine-enforced.

## Considered Options

- Keep the obligation in per-skill prose; lint only the `input-fidelity` marker (status quo, unenforced).
- A single byte-identical stamp like the plan-mode gate, plus a curated boundary set and dual lint.
- Fold the obligation into the existing `input-fidelity` rule (conflates two distinct concerns and sets).

## Decision Outcome

Chosen option: **a canonical context-brief gate stanza, stamped and drift-linted on every
fresh-context-boundary orchestrator, with a separate dual lint.** `cog context-brief gate render
--skill <name>` owns the wording (marker `<!-- cog-context-brief-gate -->`); the rule is the source of
truth, `cog context-brief` and the contract are the source of truth for the mechanics. The
`context-brief-gate` rule in `cog skill-lint` keys off a curated, **runtime-agnostic** boundary set
(Codex orchestrators included, unlike the Claude-only plan-mode gate) and requires BOTH the un-drifted
stanza AND a real `cog context-brief build`/`validate` call (build constructs the brief; validate
confirms a handoff or `/context-builder` brief). It forbids the marker on any skill outside the set. The boundary is "hands substantive planning/review/implementation work to a fresh
context." Read-only Q&A relays (`ask`), inline same-context chainers (`executor-vetted`,
`context-builder`), and verbatim transport runners (`runner-*`, `gc`) are deliberately out; the human
top-level operator orients the first skill directly and is exempt.

## Consequences

- Good: The obligation cannot drift or be name-dropped without honoring it; recursive down the chain.
- Good: Two source-of-truth split (rule vs. mechanics) avoids duplicated logic per skill.
- Bad: A new boundary orchestrator must be added to the curated set by hand (mirrors plan-mode gate).

## Status

Implemented

Enacted by `lib/functions/fn_skill.sh` (`cog::fn::skill::context_brief_gate_*`),
`lib/commands/cmd_context_brief.sh` (`gate render`), and the `context-brief-gate` rule in
`lib/commands/cmd_skill_lint.sh`. Builds on ADR-0043; mirrors ADR-0037.
