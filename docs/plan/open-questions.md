# Open questions

Every entry names what it blocks and exits through an ADR, a slice revision, or a recorded measurement.

## Q-005 — Does `gc` belong in the curated terminal-contract map?

Blocks: nothing today; `terminal-contract` is opt-in, so leaving `gc` out fails nothing. Raised: the gc leanup, which gave `gc` its own inline commit path emitting `COMMIT_OK <sha>` directly rather than only aggregating a worker's line — the same shape the rule curates for `gc-repo`. Exit: an ADR or a recorded decision to add `gc` to the map in `lib/commands/cmd_skill_lint.sh`, `docs/reference/skill-contract.md`, and the `cmd_skill_lint.bats` fixtures, or to keep the map scoped to fresh-context workers only.

## Q-008 — Should a plugin be able to contribute skills, skill-refs, or `data/` tables?

Blocks: nothing today; slice 013 shipped the command seam only, and a plugin ships its resources under its own name. Raised: shaping that slice, where composing resource roots looked adjacent to composing commands and turned out not to be. `cog::fn::data_root` and `cog::fn::skill_refs_root` are first-hit-wins whole-root replacement rather than merge, `cog::fn::data::load_dir` makes one malformed file fatal for an entire merged table, and mirror-mode install deletes anything cog did not ship inside a mirrored tree — so admitting third-party content bundles namespace ownership, install safety, and precedence into one undesigned mechanism. Exit: an ADR that designs a distinct plugin-owned root the installer's mirror cannot reach, or a recorded decision that resource composition stays closed and plugins keep their resources under their own name.

Q-001 through Q-004 were workflow-engine questions. They exited through ADR-0023, ADR-0024, ADR-0025, and ADR-0027, all of which were removed on 2026-08-14 when the engine returned to its defining phase. Those exits no longer bind, and they never will here: the design left cog for [ripwork](https://github.com/gubasso/ripwork), which re-decided each of those questions from scratch under its own numbering. Cog carries no workflow engine and has no open question about one.

Q-007 asked how a Codex host reaches Claude for cross-engine work. It exited through slice 012 [cross-engine-claude-runner](./slices/012-cross-engine-claude-runner/README.md): `cog claude-runner` is the lane, the Codex `executor-oneshot` `good-input` route is a real cross-engine review again, and the record it feeds is an observation — `cog executor summary --prepare-engine` lets the twin that knows its own host declare it, which the `(executor, engine, route)` key never could.

Q-006 asked whether `cog executor prepare-step` should gain an `inline` lane and a host dimension, or whether lane ownership should leave the CLI. It exited the second way: `prepare-step` no longer reports a lane (`cog.executor.prepare-step.v2`), because the same producer runs inline on one host and forked on another, and a fork chosen for bias isolation rather than engine mismatch is judgment no lookup key can express. The rule now lives in prose as the inline-by-default pattern in `skill-refs/orchestration/orchestration-patterns.md`.
