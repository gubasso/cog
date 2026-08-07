---
name: gc
description: >
  Commit the session's work: read the diff of what changed, use the session's own
  context as the source, write a Conventional Commits message, and commit. Fixes
  pre-commit hook failures in a fix-all loop, and commits every git repo the
  session touched when it touched more than one. Use when the user says "gc",
  "commit", "commit this", "save changes", "stage and commit", or "commit and push".
model: opus
effort: low
argument-hint: "[-a|--all] [-p|--push] [--repo <dir>]... [--repo-set <file>]"
---

<!-- trigger-tests: "gc", "commit", "commit this", "save changes", "stage and commit", "commit and push" -->

# Commit changes

Commit what this session changed. Read the diff, use the session's own context as the source of what the change means, write a Conventional Commits message, and commit. That is the whole job in the common case, and it runs **inline in this context** — no subagent.

Two things escalate, only when the case actually appears: a failing pre-commit hook pulls in the fix-all round loop, and a session that touched more than one git repo fans out one commit worker per repo, in parallel. Neither shape is paid for when it does not apply.

The per-repo commit routine — stage, draft and lint the message, run the round loop, optionally push — is one source of truth at `$(cog skill-refs path gc/commit-routine.md)`, followed inline here and by every fan-out worker.

## Non-negotiable rules

- Never commit unless the user explicitly asks to commit.
- Commit every repo the session worked in. Deviate only when `gc-plan` reports a surprise (a path in no git repo, an undeclared touched repo, an invalid declared dir, or a repo with foreign dirty paths) — then STOP and ask the user. Never silently drop a touched repo.
- Resolve every "ask the user" branch here, before any worker spawns. A fan-out worker runs in fresh context and never asks the user; it fails closed instead.
- Never run history- or worktree-destroying git: no `git reset --hard`, no `git restore`/`git checkout` on worktree files, no `git clean`, and no hand-rolled content merges. If the baseline reaches a tree state you cannot explain, STOP and report it — never surgery your way out.
- Do not touch live files outside the chosen session file list unless the user explicitly approves.

## Flags

| Flag         | Short | Effect                                                                                                                  |
| ------------ | ----- | ----------------------------------------------------------------------------------------------------------------------- |
| `--all`      | `-a`  | Commit every dirty path in the repos this session is responsible for, not only the files this session touched.          |
| `--push`     | `-p`  | Push after each clean commit.                                                                                           |
| `--repo`     |       | Declare a repo the session is responsible for, repeatable. Declaring any repo turns the declared set into an allowlist. |
| `--repo-set` |       | Same, as a newline-delimited file of repo roots.                                                                        |

## Scope

1. Bind the run directory, then take a **fresh** baseline in every touched repo with read-only commands: live `git status`, `git stash list`, staged diff, unstaged diff, and recent log. Reconcile that live status against the files the session actually edited; never trust the ambient session-start `gitStatus` snapshot, which can be stale.

   ```bash
   RUN_DIR="$(cog rundir gc | sed -n 's/^RUN_DIR=//p')"
   echo "RUN_DIR=$RUN_DIR"
   ```

   Shell state does not persist between Bash tool calls. Substitute the literal `RUN_DIR` path echoed above — and the literal file paths under it — into every later command.

2. Decide the session file list in prose. This is judgment:
   - With `--all`/`-a`, include every dirty path the user asked to commit across the repos the session is responsible for.
   - Otherwise include only files this session created, modified, or the user explicitly named.
   - If the session made no code changes, do not fall back to all dirty files.

   Write the chosen paths to `$RUN_DIR/session-files.txt`, one per line, as **absolute** paths — they may span repos.

3. Partition and run the safety scan:

   ```bash
   cog gc-plan --session-files "$RUN_DIR/session-files.txt" --json
   ```

   Add `--repo <dir>` (repeatable) or `--repo-set <file>` when the invocation declared repos. `gc-plan` returns `repos[]` (each with an absolute `root`, a repo-relative `paths` list, and an `extra_dirty` list), plus `ok`, `empty`, `undeclared_dirty`, `declared_no_change`, `escapes`, `invalid_repos`, and `surprises`.

4. Safety branch, all resolved here:
   - `.ok` is `false` (there are `escapes`) → STOP. Report the paths that resolve to no git repo; commit nothing.
   - `.empty` is `true` → no accepted repo has a declared session path that is actually dirty. Emit `COMMIT_OK empty` as the trailing block and return.
   - `.surprises` is non-empty → STOP and ask the user, naming the undeclared repos, any invalid declared dirs, and — for each `foreign-dirty:<root>` — the specific foreign paths from that repo's `extra_dirty`. Those are dirty or untracked files the session never declared; do not sweep them in until the user confirms. Under `--all`/`-a`, instead of asking, **union** each accepted repo's `extra_dirty` into `$RUN_DIR/session-files.txt` (append, never replace) and re-run `gc-plan`; the foreign-dirty surprise then clears.
   - Otherwise proceed to **Commit**.

