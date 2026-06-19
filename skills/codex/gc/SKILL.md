---
name: gc
description: >
  Delegates deterministic git mechanics to cog while preserving session-scope
  and hook-fix judgment in prose. Commits the work across every git repo the
  session touched (source repo plus any satellite/SoT docs repo). Use when the
  user says "gc", "commit", "commit this", "save changes", "stage and commit",
  or "commit and push".
---

# Commit changes

The shared mechanical contract is identical to the Claude `gc` skill.

**Multi-repo by default.** When this session changed files in more than one git repo
— a source repo plus a SoT docs repo, or an orchestrated run writing into a
satellite project — commit the work in **every** touched repo, not just the one the
shell sits in. The deterministic partition/stage/commit mechanics live in `cog`;
this skill stays a thin orchestrator.

## Non-negotiable rules

- Never commit unless the user explicitly asks to commit.
- Never mention AI, Claude, Codex, automation, assistance, or similar wording in
  commit messages.
- Never bypass hooks: no `--no-verify`, no `-n`, no `SKIP=...`, no hook removal,
  and no git config edits.
- Never use blanket staging. The only staging path goes through
  `cog gc-stage --session-files "$PATHS_FILE"` (per repo, with `--repo-root` in
  multi-repo mode).
- Do not touch live files outside the chosen session file list unless the user
  explicitly approves.
- Commit every repo the session worked in by default. Deviate only when `gc-plan`
  reports a surprise (a path in no git repo, an undeclared touched repo, or an
  invalid declared dir) — then STOP and ask the user. Never silently drop a
  touched repo.

## Cog Contract

Session files are written to a newline-delimited file of paths. In multi-repo mode
write **absolute** paths (they may span repos); `gc-plan` partitions them by owning
repo and converts to repo-relative per-repo path lists. Blank lines are ignored. NUL
bytes and empty sets are rejected by the helpers.

Mechanical commands:

```bash
cog gc-plan --session-files "$SESSION_FILES_FILE" [--repo <dir>]... [--repo-set <file>] --json
cog gc-stage --session-files "$PATHS_FILE" --repo-root "<root>" --json
cog gc-commit --message-file "$MESSAGE_FILE" --paths-file "$PATHS_FILE" --repo-root "<root>" --json
cog gc-classify-failure --log "$LOG_FILE" --json
cog gc-push --repo-root "<root>" --json
```

`--repo-root` makes `gc-stage`/`gc-commit`/`gc-push` target a specific repo without
`cd`. Omit it for a single-repo commit in the current directory's repo.

`gc-plan` emits:

```json
{
  "ok": true,
  "repos": [{"root": "/abs/repo", "paths": ["a"], "extra_dirty": ["b"]}],
  "undeclared_dirty": [{"root": "/abs/other", "paths": ["x"]}],
  "declared_no_change": ["/abs/declared-clean"],
  "escapes": ["/abs/path-in-no-repo"],
  "invalid_repos": ["/not/a/repo"],
  "surprises": ["undeclared-repo:/abs/other"]
}
```

`ok` is `false` only when there are `escapes` (paths in no git repo). A non-empty
`surprises` list means the safety scan wants you to ask the user before committing.
Pass `--repo <dir>` or `--repo-set <file>` for repos an orchestrator explicitly
declared; this turns the declared set into an allowlist. With no declared repos,
every touched repo is accepted and committed by default.

## Result Line Contract

Emit one canonical status line per committed repo via `cog msg`, as the trailing
block of the reply with nothing after it. In multi-repo mode each line carries a
free-form `repo=<root>` suffix; for a single repo omit the suffix so the line is
byte-identical to the legacy form:

```bash
cog msg ok commit "$SHA"                                 # COMMIT_OK <sha>
cog msg ok commit "$SHA repo=$ROOT"                      # COMMIT_OK <sha> repo=<root>
cog msg ok commit-push "$SHA repo=$ROOT"                 # COMMIT_PUSH_OK <sha> repo=<root>
cog msg failed commit "<reason> repo=$ROOT log=<path>"   # COMMIT_FAILED ...
cog msg failed commit-push "<reason> repo=$ROOT"         # COMMIT_PUSH_FAILED ...
```

The parent `/runner-queue` reads these via
`cog runner-queue-parse-commit`, which accepts one line per repo and fails
closed if any repo's line is `*_FAILED`.

## Workflow

1. Snapshot context using read-only commands: porcelain status, staged diff,
   unstaged diff, and recent log. This informs the session file list and the commit
   message draft.

2. Decide the session file list in prose. This remains judgment:
   - With `--all`/`-a`, include every dirty path the user asked to commit across the
     repos the session is responsible for.
   - Otherwise include only files this session created, modified, or the user
     explicitly named.
   - If the session made no code changes, do not fall back to all dirty files.
   - If a file contains mixed session and non-session changes, ask the user.

   Write the chosen paths to `$SESSION_FILES_FILE`, one per line. In multi-repo mode
   write **absolute** paths.

3. Partition and run the safety scan:

   ```bash
   cog gc-plan --session-files "$SESSION_FILES_FILE" [--repo <dir>]... [--repo-set <file>] --json
   ```

4. Safety branch:
   - If `.ok` is `false` (escapes): STOP. Report the paths that resolve to no git
     repo; do not commit anything.
   - If `.surprises` is non-empty: STOP and ask the user, naming the undeclared repos
     and any invalid declared dirs. Under `--all`/`-a`, instead of asking, seed
     `$SESSION_FILES_FILE` from each accepted repo's `extra_dirty` and re-run
     `gc-plan`.
   - Otherwise proceed.

5. For each repo object in `.repos`, in order:
   1. Write its `.paths` (repo-relative) to a per-repo `$PATHS_FILE`.
   2. `cog gc-stage --session-files "$PATHS_FILE" --repo-root "<root>" --json`.
      If `ok` is not `true`, stop and ask before committing.
   3. Draft the Conventional Commit message from **that** repo's staged diff,
      following its `committed.toml` if present. Write it to `$MESSAGE_FILE`.
   4. `cog gc-commit --message-file "$MESSAGE_FILE" --paths-file "$PATHS_FILE" --repo-root "<root>" --json`.
   5. If commit fails, classify the captured log and handle per the discipline below.
   6. If `--push`/`-p` is active, `cog gc-push --repo-root "<root>" --json`.

6. Emit one result line per committed repo (see the result line contract), with the
   `repo=` suffix in multi-repo mode and the bare line for a single repo. Emit
   exactly this trailing block and nothing after it.

### Per-Repo Failure Handling

For each repo, classify a commit failure:

```bash
cog gc-classify-failure --log "$LOG_FILE" --json
```

- `setup-missing`: hard-fail. Do not run git config or setup commands.
- `auto-fixer`: re-run `gc-stage` for that repo's session files and retry.
- `commit-message`: revise only the message, then retry.
- `content-fix`: inspect hook output and fix only reported issues in that repo's
  session files. If a hook wants files outside scope or a semantic change, ask.
- `stuck` or `unknown`: follow the progress-gate escalation and ask when no specific
  safe repair is clear.

For `push-hook`, fix reported hook issues with the same session-file discipline,
create a normal follow-up commit through `gc-commit`, and retry. For
`push-setup-missing` or `push-non-hook`, report the failure and stop.

A failure in one repo does not roll back commits already made in earlier repos. Report
each repo's actual outcome; the parent runner treats any `*_FAILED` line as a hard
fail.
