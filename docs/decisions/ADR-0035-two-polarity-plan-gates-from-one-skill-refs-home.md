# ADR-0035: Use two plan-gate polarities from one skill-refs home

## Context and Problem Statement

Skills that originate mutations of user-owned files, repositories, or services (`bootstrap`, `suckless-patcher`, `jira-ticket-creator`, `osc-obs`) had no shared pre-mutation gate, while `executor-*` skills already STOP on plan mode because their input plan is approved — and one skill cannot both stop on plan mode and enter it. Research recorded on the shelf (entries tagged `skill-authoring`) confirms that no frontmatter allowlist — portable spec or runtime extension — carries a gating field, so any gate must be prose, and prose shared across skills needs exactly one installed home.

## Considered Options

- Ad-hoc approval prose written per skill.
- A lint-stamped gate stanza checked by `cog skill-lint`.
- One shared plan-validate-execute source of truth with two declared polarities, resolved through skill-refs.

## Decision Outcome

Chosen option: `one shared source of truth with two declared polarities` — it reuses the mechanism the existing gates already trust and makes the polarity split explicit instead of accidental.

Plan-consuming skills keep the STOP directive in `skill-refs/orchestration/plan-mode-gate.md`; plan-originating mutators carry a byte-identical stanza pointing at `skill-refs/orchestration/plan-validate-execute-gate.md`: enter plan mode, present the ordered plan via `ExitPlanMode` (never pre-approved — approving it automatically is the same as having no gate), validate previews, execute one mutation at a time. `--no-plan` skips only the approval turn. Gates live on the user-launched entry layer; fresh-context workers never see plan mode; Codex skills are exempt. A skill that presents its complete artifact and waits for approve/abort (`cog-skill-creator`, `claudemd`) is a documented equivalent. The one-installed-home requirement is already satisfied by `skill-refs/` plus `cog skill-refs path` over the XDG data install; no new mechanism. The stanza stays deliberately unlinted, per the existing rule that a gate is a prose pointer to one skill-refs source of truth, not a stamped, lint-drift-checked stanza.

## Consequences

- Good: one protocol, no double-gating, no invented frontmatter, no new lint surface.
- Bad: polarity assignment is prose judgment, enforced only by the review checklist and `cog-skill-creator` rules.

## Status

Implemented. Enacted by [skill contract](../reference/skill-contract.md) and [plan-validate-execute gate](../../skill-refs/orchestration/plan-validate-execute-gate.md).
