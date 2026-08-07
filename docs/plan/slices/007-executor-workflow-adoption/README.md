# 007 — Executor workflow adoption

## Goal

`executor-workflow` drives one real workflow through the conformance contract while retaining its gates.

## Appetite

3 implementation sessions. Chosen before the design below.

## Core

One executor entry point preserves plan-mode and context-brief gates end to end, leaving broad executor migration as remainder.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Add `executor-workflow` to input-fidelity and skill-class registries.
- Add workflow Markdown and both pre-commit file-pattern edits, including `workflow validate --all`.
- Route one real executor workflow through the accepted provider runner.
- Document the new surface. Documentation breadth is cut first.

## Out of scope

- Cutover of `oneshot`, `vetted`, or `prex`.
- Removal of existing executor skills or calibration evidence.

## Governed by

- `docs/plan/slices/006-provider-runners/README.md` — runner contract.
- `docs/decisions/ADR-0010-executor-preparation-and-artifacts.md` — executor stages and artifacts.
- `docs/decisions/ADR-0016-context-briefs-and-input-fidelity.md` — handoff contract.
- `docs/reference/skill-contract.md` — skill-class and gate rules.

## Acceptance

```text
When executor-workflow runs, the executor shall preserve the plan-mode and context-brief gates through one real workflow. -> test/integration/skills_claude.bats
When workflow sources change, pre-commit shall validate all workflow YAML and Markdown surfaces. -> test/integration/cmd_precommit_apply_template.bats
```

## Rabbit holes

- Adoption can become cutover — escape: keep every existing executor entry point intact.
- Two hook patterns can drift — escape: assert both exact patterns in focused tests.

## Done when

The new executor path and both validation hooks pass, existing executors remain intact, and milestone 007 flips to `done`.

## Revisions

None.
