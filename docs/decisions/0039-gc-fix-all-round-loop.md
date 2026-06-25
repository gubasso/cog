# ADR-0039: gc Drives a Fix-All-at-Once Commit Round Loop With a Delegated opus@low Fixer

## Context and Problem Statement

The `gc` skill described commit-failure handling one failure class at a time, with no
explicit round loop and no deterministic stuck-loop detection. When pre-commit reports
many issues across several hooks, fixing one error per retry is slow and can loop
forever on an unsolvable case. The fixing was also done by `gc` itself, which is pinned
to `model: haiku` for cheap orchestration — too thin for multi-hook fix triage.

## Considered Options

- Keep per-class handling; let the model eyeball logs to judge "stuck".
- Add a deterministic cross-round diff in cog and keep all fixing inline on haiku.
- Add the cross-round diff **and** extract the expensive fix work to an opus@low worker
  that `gc` delegates to, keeping `gc` on haiku.

## Decision Outcome

Chosen option: **deterministic round-diff in cog plus a delegated opus@low fixer.**
`gc` runs a bounded per-repo round loop: each round attempts the commit (whose full
report `gc-commit` already saves to a file), fixes the *whole* report at once, then
retries. `cog gc-loop-progress` diffs two consecutive reports on failing-hook (or
failure-class) signatures and emits `new/recurring/resolved/churn_ratio/counts`,
mirroring `cog review-loop-progress`; the stuck/redirect/stop *decision* stays prose.
`gc` stays `model: haiku` and delegates `auto-fixer`/`content-fix`/`push-hook`
remediation to the new Claude-only `gc-hook-fix` worker (`model: opus`, `effort: low`)
through the Agent tool. The Codex `gc` twin shares the identical cog mechanical contract
but fixes inline, since Codex is a single capable engine with no haiku→opus split.

## Consequences

- Good: maximum issues fixed per round; deterministic stuck detection; cheap haiku
  orchestration with expensive reasoning isolated to a fresh opus@low context.
- Good: the round-diff reuses the established `review-loop-progress` pattern.
- Bad: one more cog command and one Claude-only worker skill to maintain; the twins now
  diverge in their fix step (delegation vs inline), an accepted platform difference.

## Status

Implemented. `lib/commands/cmd_gc_loop_progress.sh` and `cog::fn::git_loop_progress`
(`lib/functions/fn_git.sh`); `skills/claude/gc-hook-fix/SKILL.md`; the round loop in
`skills/claude/gc/SKILL.md` and `skills/codex/gc/SKILL.md`.
