# Commit Routine

The routine that turns **one** repository's declared session file set into a commit: stage, draft and lint a Conventional Commits message, run the fix-all round loop until the repo commits clean, and optionally push.

This is the single source of truth for that routine. It is followed two ways, and the text is identical in both: **inline**, by a session that already holds the context of what it changed, and by a **fresh-context worker** handed one repo and nothing else. The routine ends at an outcome; how that outcome is reported — a trailing status line, a result file, both — belongs to the caller.

## Inputs

Three values the caller resolves before entering the routine:

- `$REPO_ROOT` — the repository to commit. Every `cog gc-*` call passes `--repo-root "$REPO_ROOT"` and targets the repo without `cd`.
- `$PATHS_FILE` — a newline-delimited file of **repo-relative** paths in scope for this repo.
- `$RUN_DIR` — a scratch directory for this repo's artifacts; it holds `message.txt`. The per-round hook report is not under it — it is the path `cog gc-commit` returns in its `.log` field.

Shell state does not persist between Bash tool calls. Substitute the literal paths into every command; never rely on these being live shell variables.

## Non-negotiable rules

- Never mention AI, Claude, Codex, automation, assistance, or similar wording in commit messages.
- Never bypass hooks: no `--no-verify`, no `-n`, no `SKIP=...`, no hook removal, and no git config edits.
- Never run `git commit` directly; commits go only through `cog gc-commit`.
- Never run history- or worktree-destroying git: no `git reset --hard`, no `git restore`/`git checkout` on worktree files, no `git clean`, and no hand-rolled content merges. If staging or commit reaches a tree state you cannot explain, STOP at a failure outcome — never surgery your way out.
- Fix the **whole** hook report in one pass, never one error per round.
- Stay inside `$PATHS_FILE`. A fix that needs a file outside that set is out of scope.

## Commit message format

Every commit message is a Conventional Commit: `type(scope): description`.

- **type**: one of `feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert`.
- **scope** (optional, encouraged): a lowercase noun naming the area changed. Prefer a hierarchical `scope/subscope`, e.g. `feat(auth/login): ...`; the subscope is optional, added only when the parent area is broad enough that a narrower part adds signal — otherwise a single scope (`feat(auth): ...`). Use lowercase kebab-case segments (`github-actions`), keep to ≤ 2 levels, and omit the scope entirely for genuinely cross-cutting changes (`chore: relicense`).
- **description**: imperative, lowercase, no trailing period; keep the subject ≤ 72 chars and put detail in the body after one blank line.
- **breaking change**: add `!` before the colon (`feat(api)!: ...`) and/or a `BREAKING CHANGE:` footer.

`cog gc-commit-lint` checks this deterministically and `gc-commit` enforces it as a pre-flight gate. When the repo runs its own commit-message linter the check reports `deferred: true`; that linter prevails, so follow the project's rules.

## Routine

1. Stage the session files:

   ```bash
   cog gc-stage --session-files "$PATHS_FILE" --repo-root "$REPO_ROOT" --json
   ```

   If `ok` is not `true`, stop at outcome `stage`.

   `cog gc-stage` is path-granular and stages whole files; it cannot isolate hunks in a file that mixes session and non-session changes. It reconciles against the worktree, not just the index: a directory in `$PATHS_FILE` expands to the dirty paths under it (reported in `.session_files`, with the literal input in `.requested`), and a file that was already staged but still carries worktree edits is re-added and reported in `.restaged`. Trust `.session_files`, never `.requested`, when reasoning about what got staged.

2. Materiality check. Review the staged diffstat with `git diff --cached --stat`, run as `git -C "$REPO_ROOT" diff --cached --stat`. If any staged file's churn is materially larger than the edit intended for it — a "one-line" file that staged dozens of lines — treat it as a mixed file the stager cannot split and stop at outcome `mixed-file`. Never stage around it wholesale.

3. Draft the message from **this** repo's staged diff, in the format above, using whatever change context the caller holds. Write it to `$RUN_DIR/message.txt` and validate:

   ```bash
   cog gc-commit-lint --message-file "$RUN_DIR/message.txt" --repo-root "$REPO_ROOT" --json
   ```

   If `ok` is `false` and `deferred` is `false`, revise per `violations` and re-lint before committing.

