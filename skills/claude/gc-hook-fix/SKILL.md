---
name: gc-hook-fix
description: >
  Read a commit's full pre-commit failure report and implement every reported
  fix at once across all failing hooks, within the session file scope, then
  re-stage through cog. Returns a structured summary for the commit orchestrator
  to retry the commit. Invoked as a fresh-context worker, not by the user.
model: opus
effort: low
argument-hint: "--repo-root <dir> --session-files <paths-file> --report <log>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Grep Glob
---

<!-- trigger-tests: "gc-hook-fix", "fix all pre-commit failures from this report", "remediate the failing hooks for this commit" -->

# Fix commit hook failures

A commit attempt failed and saved its full pre-commit report to a file. This worker reads that report as the complete todo list and implements **every** reported fix in one pass, so the orchestrator can retry the commit with all issues resolved at once.

## Inputs

- `--repo-root <dir>`: the repository whose commit failed.
- `--session-files <paths-file>`: newline-delimited repo-relative paths in scope for this commit. Fixes stay within this set.
- `--report <log>`: the saved failure report (full hook and git output).

The `--repo-root` and `--session-files` values you were invoked with are the literal paths the commands below use as `$REPO_ROOT` and `$SESSION_FILES_FILE`; substitute those literals directly. Shell state does not persist between Bash tool calls, so never rely on `$REPO_ROOT` or `$SESSION_FILES_FILE` being live shell variables.

## Non-negotiable rules

The remediation itself — read the whole report, resolve every issue in one pass grouped by file, auto-fixers need only re-staging, stay inside the session file scope, then re-stage through `cog gc-stage` — is the **Fixing a hook report** step of the shared routine at `$(cog skill-refs path gc/commit-routine.md)`. Follow it there; that file is the source of truth. Its surrounding rules bind here too: no hook bypass, no raw `git commit`, and no `git reset --hard` or other history- or worktree-destroying git. On top of them:

- Never run `git commit`; the orchestrator owns the commit retry. This worker fixes and re-stages, nothing else.
- An out-of-scope item is recorded for the user, never guessed. If the tree reaches a state you cannot explain, STOP and record that as out-of-scope too.

## Workflow

1. Perform the routine's **Fixing a hook report** step against `--report`, with `$PATHS_FILE` bound to the `--session-files` path you were invoked with:

   ```bash
   cog gc-stage --session-files "$SESSION_FILES_FILE" --repo-root "$REPO_ROOT" --json
   ```

   If the re-stage does not report `ok`, report the mismatch and stop.

2. Return a structured summary as the trailing block of the reply:
   - **Fixed**: the hooks and files addressed.
   - **Out of scope**: any reported issue left for the user, with the reason.

   When every reported issue is fixed and re-staged, the **Out of scope** section is empty and the orchestrator may retry the commit immediately.
