---
name: gc-repo
description: >
  Commit one repository's declared session file set: stage through cog, draft
  and lint a Conventional Commits message, run the fix-all commit round loop
  delegating hook fixes to a fresh worker, optionally push, and emit one
  canonical status line. Invoked as a fresh-context worker, not by the user.
model: opus
effort: low
argument-hint: "--repo-root <dir> --session-files <paths-file> --run-dir <dir> --result-file <file> [--push] [--multi-repo]"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Agent Grep Glob
---

<!-- trigger-tests: "gc-repo", "commit one repo's session files through cog", "stage draft and commit a single repository" -->

# Commit one repository

Commit exactly one repository's declared session files. A coordinator has already partitioned the session, resolved every scope question, and handed this worker a single repo plus its repo-relative paths. This worker stages, drafts and lints a Conventional Commits message, runs the fix-all round loop until the repo commits clean, optionally pushes, and emits one canonical status line.

## Inputs

- `--repo-root <dir>`: the repository to commit. Every `cog gc-*` call passes `--repo-root "$REPO_ROOT"`.
- `--session-files <paths-file>`: newline-delimited **repo-relative** paths in scope for this repo (literal `$PATHS_FILE`).
- `--run-dir <dir>`: this worker's scratch subdirectory (literal `$RUN_DIR`); holds `message.txt`. The per-round hook report is not under `$RUN_DIR` — it is the path `cog gc-commit` returns in its `.log` field.
- `--result-file <file>`: the path the single canonical status line is written to (literal `$RESULT_FILE`).
- `--push`: push after a clean commit when present.
- `--multi-repo`: emit the `repo=<root>` suffix on the status line when present; without it, emit the bare single-repo form.

The values you were invoked with are the literal paths the commands below use as `$REPO_ROOT`, `$PATHS_FILE`, `$RUN_DIR`, and `$RESULT_FILE`; substitute those literals directly. Shell state does not persist between Bash tool calls, so never rely on them being live shell variables.

## Non-negotiable rules

- Never mention AI, Claude, Codex, automation, assistance, or similar wording in commit messages.
- Never bypass hooks: no `--no-verify`, no `-n`, no `SKIP=...`, no hook removal, and no git config edits.
- Never run `git commit` directly; commits go only through `cog gc-commit`.
- Never run history- or worktree-destroying git: no `git reset --hard`, no `git restore`/`git
  checkout` on worktree files, no `git clean`, and no hand-rolled content merges. If staging or commit reaches a tree state you cannot explain, STOP and emit `COMMIT_FAILED` — never surgery your way out.
- `cog gc-stage` is path-granular and stages whole files; it cannot isolate hunks in a file that mixes session and non-session changes.
- This worker never asks the user. On any unresolved condition it fails closed with `COMMIT_FAILED` (or `COMMIT_PUSH_FAILED`) and stops.

## Commit message format

Every commit message is a Conventional Commit: `type(scope): description`.

- **type**: one of `feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert`.
- **scope** (optional, encouraged): a lowercase noun naming the area changed. Prefer a hierarchical `scope/subscope`, e.g. `feat(auth/login): ...`; the subscope is optional, added only when the parent area is broad enough that a narrower part adds signal — otherwise a single scope (`feat(auth): ...`). Use lowercase kebab-case segments (`github-actions`), keep to ≤ 2 levels, and omit the scope entirely for genuinely cross-cutting changes (`chore: relicense`).
- **description**: imperative, lowercase, no trailing period; keep the subject ≤ 72 chars and put detail in the body after one blank line.
- **breaking change**: add `!` before the colon (`feat(api)!: ...`) and/or a `BREAKING CHANGE:` footer.

`cog gc-commit-lint` checks this deterministically and `gc-commit` enforces it as a pre-flight gate. When the repo runs its own commit-message linter the check reports `deferred: true`; that linter prevails, so follow the project's rules.

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

1. Stage the session files:

   ```bash
   cog gc-stage --session-files "$PATHS_FILE" --repo-root "$REPO_ROOT" --json
   ```

   If `ok` is not `true`, write and emit `COMMIT_FAILED stage repo=$ROOT log=<path>` and stop.

