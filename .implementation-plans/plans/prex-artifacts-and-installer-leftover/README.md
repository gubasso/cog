# Fix `/prex` artifacts, stale skill-name refs, and self-cleaning installer

> Complexity: M | Rounds: 1 | Generated: 2026-06-22T19:44:56Z | Repo: /workspaces/cog

## Problem Statement

`cog` migrated `/prex` → `/executor-prex`, and ADR-0018 then removed `/prex` entirely (no alias, no compatibility form). A later mechanical replace turned the surviving `/prex` compatibility-language into `/executor-prex`, producing self-referential nonsense like "`/executor-prex` is supported only as an alias for `/executor-prex`" — false statements implying a deleted compatibility layer.

Separately, the orchestration skill was renamed `plan-queue-runner` → `runner-queue`. Several `skill-refs/` docs still name the old skill, and one pre-rename copy is still deployed at `~/.claude/skills/plan-queue-runner/` carrying the old `/prex` text. The root cause of that leftover is that `install.sh` overlays user-home skills without pruning files a previous version shipped but the current one does not.

The repo is functionally correct — nothing live invokes `/prex`. This is a documentation-truth, deployed-artifact, and installer-hygiene fix.

## Strategy

A single `/executor-prex` round: (1) delete three self-referential prose clauses in two `SKILL.md` files; (2) rename five stale `plan-queue-runner` references in `skill-refs/` to `runner-queue`; (3) remove the existing deployed orphan; (4) make `install.sh` self-cleaning by extracting shared bootstrap helpers into `install-common.sh` and adding a manifest-diff stale-prune. The work is one cohesive cleanup, so it is not split.

## Rounds

1. `apply-fixes.md` — prose artifact removal, skill-refs renames, orphan deletion, and self-cleaning installer (shared helper + manifest-diff prune), with lint and a disposable-prefix install test.

## Execution Commands

```bash
# Execute the next todo round (executor reads queue-rounds.yaml, runs the first todo round, then stops):
/executor-prex -ar @.implementation-plans/plans/prex-artifacts-and-installer-leftover/

# Or target the round file directly:
/executor-prex -ar .implementation-plans/plans/prex-artifacts-and-installer-leftover/apply-fixes.md
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for a single `/executor-prex` session. Do not implement multiple rounds in one session.

When `/executor-prex` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh `/executor-prex` session is launched for any subsequent round.

## Decisions & Constraints

- **Executor: executor-prex (EF 1.5).** Rounds sized for a full `/executor-prex` run.
- **Delete, don't reword, the alias/compat clauses.** Per ADR-0018 there is no `/prex` alias or compatibility form, and per ADR-0019 skill prose is lean and positive — the correct canonical statement is simply the `/executor-prex` sentence with the dead clause removed.
- **Rename all five `plan-queue-runner` refs in `skill-refs/`, including the dated 2026-06-17 line** (user-approved). Only the skill token changes; the date stays.
- **Installer uses a shared helper file** (user-approved) so the install-time prune and uninstall use one identical `valid_manifest_path` safety implementation rather than two copies that can drift.
- **Prune by manifest diff** = old-manifest − new-manifest, validated to cog-owned roots. This never touches user-authored files (never recorded in a manifest).
- **The orphan needs an explicit one-time `rm`** because the current manifest no longer lists `plan-queue-runner`; the diff-prune fixes future recurrences, not this pre-existing orphan.
- ADRs `0007-*` and `0018-*` keep their historical `/prex` / `plan-queue-runner` mentions — accepted ADRs are never rewritten.
- No git operations; committing is a separate `/gc` step.

## Rejected Alternatives

- **Reword the alias clauses to describe `/executor-prex` positively** — rejected: there is nothing to describe; the clause's only content was the now-nonexistent `/prex` compatibility relationship.
- **Hard-clear the user-home skill roots in `install.sh` like the app payload** — rejected: those roots may hold user-authored skills; a blanket `rm -rf` would destroy user content. The manifest-diff prune removes only cog-owned files.
- **Inline-duplicate the prune helpers into `install.sh`** — rejected by the user in favor of a shared `install-common.sh`, so install-prune and uninstall share one safety implementation.
- **Rely on the self-cleaning installer to remove the existing orphan** — rejected: the orphan is not in the current manifest, so the diff-prune cannot see it; an explicit one-time delete is required.

## Risks & Edge Cases

- **Prune deletes a cog-owned file a user hand-edited in place** when that file is renamed/removed upstream. This is the intended contract (cog-owned paths belong to cog); user-authored _new_ files are always safe because they are never in a manifest. Mitigated by the disposable-prefix test that asserts the user/cog boundary.
- **`comm` requires sorted inputs.** Both inputs are sorted (`$manifest_tmp.sorted` already; old manifest re-sorted defensively). Accepted.
- **Sourcing path resolution** must work when the scripts are invoked from any CWD; resolve via `BASH_SOURCE`/`repo_root`, not a relative path.

## Completion

When the round is done, set `apply-fixes` to `done` in this plan's `queue-rounds.yaml` and set this plan `done` in the top-level `.implementation-plans/queue-plans.yaml`. Nothing moves on disk.
