# Round 1: review-code-deep stage-4 contract

> Plan: review-deep-loop-refactor | Round: 1 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

`skills/claude/review-code-deep/SKILL.md` already exposes an Orchestrator Invocation Contract: given
two absolute paths (`<context-path> <output-path>`), it forces JSON, runs Phases 0–3, validates with
`cog review-validate-findings`, writes the JSON, and replies `WROTE <output-path>`. This is exactly
what prex Stage 4 invokes. Make the stage-4 use first-class and DRY so `executor-prex` delegates to it.

## Previous Rounds

None (first round).

## Scope of This Round

**IN scope:**

- Refactor `skills/claude/review-code-deep/SKILL.md` (and the Codex twin
  `skills/codex/review-code-deep/SKILL.md`) to be the canonical stage-4 implementation-review skill,
  inspired by prex Stage 4: make the JSON-findings-for-orchestrator-triage contract explicit; confirm
  the two-abs-path Orchestrator Invocation Contract and the stable findings schema (severity, file,
  line range, category, headline, evidence, reasoning, suggestion, confidence). Keep Phase-0 mechanics
  in the existing `cog review-init`/`review-scope`/`classify-project`/`review-cli-signals`/
  `review-refs`/`review-validate-findings` commands.
- Decide where plan-conformance lives: prex Stage 4 currently does a separate plan-conformance pass in
  the orchestrator. Have `review-code-deep` accept (via its context-path input) the reviewed plan and
  surface plan-conformance findings, so prex does not duplicate that logic in prose. Keep it review-only
  (no edits; the orchestrator-mode write to `<output-path>` is the only write).
- Run `cog skill-lint` on both skills.

**OUT of scope:**

- `review-loop` (Rounds 2–3).
- The prex Stage 4 rewire (owned by `executor-prex-refactor`).

## Deterministic vs Probabilistic

- Deterministic (cog): the existing `cog review-*` Phase-0 + findings validation (unchanged unless a
  new routine surfaces).
- Judgment: the review itself; how plan-conformance findings are framed.

## Validation

- `cog skill-lint` green on both; the orchestrator contract still emits valid findings JSON validated
  by `cog review-validate-findings`. If any `cog review-*` command changes, sync its surfaces + bats.
  `just lint` + `just test` green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
