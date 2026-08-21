# 014 — Declarative review scope

## Goal

A review run reviews everything its session produced — the live working tree, the commits the session made, and the files it touched — and the caller narrows that by saying so in prose rather than by learning a flag.

## Appetite

1 implementation session. Chosen before the design below.

## Core

The scope is declared by whoever holds the session, not inferred by cog from git history.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- The commit and explicit-file sources on `cog review-scope`, and the `commits`/`commit_files`/`requested_files`/`sources` keys that report them. Without these, a session that commits mid-run reviews nothing and reports clean, which is the failure this slice exists to remove.
- The two range helpers in `lib/functions/fn_git.sh`. They are separate functions rather than a widened `git_diff_stat_json`, because that function's `mode` enum is a pinned contract and a range is plural where a mode is singular.
- Refusing a source-less scope, and raising on an unresolvable ref instead of returning an empty list. A false clean is worse than a hard failure, and both of these are the paths that produce one.
- `review-loop` running inline in the session that invoked it, so the session is available as the source of what to review. Its frontmatter says the opposite today while its prose assumes the session is there.
- The optional `scope` field on the `review-loop` handoff envelope, so a delegated run inherits the parent's declaration.
- The matching Phase 0 update in both `review-oneshot` twins. This is cut first; the twins keep working unchanged without it.

## Out of scope

- Any inference of a base ref. No `merge-base`, `rev-list`, `symbolic-ref`, or `for-each-ref` enters `lib/`. Inferring a lower bound requires knowing which branch is the trunk and whether the branch is shared, and guessing wrong either reviews a stranger's commits or silently reviews none.
- Path-glob narrowing on `review-scope`. `review-oneshot` already narrows review judgment with `--scope <glob>`, and an explicit file list covers the case that must be deterministic; a second narrowing mechanism would have to agree with the first at every consumer.
- Reviewing another repository. Every helper the scope builder calls is bound to the current working directory, and `--repo` would have to thread through all of them for a case nobody has asked for.
- Merge-commit diffs against multiple parents.
- Any change to how findings are triaged, fixed, or counted.

## Governed by

- `docs/decisions/ADR-0003-machine-facing-output-contract.md` — the `--json` and self-check obligation the widened scope artifact answers to.
- `docs/decisions/ADR-0007-skill-and-cli-responsibility-boundary.md` — why the flag surface belongs in cog while "what did this session change" stays judgment in the skill.
- `docs/decisions/ADR-0016-context-briefs-and-input-fidelity.md` — why the session's substance is an input to a review rather than something a worker re-derives.
- `docs/decisions/ADR-0009-orchestration-and-durable-jobs.md` — the delegation boundary that decides which lane `review-loop` runs in.

## Acceptance

```text
When cog review-scope runs with no source flags, it shall issue the same git commands as before. -> test/integration/review_scope.bats
When cog review-scope is given --range or --sha, it shall union those commits' files into changed_files and report them in diff_stats.commits. -> test/integration/review_scope.bats
When cog review-scope is given --files, it shall union that list into changed_files and record it in requested_files. -> test/integration/review_scope.bats
When cog review-scope is given --no-worktree with no commit or file source, it shall fail rather than emit an empty scope. -> test/integration/review_scope.bats
When a commit ref does not resolve, cog review-scope shall fail naming the ref rather than emit an empty scope. -> test/integration/review_scope.bats
When cog review-scope check is given the same source flags, it shall count the commits' files and lines against the declared limits. -> test/integration/cmd_review_scope_check.bats
When a review-loop handoff carries no scope field, cog review-loop-input shall emit and accept the unchanged five-key envelope. -> test/integration/review_loop_input.bats
When a review-loop handoff carries a scope object, cog review-loop-input shall validate its ranges, shas, files, and worktree fields. -> test/integration/review_loop_input.bats
When review-tech-scope reads a scope carrying the new keys, it shall ignore them and detect from changed_files. -> test/integration/review_tech_scope.bats
When git_range_diff_stat_json is given no range or sha, it shall return an empty range stat without invoking git. -> test/unit/git.bats
When a commit selector resolves to no files and the working tree is off, cog review-scope shall fail rather than emit an empty scope. -> test/integration/review_scope.bats
When a --sha selector names a non-commit object, cog review-scope shall fail rather than read the object's contents as paths. -> test/integration/review_scope.bats
When cog review-scope is given more than one range, it shall walk each range separately so commits[] covers every commit commit_files was built from. -> test/integration/review_scope.bats
When a review-loop handoff scope carries an explicitly null selector or worktree, cog review-loop-input shall reject it rather than read it as the default. -> test/integration/review_loop_input.bats
When any commit or file source is declared and the union resolves to no files, cog review-scope shall fail whether or not the working tree is on. -> test/integration/review_scope.bats
When a --sha selector names a movable ref, cog review-scope shall resolve it once and hand the resolved hash to every collector. -> test/integration/review_scope.bats
When a --range names movable endpoints, cog review-scope shall resolve them once, preserve the two- or three-dot form, and report the original range in sources.ranges. -> test/integration/review_scope.bats
When a --range carries no separator or more than one, cog review-scope shall reject it in both the bare form and check. -> test/integration/review_scope.bats
When a three-dot range is given, cog review-scope shall diff it as A...B but walk its history as A..B so commits[] matches commit_files. -> test/integration/review_scope.bats
```

