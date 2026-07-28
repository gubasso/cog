---
name: precommit-fix
description: >
  Run the project's pre-commit hooks and loop until they pass. Delegates the
  install check, hook execution across stages, and failure collection to the
  cog CLI, then fixes every reported issue in one pass and re-runs. Use when the
  user says "precommit-fix", "run pre-commit", "fix pre-commit failures", "run
  hooks until clean", or "loop pre-commit".
model: opus
effort: low
argument-hint: "[-s|--stage <pre-commit|pre-push|...>]..."
---

<!-- trigger-tests: "precommit-fix", "run pre-commit until clean", "fix the failing pre-commit hooks" -->

# Pre-commit fix loop

Run the project's pre-commit hooks, collect every failure at once, fix them all in a single pass, and repeat until the hooks pass clean, the failures stop changing, or the user stops the loop. `cog precommit-run` owns the deterministic work — ensuring hooks are installed, running each configured stage, and collecting the failing hooks — so this skill only decides what to fix and when to stop.

## Inputs

`$ARGUMENTS` may contain repeated `-s`/`--stage <stage>` flags (`pre-commit`, `pre-push`, `commit-msg`, ...); each occurrence adds one stage, so `-s pre-commit -s pre-push` runs both. Pass them straight through to `cog precommit-run`. With no stage flag, the command runs every non-manual stage configured in `.pre-commit-config.yaml`.

## Run directory

Bind a run directory once and write every round's log under it:

```bash
RUN_DIR="$(cog rundir precommit-fix | sed -n 's/^RUN_DIR=//p')"
[ -n "$RUN_DIR" ] || { echo "ERROR: cog rundir did not emit RUN_DIR" >&2; exit 1; }
```

## Cog contract

Each round runs one command. Pass the round's own log path and any `--stage` flags the user supplied:

```bash
cog precommit-run -s pre-commit -s pre-push --log "$RUN_DIR/precommit-round-1.log" --json
```

The JSON reports `ok` (all stages passed), `installed`, `stages` (what ran), `failed_hooks` (stable `hook:<id>` signatures), `classification` (with `retryable` and `requires_judgment`), and `log` (the full output path). A missing `pre-commit` CLI fails the command closed with an actionable message; a missing config or non-git tree returns `ok:false` with a `reason`.

## Workflow

1. Bind the run directory.

2. Run `cog precommit-run` with the user's stage flags and this round's log path. Number each round's log (`precommit-round-1.log`, `-2`, ...).

3. If `ok` is `true`, the hooks are clean — stop with `hooks-pass`.

4. If `ok` is `false` with a `reason` (missing config, non-git tree), report the reason to the user and stop — this is not a fixable hook failure.

5. Otherwise read the `log` file and enumerate every failing hook and concrete issue it names (hook ids, file/line references, linter messages, auto-fixer notices). This list is the full scope for the round.

6. Fix every issue in one pass:
   - Auto-fixer hooks (formatters that already rewrote files) need no edit — the rewritten files are the fix.
   - Content hooks (shellcheck, mypy, eslint, ruff, markdownlint, tests, and the like) get the minimal edit that resolves each reported issue.
   - Group the work by file so every issue in a file is resolved together.
   - When a fix needs a semantic decision, or a file or change the log does not pin down, record it as an out-of-scope item for the user instead of guessing.

7. Re-run `cog precommit-run` (next round, next log). Compare this round's `failed_hooks` to the previous round's: an identical set two rounds running means the fixes are not landing — stop with `stall`.

8. Repeat until a terminal condition is reached.

## Terminate

- `hooks-pass` — `ok:true`; the hooks are clean.
- `stall` — the same `failed_hooks` signatures repeat across two rounds, or only out-of-scope items remain.
- `user-limit` — the user set a round cap and it is reached.
- `user-abort` — the user stops the loop.
- `error` — `pre-commit` is unavailable, or the command returns a non-fixable `reason`.

## Result line

End the run with a single trailing line:

- `PRECOMMIT_FIX_OK rounds=<n>` when the loop reached `hooks-pass`.
- `PRECOMMIT_FIX_FAILED reason=<reason>` for any other terminal condition, with a short list of what still fails and any out-of-scope items for the user.

## Guardrails

- Fix all reported issues together each round; do not fix one hook per round.
- Never bypass hooks: no `--no-verify`, no `-n`, no `SKIP=...`, no hook removal, and no edits to `.pre-commit-config.yaml` or git config to sidestep a failure.
- Never run history- or worktree-destroying git (`git reset --hard`, `git restore`/`git checkout` on worktree files, `git clean`). If the tree reaches a state you cannot explain, stop and record it for the user.
- On `stall`, stop and report the impasse rather than churning further rounds.
