---
name: gc
description: >
  Delegates deterministic git mechanics to the cog CLI while preserving
  session-scope and hook-fix judgment in prose. Use when the user says "gc",
  "commit", "commit this", "save changes", "stage and commit", or "commit and
  push".
model: haiku
---

# Commit changes

The shared mechanical contract is identical to the Codex `gc` skill.

## Non-negotiable rules

- Never commit unless the user explicitly asks to commit.
- Never mention AI, Claude, Codex, automation, assistance, or similar wording in
  commit messages.
- Never bypass hooks: no `--no-verify`, no `-n`, no `SKIP=...`, no hook removal,
  and no git config edits.
- Never use blanket staging. The only staging path goes through
  `cog gc-stage --session-files "$SESSION_FILES_FILE"`.
- Do not touch live files outside the chosen session file list unless the user
  explicitly approves.

## Agent-helper contract

Session files are written to a newline-delimited file of repo-relative paths.
Blank lines are ignored. Absolute paths, `..` traversal, NUL bytes, and empty
sets are rejected by the helper.

Mechanical commands:

```bash
cog gc-stage --session-files "$SESSION_FILES_FILE" --json
cog gc-commit --message-file "$MESSAGE_FILE" --paths-file "$SESSION_FILES_FILE" --json
cog gc-classify-failure --log "$LOG_FILE" --json
cog gc-push --json
```

`gc-stage` emits:

```json
{
  "ok": true,
  "repo_root": "/absolute/path",
  "session_files": ["file"],
  "initial_staged": ["old"],
  "unstaged": ["old"],
  "staged": ["file"],
  "final_staged": ["file"],
  "mismatch": [],
  "commands": [{"action": "stage", "path": "file"}]
}
```

`gc-commit` emits:

```json
{
  "ok": true,
  "repo_root": "/absolute/path",
  "paths": ["file"],
  "sha": "abc1234",
  "log": "/absolute/path/to/log",
  "exit_code": 0
}
```

On commit failure, `ok` is `false`, `sha` is `null`, `log` points to the
captured combined stdout/stderr, and the command exits `1`.

`gc-classify-failure` emits:

```json
{
  "class": "content-fix",
  "reason": "hook reported content issues",
  "log": "/absolute/path",
  "matched": ["content-fix"],
  "retryable": true,
  "requires_judgment": true,
  "recommended_action": "fix reported issues in session files"
}
```

Class values are `setup-missing`, `auto-fixer`, `content-fix`,
`commit-message`, `push-hook`, `push-setup-missing`, `push-non-hook`, `stuck`,
and `unknown`. Setup-missing has highest precedence.

`gc-push` emits:

```json
{
  "ok": true,
  "repo_root": "/absolute/path",
  "sha": "abc1234",
  "log": "/absolute/path/to/log",
  "exit_code": 0,
  "failure_class": null,
  "reason": null
}
```

On push failure, `ok` is `false`, `failure_class` and `reason` are populated,
and the command exits `1`.

## Workflow

1. Read the branch and snapshot context using the helper-backed git snapshot
   commands or equivalent read-only commands: current branch, porcelain status,
   staged diff, unstaged diff, and recent log. Display the branch before any
   staging or commit attempt.

2. Decide the session file list in prose. This remains judgment:
   - With `--all`/`-a`, include every dirty path the user asked to commit.
   - Otherwise include only files this session created, modified, or the user
     explicitly named.
   - If the session made no code changes, do not fall back to all dirty files.
   - If a file contains mixed session and non-session changes, ask the user.

3. Write the exact session file list to `$SESSION_FILES_FILE`, one repo-relative
   path per line.

4. Reconcile staging through the helper:

   ```bash
   cog gc-stage --session-files "$SESSION_FILES_FILE" --json
   ```

   If `ok` is not `true`, stop and ask before committing.

5. Draft the Conventional Commit message from the staged diff. This remains
   judgment and must follow the repository's `committed.toml` if present.
   Write the approved message to `$MESSAGE_FILE`.

6. Apply branch confirmation policy in prose. Protected branches require user
   confirmation unless `--yes`/`-y` or the accepted aliases are active.

7. Commit through the helper:

   ```bash
   cog gc-commit --message-file "$MESSAGE_FILE" --paths-file "$SESSION_FILES_FILE" --json
   ```

8. If commit fails, classify the captured log:

   ```bash
   cog gc-classify-failure --log "$LOG_FILE" --json
   ```

   - `setup-missing`: hard-fail. Do not run git config or setup commands.
   - `auto-fixer`: re-run `gc-stage` for session files and retry.
   - `commit-message`: revise only the message, then retry.
   - `content-fix`: inspect hook output and fix only reported issues in session
     files. If a hook wants files outside scope or a semantic change, ask.
   - `stuck` or `unknown`: follow the progress-gate escalation and ask when no
     specific safe repair is clear.

9. If `--push`/`-p` is active, push through the helper:

   ```bash
   cog gc-push --json
   ```

   For `push-hook`, fix reported hook issues with the same session-file
   discipline, create a normal follow-up commit through `gc-commit`, and retry.
   For `push-setup-missing` or `push-non-hook`, report the failure and stop.

10. Build the final status line with `cog msg` so the grammar stays
    canonical, then emit that exact line — and nothing after it — as the last line
    of the reply. Pick the form that matches the outcome:

    ```bash
    cog msg ok commit "$SHA"                       # COMMIT_OK <sha>
    cog msg ok commit-push "$SHA"                  # COMMIT_PUSH_OK <sha>
    cog msg failed commit "<reason> log=<path>"    # COMMIT_FAILED <reason> log=<path>
    cog msg failed commit-push "<reason>"          # COMMIT_PUSH_FAILED <reason>
    ```

    Emit exactly one such line. The parent `/plan-queue-runner` reads it as the last
    non-empty line of this child's output, so nothing may follow it.
