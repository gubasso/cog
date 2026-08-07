---
name: gc-repo
description: >
  Commit one repository's declared session file set by following the shared
  commit routine: stage through cog, draft and lint a Conventional Commits
  message, run the fix-all round loop delegating hook fixes to a fresh worker,
  optionally push, and emit one canonical status line. Invoked as a
  fresh-context worker, not by the user.
model: opus
effort: low
argument-hint: "--repo-root <dir> --session-files <paths-file> --run-dir <dir> --result-file <file> [--push] [--multi-repo]"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Agent Grep Glob
---

<!-- trigger-tests: "gc-repo", "commit one repo's session files through cog", "stage draft and commit a single repository" -->

# Commit one repository

Commit exactly one repository's declared session files. A coordinator has already partitioned the session, resolved every scope question, and handed this worker a single repo plus its repo-relative paths. The commit routine itself is shared prose at `$(cog skill-refs path gc/commit-routine.md)`; this worker follows it in fresh context, delegates hook fixes, and emits one canonical status line.

## Inputs

- `--repo-root <dir>`: the repository to commit; the routine's `$REPO_ROOT`.
- `--session-files <paths-file>`: newline-delimited **repo-relative** paths in scope for this repo; the routine's `$PATHS_FILE`.
- `--run-dir <dir>`: this worker's scratch subdirectory; the routine's `$RUN_DIR`.
- `--result-file <file>`: the path the single canonical status line is written to (literal `$RESULT_FILE`).
- `--push`: run the routine's push step after a clean commit when present.
- `--multi-repo`: emit the `repo=<root>` suffix on the status line when present; without it, emit the bare single-repo form.

The values you were invoked with are the literal paths the commands use; substitute those literals directly. Shell state does not persist between Bash tool calls, so never rely on them being live shell variables.

## Non-negotiable rules

The routine's own rules bind here — no AI mentions in messages, no hook bypass, no raw `git commit`, no `git reset --hard` or other destructive git, fix the whole report at once, stay inside the session file scope. On top of them:

- This worker never asks the user. On any unresolved condition it fails closed with `COMMIT_FAILED` (or `COMMIT_PUSH_FAILED`) and stops.
- This worker did not make the changes it is committing, so it reads their meaning out of the staged diff. Where the routine calls for the caller's change context, the staged diff is it.

## Result Line Contract

<!-- cog-terminal-contract: COMMIT_OK -->

Emit exactly one canonical status line via `cog msg`, written to `$RESULT_FILE` **and** as the trailing block of the reply with nothing after it. With `--multi-repo` the line carries a free-form `repo=<root>` suffix; without it, emit the bare single-repo form:

```bash
cog msg ok commit "$SHA"                                 # COMMIT_OK <sha>   (single-repo)
cog msg ok commit "$SHA repo=$ROOT"                      # COMMIT_OK <sha> repo=<root>   (multi-repo)
cog msg ok commit-push "$SHA repo=$ROOT"                 # COMMIT_PUSH_OK <sha> repo=<root>
cog msg failed commit "<reason> repo=$ROOT log=<path>"   # COMMIT_FAILED ...
cog msg failed commit-push "<reason> repo=$ROOT"         # COMMIT_PUSH_FAILED ...
```

A coordinator reads these via `cog runner-commit-parse`, which fails closed if the line is `*_FAILED`.

## Workflow

1. Follow the routine at `$(cog skill-refs path gc/commit-routine.md)` end to end, delegating every hook report per **Delegated fix** below.

2. Map the routine's outcome to the status line: `ok <sha>` → `COMMIT_OK`, `push-ok <sha>` → `COMMIT_PUSH_OK`, a push failure → `COMMIT_PUSH_FAILED <reason>`, and every other failure outcome (`stage`, `mixed-file`, a terminal class, `stuck`, `out-of-scope`) → `COMMIT_FAILED <outcome>` carrying the report path as `log=<path>` when one exists.

3. Write that one line to `$RESULT_FILE` and emit it as the trailing block, with the `repo=<root>` suffix when `--multi-repo` is present.

## Delegated fix

The routine's **Fixing a hook report** step is delegated, never done in this context: this worker holds no session history, and hook churn would crowd out the commit it is here to land.

For `auto-fixer`, `content-fix`, and `push-hook`, delegate the remediation to a fresh-context Claude worker through the Agent tool (`subagent_type: general-purpose`), never the Skill tool. The prompt tells the worker to read `$HOME/.claude/skills/gc-hook-fix/SKILL.md` and follow it, passing `--repo-root "$REPO_ROOT"`, `--session-files "$PATHS_FILE"`, and `--report "$ROUND_LOG"` (this round's `gc-commit` `.log` path). The worker fixes every reported issue at once within the session file scope and re-stages. On return, retry the commit; if it reports out-of-scope items, stop at the routine's `out-of-scope` outcome.