## Rabbit holes

- A base-ref heuristic creeps back in as a convenience default — escape: the source-less-scope refusal makes "no sources" an explicit caller decision rather than a hole a default rushes to fill, and no ref-resolution git verb is added to `lib/` at all.
- The default path grows a git call and the fake-`git` shim starts failing in a way that reads as a test problem — escape: the range helpers short-circuit before any invocation, and a test asserts the recorded argv log equals the historical sequence verbatim.
- `git show --numstat --format=` reports nothing for a merge commit, so a merge passed as `--sha` contributes no files — escape: accept it and record it here, because `-m` explodes numstat per parent and turns one commit into a diff against every branch it joined.
- The pinned commit range never shrinks between rounds and an operator reads a recurring finding as a stall — escape: the commit and file sources are the run's fixed subject by definition, only the working tree is re-derived per round, and the skill says so where the re-scope happens.
- The handoff envelope's exact-keyset filter doubles again with each optional field — escape: reformulate once as required-subset plus allowed-superset, so the next field costs one array entry.

## Done when

`cog review-scope` with no flags is byte-identical in behavior and in the git commands it issues; a commit range, an explicit file list, and the working tree combine in any combination; `review-loop` invoked in a session that has already committed reviews those commits; the handoff envelope carries the declaration without breaking its five-key form; and the milestone line flips.

## Revisions

2026-08-21, at implementation: three corrections the shaping did not anticipate, all in how a failure reaches the caller. `__cog_git_range_capture` returns its output through a nameref rather than on stdout, because a `die` inside a command substitution only kills the subshell and the caller went on to report an empty changeset for an unresolvable ref — the exact false clean this slice exists to prevent, reintroduced by the code meant to prevent it. The same function captures git's status with `|| status=$?` rather than a bare assignment, because `set -euo pipefail` in `bin/cog` terminated the shell with git's raw 128 before the status check could run, so the caller saw an exit code and no cog error at all. Both were caught by the new tests, not by reading.

2026-08-21, at implementation: the working-tree git sequence a bare `cog review-scope` issues is nine commands, not the seven the shaping counted from the fake shim's recognized-argv list. `cog::fn::git_status_json` resolves the repo root and the current branch itself, so that pair appears twice. The regression test pins the real nine, which is what makes it a baseline rather than a guess.

2026-08-21, at implementation: `review-loop` gave up `context: fork` and `agent: general-purpose`. The frontmatter is advisory and honored only for top-level auto-invocation, and it was the thing preventing a top-level `/review-loop` from seeing the session that knows which commits to review. `executor-prex` forks it through the `Agent` tool regardless, so the handoff lane is untouched.

