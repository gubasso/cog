# Round 2: /executor-codex-session skill

> Plan: executor-single-agent-wrappers | Round: 2 of 4 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Author the Codex-side single-agent executor on top of the Round-1 `cog executor` mechanics. It wraps
the cog codex-session runner (self-contained native effort, no profiles) and embeds the 3-stage flow.

## Previous Rounds

Round 1 built the `cog executor` 3-stage sequencing mechanics.

## Scope of This Round

**IN scope:**

- `skills/codex/executor-codex-session/SKILL.md`: Codex frontmatter = `name` + `description` only.
  Body = sequencing + judgment: accept a prompt OR a plan path; run the 3-stage flow via `cog executor`:
  - Stage 1 → `/plan-codex` (skip if a plan is supplied).
  - Stage 2 → `/review-plan-claude` (the OTHER engine reviews a Codex-made plan).
  - Stage 3 → execute the reviewed plan via `cog codex-runner` with native effort (no `--profile`),
    carrying relevant session context.
  - Emit the executor summary via `cog executor`.
- Use foreground delegation only; never background the Codex call (env-first, ADR-0010). Rely on the
  internalized cog orientation (no runtime `codex-conventions.md` read).
- Run `cog skill-lint` (Codex name+description rule + orchestration rules).

**OUT of scope:**

- `/executor-claude` (Round 3); queue wiring (Round 4).

## Deterministic vs Probabilistic

- Deterministic (cog): the 3-stage sequencing + codex execution via `cog executor` / `cog codex-runner`.
- Judgment: when to skip Stage 1, how much session context to carry into Stage 3, error handling.

## Validation

- `cog skill-lint` green; the skill contains no inline deterministic shell beyond `cog` calls and no
  `--profile`. `just lint` + `just test` green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
