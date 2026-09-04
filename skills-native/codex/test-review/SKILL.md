---
name: test-review
description: >
  Execute the REFACTOR_PLAN.md produced by the Claude test-review planner in safe batches, updating
  tests only, verifying after each batch, and writing POST_REFACTOR_REPORT.md. Mechanical runner,
  batch, lint-signal, and manifest updates delegate to cog.
---

# `test-review` (Codex)

This skill preserves the live Codex skill contract: the plan is law, only approved test files may be edited, and every batch must either pass verification or be rolled back before stopping.

## Helper Delegation

Use `cog test-review-discover --repo-root "$TARGET_ROOT" --manifest "$MANIFEST"
--plan "$PLAN" --json` before applying work and before resuming. It supplies the detected test runner, task counts, and next batch proposal using the live rule of at most five tasks and no file boundary crossing.

Use `cog test-review-manifest --manifest "$MANIFEST" --update <json-file> --json` after each batch and during final reporting. The helper only touches `.phase`, `.implementation-log`, `.tooling.delta`, and `.final-summary`.

Use `cog test-review-lint --repo-root "$TARGET_ROOT" --scope <touched-tests> --json` only as a post-change signal check when a task's change spec is ambiguous. Do not invent tasks from lint signals.

## Batch Rules

Parse `REFACTOR_PLAN.md`, verify target files and line ranges, and apply tasks in order. Before a task marked `requires-user-confirm`, `security-sensitive`, or `coverage-risk`, stop for the required human gate.

After each batch, run the detected project test command. On failure, roll back every file touched by the batch using the user-approved rollback approach for the session, record the failure output in `MANIFEST.yaml`, and stop. On success, record the implementation-log entry and continue.

## Judgment That Stays In Prose

Rollback decisions, snapshot approval, deletion approval, characterization-test preservation, minimal-diff application, and final report interpretation remain agent judgment. The helper provides deterministic state and YAML updates only.
