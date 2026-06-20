# Verdict & Severity Model

Shared enums for review verdicts, finding severity, and finding categories. Used by
`implementation-reviewer`, `refactor-migration-plan` (review mode), `plan-reviewer`, and
`review-code-deep` (via `llm-review-discipline.md`).

## Verdict Enum

The verdict is a single top-level status for a review report. Exactly one verdict per report.

| Verdict                    | Meaning                                                       |
| -------------------------- | ------------------------------------------------------------- |
| `APPROVED`                 | No blocking issues. Implementation matches the plan/contract. |
| `APPROVED_WITH_CONDITIONS` | Acceptable with listed follow-up items. None are blocking.    |
| `CHANGES_REQUIRED`         | Blocking issues found. Must be resolved before proceeding.    |
| `REJECTED`                 | Fundamental problems. Requires re-planning or re-design.      |

## Severity Levels

Per-finding severity. Ordered from most to least urgent.

| Severity   | Definition                                                              |
| ---------- | ----------------------------------------------------------------------- |
| `CRITICAL` | Immediate risk: data loss, security vulnerability, outage, corruption.  |
| `HIGH`     | Significant issue that will cause production problems if not addressed. |
| `MEDIUM`   | Quality/reliability concern: edge cases, performance degradation.       |
| `LOW`      | Code quality only. No runtime impact.                                   |
| `INFO`     | Observation or suggestion. Not a problem.                               |

## Finding Categories

Each finding is tagged with one primary category.

| Category          | Scope                                                 |
| ----------------- | ----------------------------------------------------- |
| `correctness`     | Logic errors, wrong behavior, missing edge cases.     |
| `security`        | Vulnerabilities, unsafe inputs, auth/authz gaps.      |
| `performance`     | Inefficiency, unnecessary allocations, scaling risks. |
| `reliability`     | Error handling, resilience, failure modes.            |
| `maintainability` | Readability, coupling, naming, structure.             |
| `compatibility`   | Breaking changes, API contracts, version constraints. |
