# Rename `review-code-deep` → `review-lean` + single-pass upgrade

> Complexity: M | Rounds: 1 | Generated: 2026-06-22 | Repo: /workspaces/cog

## Problem Statement

The skill `review-code-deep` (Claude twin `skills/claude/review-code-deep/SKILL.md`, Codex twin `skills/codex/review-code-deep/SKILL.md`) is a clean thin orchestrator, but its identity contradicts its behavior: the frontmatter description and triggers advertise a **"multi-pass"** review, while the actual workflow is a single pass (Phase 0→1→2, one `decision`, no loop). The true multi-pass owner is the `review-loop` skill, which calls this skill in rounds.

This work does two things in one cohesive change:

1. **Renames** the skill to **`review-lean`** — it is a single-pass review, and the name pairs with the iterative `review-loop` (lean = one pass, loop = many). It keeps the `review-*` taxonomy (`docs/decisions/0016-skill-prefix-taxonomy.md`) and collides with nothing.
2. **Upgrades** the skill content: single-pass identity in prose, a thicker explicit Phase 1, loading the review-discipline references directly, optional schema metadata, and a tightened Codex orchestrator-output contract.

The rename is load-bearing in several callers: `review-loop` invokes the Codex twin via the `$review-code-deep` token and prose; `executor-prex` reads it at the installed path `$HOME/.claude/skills/review-code-deep/SKILL.md`; `review-findings` cites its JSON schema; plus doc/policy/test references. All must move together.

## Strategy

One plan directory, one round. Despite touching ~15 files plus two directory renames, the change is a single logical refactor: rename the skill everywhere it is referenced, then apply the content upgrade to both twins in parallel. The user fixed this at a single `/executor-prex` round; the Executor Factor (executor-prex, EF 1.5) comfortably covers an M-grade scope in one session.

## Rounds

1. `rename-and-single-pass-upgrade.md` — rename `review-code-deep` → `review-lean` across the repo and apply the single-pass content upgrade to both twins.

## Execution Commands

```bash
# Execute the next todo round (executor reads queue-rounds.yaml, runs the first todo round, then stops):
/executor-prex -ar @.implementation-plans/plans/review-lean-rename/

# Or target the round file directly:
/executor-prex -ar .implementation-plans/plans/review-lean-rename/rename-and-single-pass-upgrade.md
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for a single `/executor-prex` session. Do not implement multiple rounds in one session.

When `/executor-prex` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh `/executor-prex` session is launched for any subsequent round.

This plan has exactly one round, so it completes in a single `/executor-prex` session.

## Decisions & Constraints

- **Executor: executor-prex (EF 1.5).** Sized for one round at this capability assumption.
- **New name is `review-lean`** (user decision). Pairs with `review-loop`; fits the `review-*` taxonomy; no collision with `review-plan-lean` / `plan-reviewer`.
- **Use filesystem `mv`, not `git mv`.** Git detects the rename at commit time. Per `AGENTS.md`, run no git commands.
- **Edit depth: Fuller** (user choice) — inline guidance blocks in Phase 1 are explicitly requested, which satisfies the ADR 0019 lean-prose exception ("negative/exclusion statements allowed when explicitly requested").
- **Schema additions are optional metadata** (user choice). `cog review-normalize-findings` and `cog review-validate-findings` pass unknown fields through (verified), so no cog or test changes are needed; the new fields are documented as optional and stay unenforced.
- **Both twins move together** (ADR 0021 twin parity). Codex frontmatter stays `name` + `description` only (`docs/reference/skill-contract.md`).
- **No cross-twin source references in runtime skill prose** (ADR 0019 / `skill-source-path-reference` lint rule) — the Codex orchestrator contract is made precise on its own terms.

## Rejected Alternatives

- **Splitting into multiple rounds** (rename round, then content round): rejected — the user requested a single round, and the rename and content edits touch the same two SKILL.md files, so splitting would force overlapping edits across sessions.
- **Inlining the full review discipline into the skill prose**: rejected in favor of loading `llm-review-discipline.md` directly in Phase 0 (the rules already live there) — keeps the skill lean (ADR 0019) and DRY (ADR 0023). The Fuller inline blocks are a deliberate, user-requested addition on top of that load, not a replacement for it.
- **Renaming the run-init label to keep a `-codex` suffix**: rejected — the argument is only a run-dir prefix; twin consistency favors the shared base name `review-lean`.

## Risks & Edge Cases

- **Stray reference breaks a caller.** If any `$review-code-deep` token or installed-path reference is missed, `review-loop` or `executor-prex` silently invokes a non-existent skill. Mitigation: the round ends with a repo-wide grep that must return only the intentional leave-as-is hits.
- **`name`/directory mismatch fails lint.** The `cog skill-lint` `name` rule requires frontmatter `name:` to equal the parent directory. Mitigation: rename the directory and edit `name:` in the same step; re-run `cog skill-lint`.
- **Accidentally rewriting history.** Historical artifacts under `.implementation-plans/plans/*`, the external attribution in `skill-refs/code-review/SOURCES.md`, and the synthetic lint fixture in `test/integration/cmd_skill_lint.bats` must NOT be rewritten. They are explicitly out of scope.

## Completion

When the round is done, set it `done` in this plan's `queue-rounds.yaml` and set this plan `done` in the top-level `.implementation-plans/queue-plans.yaml`. Nothing moves on disk.
