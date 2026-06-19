# Skill taxonomy governance: the plan-* / review-* / executor-* / runner-* prefixes

> Complexity: M | Rounds: 3 | Generated: 2026-06-19 | Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Problem Statement

`cog` ships a growing family of Claude/Codex skills with no governing naming taxonomy. The user has
settled a four-prefix taxonomy that classifies every skill by what it does, and it must become a
recorded, lint-enforced governance contract that all later work names against:

- `plan-*` — emits implementation plans (e.g. `plan-writer`, `plan-writer-multi`, the new
  `plan-claude`, `plan-codex`).
- `review-*` — reviews code implementations against the codebase + the plan, AND plan-reviewers that
  review plans before concrete implementation (e.g. `review-code-deep`, `review-loop`,
  `review-findings`, the new `review-plan-claude`/`review-plan-codex`). `review-plan-*` is a
  sub-namespace of `review-*`.
- `executor-*` — executes one plan/prompt at a time; may accept a prompt OR an already-made plan, can
  generate its own better internal plan (review/organize/interview), then execute (e.g. the renamed
  `executor-prex`, the new `executor-claude`/`executor-codex-session`).
- `runner-*` — orchestrates executors over a structured queue, where each queue element carries the
  prompt that selects which executor runs it (e.g. `runner-queue`).

The legacy `plan-reviewer` name is inconsistent under this taxonomy: it reviews plans, so it belongs
in `review-plan-*`. `prex` must become `executor-prex`. This plan lands the governance backbone only;
the actual skill renames/creations happen in the dependent siblings (reconciliation via `depends_on`,
not duplication).

This extends — does not rewrite — the `review-*` rename already shipped by
`model-effort-policy-and-rename` (which renamed `plans-revision` → `review-implementation-plans`).
Accepted ADRs are never deleted; this is a new ADR.

## Strategy

Three dependency-ordered rounds, governance first so later siblings name skills against a stable
contract:

1. `taxonomy-adr-and-reference` — record the taxonomy as a new ADR and wire it into
   `docs/reference/skill-contract.md` + `AGENTS.md`/`CLAUDE.md`.
2. `skill-lint-taxonomy-rule` — teach `cog skill-lint` to enforce prefix→semantics deterministically,
   with grandfathering for the not-yet-renamed `prex`/`plan-reviewer` via a `superseded-by` marker.
3. `inventory-and-doc-sync` — refresh the skill-inventory reference, record the planned renames as
   migration notes, and sync command surfaces + run the gates.

## Rounds

1. `taxonomy-adr-and-reference.md` — new ADR + skill-contract + AGENTS/CLAUDE taxonomy rule.
2. `skill-lint-taxonomy-rule.md` — `cog skill-lint` `skill-prefix-taxonomy` rule + helper + bats.
3. `inventory-and-doc-sync.md` — inventory doc, migration notes, command-surface sync, gates.

## Execution Commands

```bash
# Execute the next todo round:
/prex -ar @.implementation-plans/plans/skill-taxonomy-governance/

# Or target a specific round file directly:
/prex -ar .implementation-plans/plans/skill-taxonomy-governance/taxonomy-adr-and-reference.md
```

## Execution Discipline

Rounds are executed one at a time. Each round is a self-contained unit for a single `/prex` session.
When `/prex` is pointed at this directory, it reads this plan's `queue-rounds.yaml`, runs the first
`todo` round, flips it `done`, and stops. Commit each round with `/gc -a` afterward (round bodies run
no git).

## Decisions & Constraints

- `Executor: prex (EF 1.5)`.
- The taxonomy is the backbone for the whole effort; this plan must land before the siblings that
  create/rename skills (`lean-plan-and-review-skills`, `review-deep-loop-refactor`,
  `executor-single-agent-wrappers`, `executor-prex-refactor` all `depends_on` it).
- Governance only: this plan does NOT create `/plan-claude`, `/plan-codex`, `/review-plan-*`, the
  executors, or rename any skill directory. It prepares naming, docs, lint, and inventory.
- Deterministic mechanics (the lint rule + classification helper) live in `cog`; the ADR/reference
  text is documentation. (ADR-0008, skill-contract.)
- Plan-mode gate (ADR-0015) is preserved as-is; the taxonomy rule is additive to skill-lint.
- Markdown fenced code blocks declare a language. Accepted ADRs are never deleted. Do not run git
  commands inside round bodies.

## Reconciliation (depends_on, no duplication)

- `depends_on: model-effort-policy-and-rename` (done) — that plan established the model/effort SoT and
  the `review-implementation-plans` rename; this plan's taxonomy generalizes that rename into the
  four-prefix rule rather than redoing it.
- The actual `plan-reviewer` → `review-plan-claude` retirement happens in `lean-plan-and-review-skills`
  (where the replacement is authored); the actual `prex` → `executor-prex` rename happens in
  `executor-prex-refactor`. This plan only records the decisions and grandfathers the legacy names in
  the lint rule until their replacements land.
