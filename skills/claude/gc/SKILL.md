---
name: gc
description: >
  Delegates deterministic git mechanics to the cog CLI while preserving
  session-scope and safety judgment in prose. Commits the work across every git
  repo the session touched (source repo plus any satellite/SoT docs repo) by
  fanning out one independent commit worker per repo, in parallel. Use when the
  user says "gc", "commit", "commit this", "save changes", "stage and commit",
  or "commit and push".
model: opus
effort: low
---

<!-- trigger-tests: "gc", "commit", "commit this", "save changes", "stage and commit", "commit and push" -->

# Commit changes

`gc` is the coordinator for committing a session's work. It runs the one-time session partition and
safety scan, then **fans out one independent commit worker per touched repo, all in parallel**, and
aggregates their results. The per-repo commit routine — stage, draft a conforming message, run the
fix-all round loop, optionally push — lives in a fresh-context worker; this skill owns session scope,
the safety gates, and the fan-out.

**Multi-repo by default.** When this session changed files in more than one git repo — a source repo
plus a SoT docs repo, or an orchestrated run writing into a satellite project — commit the work in
**every** touched repo, not just the one the shell sits in. The deterministic partition mechanics live
in `cog gc-plan`; per-repo commit mechanics live in the worker; this skill stays a thin coordinator.

## Non-negotiable rules

- Never commit unless the user explicitly asks to commit.
- Commit every repo the session worked in by default. Deviate only when `gc-plan` reports a surprise
  (a path in no git repo, an undeclared touched repo, an invalid declared dir, or a repo with foreign
  dirty paths) — then STOP and ask the user. Never silently drop a touched repo.
- Resolve every "ask the user" branch in this coordinator, before any worker spawns. A parallel worker
  runs in fresh context and never asks the user; it fails closed instead.
- During the commit flow never run history- or worktree-destroying git: no `git reset --hard`, no
  `git restore`/`git checkout` on worktree files, no `git clean`, and no hand-rolled content merges.
  If the baseline or a plan result reaches a tree state you cannot explain, STOP and report it — never
  surgery your way out.
- Do not touch live files outside the chosen session file list unless the user explicitly approves.
- Delegate all per-repo staging and committing to the worker; never stage or commit inline in this
  coordinator.

## Cog Contract

Session files are written to a newline-delimited file of paths. In multi-repo mode write **absolute**
paths (they may span repos); `gc-plan` partitions them by owning repo and converts to repo-relative
per-repo path lists. Blank lines are ignored. NUL bytes and empty sets are rejected by the helpers.

The one-time partition + safety scan and the result aggregator are the coordinator's mechanics:

```bash
cog gc-plan --session-files "$SESSION_FILES_FILE" [--repo <dir>]... [--repo-set <file>] --json
cog runner-commit-parse "$RESULTS_FILE" --json
```

`gc-plan` emits:

```json
{
  "ok": true,
  "empty": false,
  "repos": [{"root": "/abs/repo", "paths": ["a"], "extra_dirty": ["b"]}],
  "undeclared_dirty": [{"root": "/abs/other", "paths": ["x"]}],
  "declared_no_change": ["/abs/declared-clean"],
  "escapes": ["/abs/path-in-no-repo"],
  "invalid_repos": ["/not/a/repo"],
  "surprises": ["undeclared-repo:/abs/other"]
}
```

`empty` is `true` when no accepted repo has a declared session path that is actually dirty — the
changeset is empty and there is nothing to commit (a round that only touched queue metadata, for
example). Handle it before fanning out.

