---
name: executor-doc-writeback
description: >
  Execute one documentation writeback from a structured-findings artifact to
  explicit canonical documentation paths, using gc for gated staging and commit.
argument-hint: "<findings-path> <doc-path>... --allow-repo <path>..."
model: opus
effort: medium
disable-model-invocation: true
allowed-tools: Bash Read Edit Skill Agent
---

<!-- trigger-tests: "executor-doc-writeback", "write findings back to docs", "update canonical docs from findings" -->

# Doc Writeback Executor

**Phase 0 — Plan-mode gate.** If Claude Code plan mode is active, STOP before any other work and follow `$(cog skill-refs path orchestration/plan-mode-gate.md)`.

Apply one structured-findings artifact to explicit canonical documentation paths, then use `gc` for the commit workflow. This skill is a write-capable entrypoint and gates plan mode before reading, editing, or delegating.

## Inputs

The invocation supplies:

- a structured-findings artifact path;
- one or more canonical documentation paths to update;
- an explicit allowlist for any documentation repository outside the current workspace;
- desired commit message guidance when the user has one.

If a path or allowlist is missing, ask one focused question before editing.

## Run Directory

Create scratch space:

```bash
cog rundir doc-writeback
```

Write the work report to `<RUN_DIR>/doc-writeback-report.md`. Keep scratch notes under `RUN_DIR`. Documentation edits go only to the explicit canonical paths.

## Workflow

1. Read the findings artifact and validate that each finding maps to a supplied documentation path.
2. Inspect each target document before editing.
3. Apply minimal documentation edits that internalize the findings.
4. Record edited paths, finding IDs, decisions, and unresolved items in the run report.
5. Invoke `gc` with the explicit path list and declared repository allowlist.
6. Preserve the trailing `COMMIT_*` block emitted by `gc` in the final response.

## Boundaries

Do not edit undocumented paths. Do not infer a documentation repository outside the allowlist. Use the findings contract and explicit paths as the input contract; do not depend on who produced the findings.

## Output

Return:

- updated documentation paths;
- run report path;
- unresolved findings;
- `gc` result and `COMMIT_*` block.