2. Materiality check. Review the staged diffstat — `git diff --cached --stat`, run as `git -C
   "$REPO_ROOT" diff --cached --stat`. If any staged file's churn is materially larger than the edit intended for it — a "one-line" file that staged dozens of lines — treat it as a mixed file `gc-stage` cannot split: write and emit `COMMIT_FAILED mixed-file
   repo=$ROOT` and stop (fail closed; never ask, never stage around it wholesale).

3. Draft the Conventional Commits message from **this** repo's staged diff (format above), write it to `$RUN_DIR/message.txt`, and validate:

   ```bash
   cog gc-commit-lint --message-file "$RUN_DIR/message.txt" --repo-root "$REPO_ROOT" --json
   ```

   If `ok` is `false` and `deferred` is `false`, revise per `violations` and re-lint before committing.

4. Run the **Per-Repo Commit Round Loop** below until the repo commits clean or the loop stops.

5. If `--push` is present and the commit is clean:

   ```bash
   cog gc-push --repo-root "$REPO_ROOT" --json
   ```

   Emit `COMMIT_PUSH_OK` on success or `COMMIT_PUSH_FAILED` on failure.

6. Emit the one result line (Result Line Contract) to `$RESULT_FILE` and as the trailing block, with the `repo=<root>` suffix when `--multi-repo` is present.

### Per-Repo Commit Round Loop

Each round fixes the **whole** report at once, then retries — never one error per round.

Round R:

1. Attempt the commit:

   ```bash
   cog gc-commit --message-file "$RUN_DIR/message.txt" --paths-file "$PATHS_FILE" --repo-root "$REPO_ROOT" --json
   ```

   `gc-commit` returns the full hook and git output path in its `.log` field; read that value — it is round R's report path (`$ROUND_LOG`). Substitute the literal `.log` value from **this** round's `gc-commit` JSON into the commands below; before retrying, remember it as the previous round's report path (`$PREV_ROUND_LOG`) for the stuck check.

2. If `ok` is `true`, the repo is committed. Leave the loop and emit its result line.

3. Otherwise classify the report at the `.log` path this round returned:

   ```bash
   cog gc-classify-failure --log "$ROUND_LOG" --json
   ```

   - `commit-message` (and any `gc-commit` pre-flight `lint`-only failure where `git commit` was not attempted): revise the message per `lint.violations` and retry. This stays in this loop.
   - `auto-fixer` or `content-fix`: delegate the fixes (Delegated fix, below), then re-stage and retry (round R+1).
   - `push-hook`: delegate the fixes the same way, create a normal follow-up commit through `gc-commit`, and retry.
   - `setup-missing`, `push-setup-missing`, `push-non-hook`, `unknown`: write and emit `COMMIT_FAILED <class> repo=$ROOT log=<path>` and stop; do not run git config or setup commands.

4. Stuck check. Before retrying into round 4 and every round after, compare the two most recent reports:

   ```bash
   cog gc-loop-progress --current "$ROUND_LOG" --previous "$PREV_ROUND_LOG" --json
   ```

   When `recurring` holds the same signatures with `resolved` empty and `churn_ratio` at or near `0`, the loop is stuck. Redirect to a better path: broaden the fix scope, address the root cause earlier rounds skirted, or take on a class the loop kept deferring, then re-delegate with that framing. If a redirected round still leaves the same `recurring` signatures with no progress, write and emit `COMMIT_FAILED stuck repo=$ROOT log=<path>` with the recurring signatures and stop.

### Delegated fix

For `auto-fixer`, `content-fix`, and `push-hook`, delegate the remediation to a fresh-context Claude worker through the Agent tool (`subagent_type: general-purpose`), never the Skill tool. The prompt tells the worker to read `$HOME/.claude/skills/gc-hook-fix/SKILL.md` and follow it, passing `--repo-root "$REPO_ROOT"`, `--session-files "$PATHS_FILE"`, and `--report "$ROUND_LOG"` (this round's `gc-commit` `.log` path). The worker fixes every reported issue at once within the session file scope and re-stages. On return, retry the commit; if it reports out-of-scope items, write and emit `COMMIT_FAILED out-of-scope
repo=$ROOT log=<path>` and stop.