`ok` is `false` only when there are `escapes` (paths in no git repo). A non-empty `surprises` list
means the safety scan wants you to ask the user before committing. Each surprise is a tagged string:
`escape:<path>`, `undeclared-repo:<root>`, `invalid-repo:<dir>`, or `foreign-dirty:<root>`. A
`foreign-dirty:<root>` entry means that accepted repo carries dirty or untracked paths the session did
not declare (the repo's `extra_dirty` list) — a pre-existing or someone-else's change the commit must
not sweep in. Pass `--repo <dir>` or `--repo-set <file>` for repos an orchestrator explicitly
declared; this turns the declared set into an allowlist. With no declared repos, every touched repo is
accepted and committed by default.

Each accepted repo object carries a repo-relative `.paths` list. Each worker receives its repo via
`--repo-root <root>` and reuses the deterministic per-repo command surface (`cog gc-stage`,
`gc-commit`, `gc-classify-failure`, `gc-loop-progress`, `gc-push`), all of which target a repo without
`cd`. `cog runner-commit-parse` reads one `COMMIT_*` line per repo and fails closed if any repo's line
is `*_FAILED`.

## Result Line Contract

Each worker emits one canonical status line per repo to its own result-line file:

```text
COMMIT_OK <sha> repo=<root>
COMMIT_PUSH_OK <sha> repo=<root>
COMMIT_FAILED <reason> repo=<root>
COMMIT_PUSH_FAILED <reason> repo=<root>
```

In single-repo mode the worker omits the `repo=` suffix, so the line is the canonical single-repo form
`COMMIT_OK <sha>`. The coordinator concatenates every worker's line and runs `cog runner-commit-parse`,
which fails closed on any `*_FAILED`. Emit the aggregated `COMMIT_*` block as the trailing block of the
reply, with nothing after it. When `gc-plan` reports `empty: true`, the canonical trailing block is the
single line `COMMIT_OK empty`; `cog runner-commit-parse` accepts it and reports `empty: true`.

## Working directory

All scratch artifacts live under one deterministic run directory. Establish it before anything else,
in the first Bash call:

```bash
RUN_DIR="$(cog rundir gc | sed -n 's/^RUN_DIR=//p')"
echo "RUN_DIR=$RUN_DIR"
```

The coordinator's scratch files are fixed paths under that directory:

- `SESSION_FILES_FILE` = `$RUN_DIR/session-files.txt` — the chosen session paths (absolute in
  multi-repo mode).
- Each accepted repo gets its own `$RUN_DIR/repos/<repo-slug>/` subdirectory, where `<repo-slug>` is
  the repo basename plus a short hash of the absolute root so same-basename repos never collide. That
  subdirectory holds the worker's `paths.txt` and `result-line.txt`.
- `RESULTS_FILE` = `$RUN_DIR/commit-results.txt` — the concatenated per-repo result lines.

Shell state does not persist between Bash tool calls. Substitute the literal `RUN_DIR` path echoed
above — and the literal file paths under it — into every later command; never rely on the `$VAR` names
being live shell variables in a later call.

## Workflow

1. Establish the run directory (see "Working directory"), then take a **fresh** baseline in every
   touched repo with read-only commands: live `git status`, `git stash list`, staged diff, unstaged
   diff, and recent log. Reconcile this live status against the files the session actually edited;
   never trust the ambient session-start `gitStatus` snapshot, which can be stale. This informs the
   session file list.

2. Decide the session file list in prose. This remains judgment:
   - With `--all`/`-a`, include every dirty path the user asked to commit across the repos the session
     is responsible for.
   - Otherwise include only files this session created, modified, or the user explicitly named.
   - If the session made no code changes, do not fall back to all dirty files.

   Write the chosen paths to `$SESSION_FILES_FILE`, one per line. In multi-repo mode write **absolute**
   paths.

3. Partition and run the safety scan:

   ```bash
   cog gc-plan --session-files "$SESSION_FILES_FILE" [--repo <dir>]... [--repo-set <file>] --json
   ```

4. Safety branch (all resolved here, before any worker spawns):
   - If `.ok` is `false` (escapes): STOP. Report the paths that resolve to no git repo; do not commit
     anything.
   - If `.empty` is `true`: there is nothing to commit. Emit the canonical `COMMIT_OK empty` line as
     the trailing block and return without spawning any worker.
   - If `.surprises` is non-empty: STOP and ask the user, naming the undeclared repos, any invalid
     declared dirs, and — for each `foreign-dirty:<root>` — the specific foreign paths from that repo's
     `extra_dirty`. These are dirty or untracked files the session never declared; do not commit until
     the user confirms whether they belong. Under `--all`/`-a`, instead of asking, **union** each
     accepted repo's `extra_dirty` into `$SESSION_FILES_FILE` (append, never replace) and re-run
     `gc-plan`; the foreign-dirty surprise then clears because those paths are now declared.
   - Otherwise proceed. Set `MULTI_REPO=1` when `.repos` has more than one entry.

5. Prepare per-repo dispatch inputs. For each repo object in `.repos`, in order, create its
   `$RUN_DIR/repos/<repo-slug>/` subdirectory (slug = repo basename + short hash of the absolute
   root), write that repo's repo-relative `.paths` to `<work-dir>/paths.txt`, designate
   `<work-dir>/result-line.txt` as its result file, and append that result-file path (one per line, in
   `.repos` order) to the manifest `$RUN_DIR/result-files.txt`.

6. Fan out (parallel), with proof-of-delegation. This follows the Homogeneous Parallel Fan-Out pattern
   in `$(cog skill-refs path orchestration/orchestration-patterns.md)`. Set
   `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` before dispatch; never shell-background the Agent calls.
   Take a pre-snapshot of `$RUN_DIR` and clear stale per-repo result/proof files:

   ```bash
   find "$RUN_DIR" -type f -printf '%p %T@\n' 2>/dev/null | sort > "$RUN_DIR/fanout-pre.snap"
   ```

   Then, in ONE assistant message, issue one **Agent** call per repo (`subagent_type:
   general-purpose`, never the Skill tool). Each prompt tells the worker to read
   `$HOME/.claude/skills/gc-repo/SKILL.md` and follow it end-to-end with its literal arguments:
   `--repo-root <root>`, `--session-files <work-dir>/paths.txt`, `--run-dir <work-dir>`,
   `--result-file <work-dir>/result-line.txt`, `--push` (only when `--push`/`-p` is active), and
   `--multi-repo` (only when `MULTI_REPO=1`); and to return one line with its result-line path. All
   calls go in the single message so they run concurrently.

7. Post-snapshot and validate. After all workers return:

   ```bash
   find "$RUN_DIR" -type f -printf '%p %T@\n' 2>/dev/null | sort > "$RUN_DIR/fanout-post.snap"
   diff -u "$RUN_DIR/fanout-pre.snap" "$RUN_DIR/fanout-post.snap" > "$RUN_DIR/fanout-proof.diff" || true
   ```

   For each repo, fail closed if `<work-dir>/result-line.txt` is missing or empty, does not hold
   exactly one `COMMIT_OK`/`COMMIT_PUSH_OK`/`COMMIT_FAILED`/`COMMIT_PUSH_FAILED` line, or (when
   `MULTI_REPO=1`) lacks the `repo=<root>` suffix; or if `fanout-proof.diff` is empty. Do not
   auto-retry; do not fall back to inline commit work. On missing proof, report it and ask the user.

8. Aggregate and emit. Concatenate every worker's result line in `gc-plan` repo order and parse
   fail-closed:

   ```bash
   xargs -r -d '\n' cat < "$RUN_DIR/result-files.txt" > "$RUN_DIR/commit-results.txt"
   cog runner-commit-parse "$RUN_DIR/commit-results.txt" --json
   ```

   Emit the aggregated `COMMIT_*` lines (each carrying its `repo=<root>` suffix in multi-repo mode,
   the bare form for a single repo) as the trailing block of the reply, with nothing after it. A
   `*_FAILED` line (including a mixed-file reason) is a hard fail; surface those repos to the user. A
   failure in one repo does not roll back commits already made in other repos.
