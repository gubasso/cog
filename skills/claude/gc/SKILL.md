---
name: gc
description: >
  Delegates deterministic git mechanics to the cog CLI while preserving
  session-scope and hook-fix judgment in prose. Commits the work across every
  git repo the session touched (source repo plus any satellite/SoT docs repo).
  Use when the user says "gc", "commit", "commit this", "save changes", "stage
  and commit", or "commit and push".
model: haiku
---

<!-- trigger-tests: "gc", "commit", "commit this", "save changes", "stage and commit", "commit and push" -->

# Commit changes

The shared mechanical contract is identical to the Codex `gc` skill.

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
cog gc-commit-lint --message-file "$MESSAGE_FILE" [--repo-root "<root>"] --json
cog gc-commit --message-file "$MESSAGE_FILE" --paths-file "$PATHS_FILE" --repo-root "<root>" --json
cog gc-classify-failure --log "$LOG_FILE" --json
cog gc-loop-progress --current "$LOG_FILE" --previous "$PREV_LOG_FILE" --json
cog gc-push --repo-root "<root>" --json
```

`gc-commit` carries a `lint` object in its JSON (`{ok, deferred, linter, config,
violations}`) from the pre-flight Conventional Commits gate; see "Commit message
format".

`gc-loop-progress` diffs two consecutive round reports and emits
`{new, recurring, resolved, churn_ratio, counts}` keyed on failing-hook (or
failure-class) signatures. It is the deterministic signal for the stuck-loop
judgment in the round loop below.

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

## Commit message format

Every commit message is a Conventional Commit: `type(scope): description`.

- **type**: one of `feat, fix, docs, style, refactor, perf, test, build, ci, chore,
  revert`.
- **scope** (optional, encouraged): a noun naming the area changed; may be
  hierarchical, e.g. `module/sub-module`, `theme/sub-theme`.
- **description**: imperative, lowercase, no trailing period; keep the subject ≤ 72
  chars and put detail in the body after one blank line.
- **breaking change**: add `!` before the colon (`feat(api)!: ...`) and/or a
  `BREAKING CHANGE:` footer.

`cog gc-commit-lint` checks this deterministically and `gc-commit` enforces it as a
pre-flight gate. When the repo runs its own commit-message linter the check reports
`deferred: true`; that linter prevails, so follow the project's rules.

## Result Line Contract

Emit one canonical status line per committed repo via `cog msg`, as the trailing
block of the reply with nothing after it. In multi-repo mode each line carries a
free-form `repo=<root>` suffix; for a single repo omit the suffix so the line is
the canonical single-repo form:

```bash
cog msg ok commit "$SHA"                                 # COMMIT_OK <sha>
cog msg ok commit "$SHA repo=$ROOT"                      # COMMIT_OK <sha> repo=<root>
cog msg ok commit-push "$SHA repo=$ROOT"                 # COMMIT_PUSH_OK <sha> repo=<root>
cog msg failed commit "<reason> repo=$ROOT log=<path>"   # COMMIT_FAILED ...
cog msg failed commit-push "<reason> repo=$ROOT"         # COMMIT_PUSH_FAILED ...
```

Parent runners read these via
`cog runner-commit-parse`, which accepts one line per repo and fails
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
   3. Draft the commit message from **that** repo's staged diff in the format under
      "Commit message format", and write it to `$MESSAGE_FILE`. Validate it with
      `cog gc-commit-lint --message-file "$MESSAGE_FILE" --repo-root "<root>" --json`;
      if `ok` is `false` and `deferred` is `false`, revise per `violations` and
      re-lint before committing.
   4. Run the commit round loop below until that repo commits clean or the loop stops.
   5. If `--push`/`-p` is active, `cog gc-push --repo-root "<root>" --json`.

6. Emit one result line per committed repo (see the result line contract), with the
   `repo=` suffix in multi-repo mode and the bare line for a single repo. Emit
   exactly this trailing block and nothing after it.

### Per-Repo Commit Round Loop

Each repo commits through a bounded round loop. Every round fixes the **whole** report
at once, then retries — never one error per round.

Round R:

1. Attempt the commit:

   ```bash
   cog gc-commit --message-file "$MESSAGE_FILE" --paths-file "$PATHS_FILE" --repo-root "<root>" --json
   ```

   `gc-commit` saves the full hook and git output to the file named by its `.log`;
   that file is round R's report. Keep the previous round's `.log` as `$PREV_LOG_FILE`.

2. If `ok` is `true`, the repo is committed. Leave the round loop and emit its result
   line.

3. Otherwise classify the report:

   ```bash
   cog gc-classify-failure --log "$LOG_FILE" --json
   ```

   - `commit-message` (and any `gc-commit` pre-flight `lint`-only failure where
     `git commit` was not attempted): revise the message per `lint.violations` and
     retry. This stays in this loop; it needs no fix worker.
   - `auto-fixer` or `content-fix`: delegate the fixes to a fresh opus worker, then
     re-stage and retry (round R+1). See "Delegated fix".
   - `push-hook`: delegate the fixes the same way, create a normal follow-up commit
     through `gc-commit`, and retry.
   - `setup-missing`, `push-setup-missing`, `push-non-hook`: report the failure and
     stop; do not run git config or setup commands.

4. Stuck check. Before retrying into round 4 and every round after, compare the two
   most recent reports:

   ```bash
   cog gc-loop-progress --current "$LOG_FILE" --previous "$PREV_LOG_FILE" --json
   ```

   When `recurring` holds the same signatures with `resolved` empty and `churn_ratio`
   at or near `0`, the loop is stuck. Redirect to a better path: broaden the fix scope,
   address the root cause the earlier rounds skirted, or take on a class the loop kept
   deferring, then re-delegate with that framing. If a redirected round still leaves
   the same `recurring` signatures with no progress, stop and emit `COMMIT_FAILED` with
   the recurring signatures and the round-log paths.

### Delegated fix

For `auto-fixer`, `content-fix`, and `push-hook`, delegate the remediation to a
fresh-context Claude worker through the Agent tool (`subagent_type: general-purpose`),
never the Skill tool. The prompt tells the worker to read
`$HOME/.claude/skills/gc-hook-fix/SKILL.md` and follow it, passing the repo root, the
repo's session `$PATHS_FILE`, and the failure report (`$LOG_FILE`). The worker fixes
every reported issue at once within the session file scope and re-stages. On return,
retry the commit; address any out-of-scope items it reports with the user.

A failure in one repo does not roll back commits already made in earlier repos. Report
each repo's actual outcome; the parent runner treats any `*_FAILED` line as a hard
fail.