## Commit

- `.repos` has exactly **one** entry → **Commit inline**. This is the default path.
- `.repos` has **more than one** entry → **Multi-repo fan-out**.

## Commit inline

Write that repo's repo-relative `.paths` to `$RUN_DIR/paths.txt`, then follow the routine at `$(cog skill-refs path gc/commit-routine.md)` **in this context**, with `$REPO_ROOT` set to the repo's `root`, `$PATHS_FILE` to `$RUN_DIR/paths.txt`, and `$RUN_DIR` as the routine's scratch directory. Pass the push step when `--push`/`-p` is active.

Fix hook reports inline. This session already holds the context of what it changed and why, so it resolves the whole report itself rather than handing it to a blind worker.

Render the routine's outcome as the single canonical status line, in the bare single-repo form, via `cog msg` — written as the trailing block of the reply with nothing after it:

```bash
cog msg ok commit "$SHA"                        # COMMIT_OK <sha>
cog msg ok commit-push "$SHA"                   # COMMIT_PUSH_OK <sha>
cog msg failed commit "<reason> log=<path>"     # COMMIT_FAILED ...
cog msg failed commit-push "<reason>"           # COMMIT_PUSH_FAILED ...
```

There is one result and this context produced it, so there is no snapshot, no proof diff, and no aggregation parse on this path.

## Multi-repo fan-out

One independent worker per repo, all in parallel, following the Homogeneous Parallel Fan-Out pattern in `$(cog skill-refs path orchestration/orchestration-patterns.md)`. Each worker reuses the same deterministic per-repo command surface, targeting its repo without `cd`.

1. Prepare per-repo dispatch inputs. For each repo object in `.repos`, in order, create `$RUN_DIR/repos/<repo-slug>/` (slug = repo basename plus a short hash of the absolute root, so same-basename repos never collide), write that repo's repo-relative `.paths` to `<work-dir>/paths.txt`, designate `<work-dir>/result-line.txt` as its result file, and append that result-file path (one per line, in `.repos` order) to `$RUN_DIR/result-files.txt`.

2. Pre-snapshot, clearing stale per-repo result and proof files:

   ```bash
   find "$RUN_DIR" -type f -printf '%p %T@\n' 2>/dev/null | sort > "$RUN_DIR/fanout-pre.snap"
   ```

3. Dispatch. Set `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` before dispatch; never shell-background the Agent calls. In ONE assistant message, issue one **Agent** call per repo (`subagent_type: general-purpose`, never the Skill tool). Each prompt tells the worker to read `$HOME/.claude/skills/gc-repo/SKILL.md` and follow it end-to-end with its literal arguments: `--repo-root <root>`, `--session-files <work-dir>/paths.txt`, `--run-dir <work-dir>`, `--result-file <work-dir>/result-line.txt`, `--push` (only when `--push`/`-p` is active), and `--multi-repo`; and to return one line with its result-line path. All calls go in the single message so they run concurrently.

4. Post-snapshot and validate:

   ```bash
   find "$RUN_DIR" -type f -printf '%p %T@\n' 2>/dev/null | sort > "$RUN_DIR/fanout-post.snap"
   diff -u "$RUN_DIR/fanout-pre.snap" "$RUN_DIR/fanout-post.snap" > "$RUN_DIR/fanout-proof.diff" || true
   ```

   For each repo, fail closed if `<work-dir>/result-line.txt` is missing or empty, does not hold exactly one `COMMIT_OK`/`COMMIT_PUSH_OK`/`COMMIT_FAILED`/`COMMIT_PUSH_FAILED` line, or lacks the `repo=<root>` suffix; or if `fanout-proof.diff` is empty. Do not auto-retry; do not fall back to inline commit work. On missing proof, report it and ask the user.

5. Aggregate and emit. Concatenate every worker's result line in `gc-plan` repo order and parse fail-closed:

   ```bash
   xargs -r -d '\n' cat < "$RUN_DIR/result-files.txt" > "$RUN_DIR/commit-results.txt"
   cog runner-commit-parse "$RUN_DIR/commit-results.txt" --json
   ```

   Emit the aggregated lines — `COMMIT_OK <sha> repo=<root>`, `COMMIT_PUSH_OK <sha> repo=<root>`, `COMMIT_FAILED <reason> repo=<root>`, `COMMIT_PUSH_FAILED <reason> repo=<root>` — as the trailing block of the reply, with nothing after it. A `*_FAILED` line is a hard fail; surface those repos to the user. A failure in one repo does not roll back commits already made in other repos.
