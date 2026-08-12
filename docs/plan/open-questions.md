# Open questions

Every entry names what it blocks and exits through an ADR, a slice revision, or a recorded measurement.

## Q-005 — Does `gc` belong in the curated terminal-contract map?

Blocks: nothing today; `terminal-contract` is opt-in, so leaving `gc` out fails nothing. Raised: the gc leanup, which gave `gc` its own inline commit path emitting `COMMIT_OK <sha>` directly rather than only aggregating a worker's line — the same shape the rule curates for `gc-repo`. Exit: an ADR or a recorded decision to add `gc` to the map in `lib/commands/cmd_skill_lint.sh`, `docs/reference/skill-contract.md`, and the `cmd_skill_lint.bats` fixtures, or to keep the map scoped to fresh-context workers only.

## Q-006 — Should `cog executor prepare-step` gain an `inline` lane and a host dimension?

Blocks: nothing today; the two Claude-hosted single-executor twins no longer call the resolver, and its remaining consumers still receive correct lanes for their own hosts. Raised: the single-executor leanup, which moved the Claude-side plan producer and plan reviewer in-session — so `(executor-oneshot, claude, needs-plan)` and `(executor-oneshot, codex, good-input)` still resolve to `"lane":"agent"` for work that is now inline. The underlying limitation is that the `(executor, engine, route)` key is host-blind: it cannot express that the same producer runs inline on one host and as a fresh context on another. Exit: an ADR or a recorded decision either to add the host dimension plus an `inline` lane across `lib/functions/fn_executor.sh`, `lib/commands/cmd_executor.sh`, `test/integration/cmd_executor.bats`, and `docs/reference/cli-commands.md`, or to move lane ownership out of the CLI entirely and leave it to skill prose.

Q-001 through Q-004 all exited through [ADR-0023](../decisions/ADR-0023-select-workflow-engines-at-definition-or-call-site.md), [ADR-0024](../decisions/ADR-0024-pass-step-artifacts-by-directory.md), [ADR-0025](../decisions/ADR-0025-needs-is-the-only-edge-directive.md), and [ADR-0027](../decisions/ADR-0027-accept-the-workflow-engine.md).
