# Round 3: review-loop skill leaning

> Plan: review-deep-loop-refactor | Round: 3 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

With the handoff JSON + child-run discovery now owned by `cog` (Round 2), strip the deterministic
prose out of `review-loop` so it carries only judgment.

## Previous Rounds

Round 1: `review-code-deep` stage-4 refactor. Round 2: `cog review-loop-input` + child-locate.

## Scope of This Round

**IN scope:**

- Rewrite `skills/claude/review-loop/SKILL.md` to consume `cog review-loop-input` (assembly +
  validation) instead of any inline JSON-literal schema construction, and `cog review-loop child-locate`
  instead of the `find`/`comm`/`diff`/snapshot prose. Keep the handoff + standalone modes, MAX_ROUNDS,
  per-round context assembly, triage judgment, and termination logic as prose.
- Confirm Codex effort is native (already swept by `codex-native-effort-runner`) and that the body no
  longer reads `codex-conventions.md` at runtime (already removed by `cog-self-contained-skill-refs`) —
  do not re-do those; just verify and remove any residual reference this refactor exposes.
- Run `cog skill-lint` (orchestration + structural + premise rules) — the premise rule should no
  longer flag deterministic JSON/`find` prose, since it now lives in cog.

**OUT of scope:**

- `review-code-deep` (Round 1).
- Rewiring prex Stage 5 to call the leaned `review-loop` (owned by `executor-prex-refactor`).

## Deterministic vs Probabilistic

- Deterministic (cog): JSON assembly + child discovery, now via the Round-2 commands.
- Judgment: triage, termination, finding validation — all skill prose (unchanged in spirit).

## Validation

- `cog skill-lint` green on `review-loop`; no premise findings for deterministic-in-prose JSON/`find`.
  `grep -n 'review_loop_input' skills/claude/review-loop/SKILL.md` shows only a `cog review-loop-input`
  call, no JSON literal. `just lint` + `just test` green. Marks plan `review-deep-loop-refactor` done
  in the top-level queue as the final round.

## Execution Discipline

One round per `/prex` session; flip this round `done`, set the plan `done` in the top-level queue, and
stop. Commit with `/gc -a` afterward.
