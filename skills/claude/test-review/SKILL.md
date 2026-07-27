---
name: test-review
description: >
  Audit a project's tests against testing principles, classify anti-patterns, and produce
  .test-review/MANIFEST.yaml, TOOLING_REPORT.md, FINDINGS.md, and REFACTOR_PLAN.md. Mechanical
  discovery and lint signals delegate to cog; anti-pattern judgment and approval gates stay
  in prose.
model: opus
effort: low
---

<!-- trigger-tests: "test-review", "audit the tests", "test anti-patterns", "review the test suite" -->

# `test-review`

This skill preserves the live Claude skill contract: it is plan-only and writes only under the
target project's `.test-review/` directory. It never edits test source, never installs tooling, and
never proceeds from findings to a refactor plan without explicit approval.

## Helper Delegation

Use `cog` for deterministic mechanics:

1. Run `cog test-review-discover --repo-root "$TARGET_ROOT" --json` to collect test files,
   language signals, runner candidates, and any existing batch status.
2. Run `cog test-review-lint --repo-root "$TARGET_ROOT" [--scope "$SCOPE"] [--include-e2e]
   --json` to collect heuristic lint signals.
3. Use `cog test-review-manifest --manifest "$TARGET_ROOT/.test-review/MANIFEST.yaml"
   --update <json-file> --json` for deterministic updates to `.phase`, `.implementation-log`,
   `.tooling.delta`, and `.final-summary`.

The helper emits signals, not final review findings. The planner still reads the testing principles,
walks the anti-pattern catalog, decides whether each signal is a true finding, writes human-readable
reports, and enforces user gates.

## Workflow

Phase 0 resolves the principles file, creates `.test-review/`, records scope and discovery metadata,
and summarizes the target before deeper audit.

Phase 0.5 performs tooling inventory and optional web research — when it verifies an external tooling
or framework claim, it follows `$(cog skill-refs path research/primary-source-verification.md)`. Never
install dependencies; report setup snippets only.

Phase 1 interprets helper lint signals against the canonical anti-pattern guidance. Each finding
must include file, line, severity, principle citation, and suggested fix.

Phase 2 writes `FINDINGS.md` and stops for explicit approval: `approve`, `approve except <ids>`,
`defer <ids>`, or `abort`.

Phase 3 writes `REFACTOR_PLAN.md`, updates `MANIFEST.yaml`, and prints the Codex handoff prompt.

## Judgment That Stays In Prose

Anti-pattern classification, severity, false-positive handling, user approvals, tooling advice, and
the final task design remain agent judgment. `cog` only supplies deterministic discovery,
lint candidates, and manifest updates.
