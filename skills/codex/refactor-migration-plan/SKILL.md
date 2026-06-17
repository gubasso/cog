---
name: refactor-migration-plan
description: >
  Generate or review a migration/refactor plan from a source project into the current target
  project. Deterministic setup, source scanning, and drift checks delegate to cog; migration
  design remains prose. Use when the user says "refactor-migration-plan", "migration plan",
  "refactor plan", "port this project", or "rewrite plan from source".
---

# `refactor-migration-plan` (Codex)

This Codex twin preserves the live Codex twin contract: the artifact is the plan, not implementation
code. The source project is read-only and the target source tree is not edited by this skill.

## Helper Delegation

Use `cog refactor-setup` to parse arguments and resolve:

- `SOURCE_ROOT`
- `TARGET_ROOT`
- `PLAN_DIR`
- target language hint
- canonical guideline path and fallback state
- plan-dir collision state

Use `cog refactor-scan-source --source-root "$SOURCE_ROOT" --run-dir "$RUN_DIR" --json` to
produce the static source scan under `$RUN_DIR/source-scan/` and the baseline
`$RUN_DIR/scan-fingerprint.txt`.

Use `cog refactor-scan-drift --scan "$RUN_DIR/source-scan" [--expected "$EXPECTED"] --json`
for review-mode drift checks. This command must remain compatible with the manifest's recorded
`source.scan-fingerprint`; changing its recipe invalidates review drift detection.

## Judgment That Stays In Prose

Do not outsource migration design to helper output. The agent still decides the target architecture,
semantic gaps, phase boundaries, plan tasks, refusal-list findings, and review conclusions. Unknowns
must be written as `<TBD: ...>` with open questions.

## Guardrails

Never run source binaries without explicit approval. Never edit source or target implementation
files. If guideline resolution fails, stop with the helper's reason and the expected paths.