2026-08-21, at review: four corrections, each closing a path that still reached the false clean this slice exists to remove. A commit selector that resolves to nothing (`--no-worktree --range HEAD..HEAD`) passed the no-source refusal and emitted a successful empty scope, so the refusal now also fires after resolution, with the working tree exempt because a clean tree is a legitimate nothing-to-review. `git show --name-only` prints a blob's contents, so `--sha <tree-ish>:<path>` placed a file's own text in `commit_files` as though every line were a path; `--sha` selectors are now peeled with `rev-parse --verify --quiet <sel>^{commit}` and fail when they do not name a commit, which also pins a tag or branch to the commit it resolved to at scope time. `cog::fn::git_log_range_json` hands every range to one revision walk, where two ranges intersect as `^A B ^C D` and drop a commit that one of them does include — while the file and stat helpers diff each range separately and do include it; `commits[]` is now the per-range union, computed in the scope builder so the shared helper's contract stays as `jira-ticket-creator` found it. And the handoff schema gated its optional `scope` keys on `// <default>`, which reads a present null as absent, so `{"shas": null}` validated and then degraded to a working-tree scope; every optional key is now gated on `has(...)`.

2026-08-21, at review: the `review-loop` round block sourced `$REVIEW_DIR/paths.env`, which sets `RUN_DIR` to the per-round review directory and so silently repointed every later `$RUN_DIR` reference in the skill — `round-N-prompt.txt`, `round-N-findings.json`, `summary-body.md` — at the wrong directory. The block now restores the loop's own `RUN_DIR` after sourcing, and the `--files` list is read from there rather than from the fresh-each-round review directory the block had been naming.

2026-08-21, at review round 2: two corrections, both narrowing gaps left by the round-1 fixes. The post-resolution empty-scope refusal exempted every run with the working tree on, so `cog review-scope --range HEAD..HEAD` on a clean tree still succeeded with an empty scope — the same false clean, reachable without `--no-worktree`. The exemption is now the narrow one it should always have been: only a working-tree-only run may come back empty, because once a commit or a file list is named, an empty union means the thing the caller asked to review was not found. And peeling `--sha` inside each range helper resolved the same selector once per collector, so a branch that moved mid-construction could leave `commit_files` describing one commit while `diff_stats.commits` and `commits[]` described another. Selectors are now peeled once in the scope builder and the resolved hashes are handed to all three collectors, while `sources.shas` keeps reporting the selector the caller actually passed. `__cog_git_range_peel_shas` became `cog::fn::git_peel_commit_selectors` to make that call site legitimate; the range helpers still peel their own input, which is idempotent and keeps them safe for any other caller.

2026-08-21, at review round 3: one correction, the range analogue of the SHA fix the previous round landed. Range endpoints were still copied into `selectors` verbatim, so `--range base..topic` was re-read by each of the three collectors and a branch that moved between them could leave `commit_files` describing one range while `diff_stats.commits` and `commits[]` described another — and a resumed round reusing the same range would silently review a different subject than round 1 did. `__cog_review_scope_resolve_range` now peels both endpoints once in the builder and rebuilds the range from the resulting hashes, returning through a nameref because a die inside an array-append command substitution is swallowed. The `...` form is preserved rather than normalized to `..`, since collapsing it would change merge-base semantics into a plain range, and an omitted endpoint is spelled `HEAD` explicitly so it too is resolved once. `sources.ranges` keeps reporting the range the caller passed.

2026-08-21, at review round 4: the round-3 decision to hand a delimiter-free `--range` to git untouched was wrong and is reversed. `git diff HEAD` compares the working tree against that commit, so `--no-worktree --range HEAD` pulled the live tree back into a scope that had just declared it out, while `git log HEAD` walked all of history — one selector, three collectors, three different changesets, and a `--no-worktree` that did not hold. `--range` now requires exactly one `..` or `...` separator and says to use `--sha` for a single commit; more than one separator is refused too, because the extra `..` would otherwise be swallowed into an endpoint as part of a ref name. `check` inherits both refusals through the shared builder, which is what keeps the guard and the review measuring the same changeset.

2026-08-21, at review round 5: the three-dot range was preserved for the diff collectors, which was right, but handed unchanged to the history walk, which was not. `git diff A...B` shows the merge base against B — B's side only — while `git log A...B` is the symmetric difference and returns A's unique commits too, so `commits[]` named commits whose files `commit_files` had never counted, and pinning those SHAs in a later round would have widened the declared subject. `__cog_review_scope_commits` now rewrites a three-dot range to two dots for the walk alone, which is the history that matches what `git diff A...B` actually diffed. The rewrite is done with an explicit prefix/suffix split rather than `${var/.../..}`, because `...` in a bash substitution pattern is a glob matching any three characters.