4. Run the **Commit round loop** below until the repo commits clean or the loop stops.

5. When the caller asked for a push and the commit is clean:

   ```bash
   cog gc-push --repo-root "$REPO_ROOT" --json
   ```

   Success is outcome `push-ok <sha>`; failure is a push failure carrying the reported reason.

## Commit round loop

Each round fixes the **whole** report at once, then retries.

Round R:

1. Attempt the commit:

   ```bash
   cog gc-commit --message-file "$RUN_DIR/message.txt" --paths-file "$PATHS_FILE" --repo-root "$REPO_ROOT" --json
   ```

   `gc-commit` returns the full hook and git output path in its `.log` field; read that value — it is round R's report path (`$ROUND_LOG`). Substitute the literal `.log` value from **this** round's `gc-commit` JSON into the commands below; before retrying, remember it as the previous round's report path (`$PREV_ROUND_LOG`) for the stuck check.

2. If `ok` is `true`, the repo is committed. Leave the loop at outcome `ok <sha>`.

3. Otherwise classify the report at the `.log` path this round returned:

   ```bash
   cog gc-classify-failure --log "$ROUND_LOG" --json
   ```

   - `commit-message` (and any `gc-commit` pre-flight `lint`-only failure where `git commit` was not attempted): revise the message per `lint.violations` and retry. This stays in this loop.
   - `auto-fixer` or `content-fix`: fix the report (**Fixing a hook report**, below), re-stage, and retry as round R+1.
   - `push-hook`: fix the report the same way, create a normal follow-up commit through `gc-commit`, and retry.
   - `setup-missing`, `push-setup-missing`, `push-non-hook`, `unknown`: stop at outcome `<class>`; do not run git config or setup commands.

4. Stuck check. Before retrying into round 4 and every round after, compare the two most recent reports:

   ```bash
   cog gc-loop-progress --current "$ROUND_LOG" --previous "$PREV_ROUND_LOG" --json
   ```

   When `recurring` holds the same signatures with `resolved` empty and `churn_ratio` at or near `0`, the loop is stuck. Redirect to a better path: broaden the fix scope, address the root cause earlier rounds skirted, or take on a class the loop kept deferring, then retry with that framing. If a redirected round still leaves the same `recurring` signatures with no progress, stop at outcome `stuck` and report the recurring signatures.

## Fixing a hook report

The report at `$ROUND_LOG` is the complete todo list for the round. Read all of it, enumerate every failing hook and every concrete issue it names (hook ids, file and line references, linter messages, auto-fixer notices), and resolve them together:

- Auto-fixer hooks (formatters that already rewrote files) need no edit beyond re-staging.
- Content hooks (shellcheck, mypy, eslint, ruff, markdownlint, tests, and the like) get the minimal edit that resolves each reported issue.
- Group the work by file so every issue in a file is resolved in one pass.

Then re-stage so the fixes enter the next attempt:

```bash
cog gc-stage --session-files "$PATHS_FILE" --repo-root "$REPO_ROOT" --json
```

An issue that needs a file outside `$PATHS_FILE`, a semantic decision, or a content change the report does not pin down is **out of scope**: never guess it. A caller holding the change context resolves the report itself; a context-free caller may hand the report to a dedicated fix worker. Either way, unresolved out-of-scope items stop the routine at outcome `out-of-scope`.

## Outcomes

The routine ends at exactly one outcome. The caller renders it.

| Outcome         | Meaning                                                                                                    |
| --------------- | ---------------------------------------------------------------------------------------------------------- |
| `ok <sha>`      | Committed clean.                                                                                           |
| `push-ok <sha>` | Committed clean and pushed.                                                                                |
| `stage`         | `cog gc-stage` did not report `ok`.                                                                        |
| `mixed-file`    | A staged file mixes session and non-session changes.                                                       |
| `<class>`       | A terminal `gc-classify-failure` class: `setup-missing`, `push-setup-missing`, `push-non-hook`, `unknown`. |
| `stuck`         | The round loop stopped making progress.                                                                    |
| `out-of-scope`  | The report needs work outside the session file scope.                                                      |
| push failure    | The commit landed but `cog gc-push` failed, with its reported reason.                                      |

Every failure outcome carries the `$ROUND_LOG` path that produced it, when one exists.
