# ADR-0076: Empty-commit as a first-class runner/gc outcome

## Context and Problem Statement

A gate round changed only queue metadata, leaving the project tree clean. When the runner ran `/gc -a`
for that round there was nothing to commit, `git commit` failed on the empty tree, and the loop had to
be special-cased by hand to treat the failure as success. A round that legitimately produces no
committable change should complete cleanly, detected up front rather than by parsing a git failure.

## Considered Options

- Keep special-casing the empty round by hand in the orchestrator (what happened; brittle).
- Detect the empty tree by parsing `git commit`'s failure after the fan-out (late, per-repo, noisy).
- Detect emptiness in the one-shot `gc-plan` partition, before any commit worker spawns.

## Decision Outcome

Chosen option: **detect emptiness in `gc-plan`, carry a canonical marker.** `cog gc-plan` adds an
`empty` boolean computed from the partition: `true` when no accepted repo has a declared session path
that is actually dirty in git (committable = declared ∩ git-dirty). The `gc` coordinator checks
`.empty` in its safety branch, before the parallel fan-out; when true it emits the canonical trailing
line `COMMIT_OK empty` and returns without spawning any worker. `cog runner-commit-parse` recognizes
`COMMIT_OK empty`, reports `empty: true`, and no longer requires a per-repo `COMMIT_*` line in that
case. `runner-plan` treats `COMMIT_OK empty` as success, skips the commit, and proceeds to the
boundary.

## Consequences

- Good: an empty round completes deterministically with no hand special-case; emptiness is decided once,
  up front, not by interpreting a git error per repo.
- Bad: `empty` keys off declared-path dirtiness, so a session that declares only clean paths reads as
  empty even if unrelated undeclared paths are dirty — which is the intended "nothing this round
  declared changed" semantics, but must be understood as such.

## Status

Implemented — enacted in `lib/commands/cmd_gc_plan.sh`, `lib/commands/cmd_runner_commit_parse.sh`, and
the `gc`/`runner-plan` skills.
