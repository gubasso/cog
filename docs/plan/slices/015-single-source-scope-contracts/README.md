# 015 — Single-source scope contracts

## Goal

The review scope describes one diff with one command and reports one answer, and a sourceable path fragment binds nothing its caller owns.

## Appetite

1 implementation session. Chosen before the design below.

## Core

Two facts that must agree are read from one place, not reconciled afterwards.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- One numstat invocation per commit selector, feeding both the file list and the line stats. Two invocations describing one diff is what let `commit_files` and `diff_stats.commits` disagree on a merge, and no amount of testing makes two sources agree the way one source does.
- `--no-renames` on every numstat call, including the pre-existing worktree one. Without it a rename lands in `.path` as the literal string `old.txt => new.txt`, which names no file on disk.
- `--first-parent` declared explicitly rather than inherited. `git show` picks combined-diff semantics for a merge on its own, and the flag that suppresses it is the difference between a reviewed merge and a skipped one.
- Prefixing every name `review-init` writes into `paths.env`, so sourcing it cannot repoint a caller's `RUN_DIR`.
- The invariant recorded where the next fragment author will look, and pinned by a test. This is cut first; the rename alone fixes today's callers.

## Out of scope

- Rename tracking in the scope artifact. `--no-renames` reports a rename as a delete plus an add, which over-counts a renamed file's lines; over-counting a review budget is the safe direction and under-scoping is the failure this repo keeps paying for.
- NUL-delimited numstat. It is the exact fix for renames, but command substitution cannot carry NUL bytes, so it costs a temp file and a cleanup path for a fidelity gain `--no-renames` already delivers safely.
- Combined-diff (`--cc`) review of merge conflict resolutions. That is a different review target from "what this merge brought in", and naming it needs its own decision.
- A shared enforcing writer for sourceable fragments. There is one emitter; hoist when there are two.
- Any change to the source flags, the scope JSON keys, or the handoff envelope.

## Governed by

- `docs/decisions/ADR-0003-machine-facing-output-contract.md` — the self-check obligation an artifact that contradicts itself does not meet.
- `docs/decisions/ADR-0007-skill-and-cli-responsibility-boundary.md` — why the fragment's namespace is cog's problem and not the skill's to work around.
- `docs/plan/slices/014-declarative-review-scope/README.md` — the slice these defects shipped in, and the false-clean principle they violate.

## Acceptance

```text
When a commit selector names a merge, cog review-scope shall list its files in changed_files and count the same files in diff_stats.commits. -> test/integration/review_scope.bats
When a commit selector renames a file, cog review-scope shall report the real paths and never a combined old-to-new string. -> test/integration/review_scope.bats
When git_range_scope_json reads a selector, its file list and its line stats shall name the same paths. -> test/unit/git.bats
When git_diff_stat_json reads a renamed worktree file, it shall report the real paths. -> test/unit/git.bats
When review-init writes paths.env, it shall bind only REVIEW_-prefixed names. -> test/unit/cmd_review_init.bats
When a skill sources paths.env, its own RUN_DIR shall survive unchanged. -> test/integration/review_init.bats
```

## Rabbit holes

- The unified collector is written as a third helper the other two call, and a later change edits one caller back into its own git invocation — escape: neither public helper issues a git command of its own any more, so re-splitting them shows up as a `git` invocation inside a function that had none.
- `--first-parent` looks like a no-op on `git diff` and gets dropped as noise — escape: it is one flag array shared by both call sites, because splitting the flag set is the shape of the bug being fixed.
- The `paths.env` rename is softened into emitting both the old and new names during a transition — escape: emitting `RUN_DIR` at all is the defect, so a dual-emit period preserves it exactly; all three consumers ship from this repo and move in the same commit.
- The pinned nine-command argv baseline is treated as a contract to preserve — escape: it pins that no additional work happens by default, not that the flags never improve; it moves with the fix and the revision says why.

## Done when

A merge selector produces the same file set in `changed_files` and `diff_stats.commits`; a rename reports real paths in both the commit and worktree stats; sourcing `paths.env` leaves the caller's `RUN_DIR` untouched and the three skills drop their save-restore ceremony; and the milestone line flips.

## Revisions

2026-08-22, at implementation: the fix went one step further than shaping described. Making both helpers read one numstat record set removed the disagreement but not the duplication — `review-scope` still called two public functions, so git ran twice per selector with identical argv. The two helpers collapsed into one, `cog::fn::git_range_scope_json`, returning `{files, stat}` together. Returning both halves from one call is what makes "these two facts agree" structural at the caller as well as inside the helper; a caller cannot ask half the question.

2026-08-22, at implementation: moving the collector behind a command substitution reintroduced slice 014's subshell defect within the hour — a `die` on an unresolvable ref killed only the subshell, leaving an empty record set and a `jq --argjson` crash at exit 70 instead of the intended 65. The collector now fills a nameref, like `__cog_git_range_capture` beside it. The test written for the old two-helper shape caught it, which is the argument for writing the failure test before the refactor rather than after.

2026-08-22, at implementation: `review-init` prefixes its stdout `KEY=value` lines too, not only `paths.env`. Shaping scoped the rename to the sourceable fragment, but leaving stdout emitting a bare `RUN_DIR` would have left the command reporting one directory under two names depending on which surface a caller read. One command, one vocabulary.
