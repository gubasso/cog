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

A commit attempt failed and saved its full pre-commit report to a file. This worker
reads that report as the complete todo list and implements **every** reported fix in
one pass, so the orchestrator can retry the commit with all issues resolved at once.

## Inputs

- `--repo-root <dir>`: the repository whose commit failed.
- `--session-files <paths-file>`: newline-delimited repo-relative paths in scope for
  this commit. Fixes stay within this set.
- `--report <log>`: the saved failure report (full hook and git output).

The `--repo-root` and `--session-files` values you were invoked with are the literal
paths the commands below use as `$REPO_ROOT` and `$SESSION_FILES_FILE`; substitute those
literals directly. Shell state does not persist between Bash tool calls, so never rely
on `$REPO_ROOT` or `$SESSION_FILES_FILE` being live shell variables.

## Non-negotiable rules

- Fix every issue the report names in a single pass; address all failing hooks
  together rather than one per invocation.
- Stay within the session file scope. When a fix requires a file outside that scope,
  a semantic decision, or a content change the report does not pin down, record it as
  an out-of-scope item for the user instead of guessing.
- Never run `git commit`; the orchestrator owns the commit retry.
- Never bypass hooks: no `--no-verify`, no `-n`, no `SKIP=...`, no hook removal, and
  no git config edits.
- Never run history- or worktree-destroying git: no `git reset --hard`, no
  `git restore`/`git checkout` on worktree files, no `git clean`, and no hand-rolled
  content merges. If the tree reaches a state you cannot explain, STOP and record it
  as out-of-scope for the user — never surgery your way out.

## Workflow

1. Read the entire `--report` file. Enumerate each failing hook and every concrete
   issue it reports (hook ids, file/line references, linter messages, auto-fixer
   notices). This list is the full scope of work.

2. Implement all fixes across the session files:
   - For auto-fixer hooks (formatters that already rewrote files), no edit is needed
     beyond re-staging.
   - For content hooks (shellcheck, mypy, eslint, ruff, markdownlint, tests, and the
     like), apply the minimal edit that resolves each reported issue.
   - Group the work by file so every issue in a file is resolved together.

3. Re-stage the session files so the fixes enter the next commit attempt:

   ```bash
   cog gc-stage --session-files "$SESSION_FILES_FILE" --repo-root "$REPO_ROOT" --json
   ```

   If `ok` is not `true`, report the mismatch and stop.

4. Return a structured summary as the trailing block of the reply:
   - **Fixed**: the hooks and files addressed.
   - **Out of scope**: any reported issue left for the user, with the reason.

   When every reported issue is fixed and re-staged, the **Out of scope** section is
   empty and the orchestrator may retry the commit immediately.
