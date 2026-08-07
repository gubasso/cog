# Open questions

Every entry names what it blocks and exits through an ADR, a slice revision, or a recorded measurement.

## Q-005 — Does `gc` belong in the curated terminal-contract map?

Blocks: nothing today; `terminal-contract` is opt-in, so leaving `gc` out fails nothing. Raised: the gc leanup, which gave `gc` its own inline commit path emitting `COMMIT_OK <sha>` directly rather than only aggregating a worker's line — the same shape the rule curates for `gc-repo`. Exit: an ADR or a recorded decision to add `gc` to the map in `lib/commands/cmd_skill_lint.sh`, `docs/reference/skill-contract.md`, and the `cmd_skill_lint.bats` fixtures, or to keep the map scoped to fresh-context workers only.

Q-001 through Q-004 all exited through [ADR-0023](../decisions/ADR-0023-select-workflow-engines-at-definition-or-call-site.md), [ADR-0024](../decisions/ADR-0024-pass-step-artifacts-by-directory.md), [ADR-0025](../decisions/ADR-0025-needs-is-the-only-edge-directive.md), and [ADR-0027](../decisions/ADR-0027-accept-the-workflow-engine.md).
