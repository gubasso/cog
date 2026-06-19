# Single-agent executor wrappers: executor-claude + executor-codex-session + 3-stage

> Complexity: L | Rounds: 4 | Generated: 2026-06-19 | Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Problem Statement

Single coding-agent executions are represented ad hoc across many skills today (a Codex `exec`, or a
native Claude run of a prompt). Wrap them into two first-class `executor-*` skills so the future can
compose hand-offs to agents/subagents and so they can be used as queue prompts:

- `/executor-codex-session` — executes a prompt/plan via the cog codex-session runner (self-contained
  native effort, no profiles).
- `/executor-claude` — executes a prompt/plan via the native TUI Claude path.

Both must embed a NEW 3-stage execution feature (which today does not exist):

1. Stage 1 — run `/plan-*` to create and output a plan (`plan-codex` for executor-codex-session,
   `plan-claude` for executor-claude).
2. Stage 2 — run `/review-plan-*` with the OTHER engine (plan made by Claude → review prioritizes
   Codex, and vice-versa).
3. Stage 3 — execute with the reviewed plan + relevant session context.

An executor accepts a prompt OR an already-made plan; with a prompt it runs all three stages, with a
plan it can skip Stage 1. They are usable as `queue-plans`/`queue-rounds` prompts alongside
`executor-prex`.

## Strategy

Build the shared 3-stage sequencing mechanics in `cog` once, then author each wrapper, then wire queue
usability.

1. `executor-cog-contracts` — `cog executor` helper family (run-dir, stage artifacts, 3-stage
   sequencing, OTHER-engine selection rule, queue-prompt recognition).
2. `executor-codex-session-skill` — the Codex-side wrapper.
3. `executor-claude-skill` — the Claude-side wrapper.
4. `queue-integration` — make all three executors valid queue prompts; update `runner-queue`.

## Rounds

1. `executor-cog-contracts.md` — `cog executor` mechanics + bats + surfaces.
2. `executor-codex-session-skill.md` — `skills/codex/executor-codex-session`.
3. `executor-claude-skill.md` — `skills/claude/executor-claude`.
4. `queue-integration.md` — queue-prompt usability + `runner-queue` recognition + docs.

## Execution Commands

```bash
/prex -ar @.implementation-plans/plans/executor-single-agent-wrappers/
# or
/prex -ar .implementation-plans/plans/executor-single-agent-wrappers/executor-cog-contracts.md
```

## Execution Discipline

One `/prex` session per round; runs the first `todo` round, flips it `done`, stops. Commit each round
with `/gc -a` afterward.

## Decisions & Constraints

- `Executor: prex (EF 1.5)`.
- `executor-*` skills execute one plan/prompt at a time. Deterministic 3-stage sequencing, artifact
  hand-offs, and the OTHER-engine selection rule live in `cog`; the skills carry orchestration judgment.
- The OTHER-engine rule: a plan made by Claude is reviewed by the Codex reviewer (`review-plan-codex`);
  a plan made by Codex is reviewed by the Claude reviewer (`review-plan-claude`).
- `executor-codex-session` uses native effort via `cog codex-runner` (no `--profile`). `executor-claude`
  is a Claude skill; if it itself writes a plan artifact directly (rather than delegating all plan
  emission to `/plan-claude`), it carries the plan-mode gate; otherwise the gate lives in the delegated
  `/plan-*` skill. Decide and document per ADR-0015.
- These executors do NOT background Codex / orchestration work (env-first no-backgrounding, ADR-0010);
  foreground delegation only.
- New cog commands sync `cli-commands.md`, man, completions, help snapshots, bats. Do not run git
  commands inside round bodies.

## Reconciliation (depends_on, no duplication)

- `depends_on: lean-plan-and-review-skills` — the 3-stage feature calls `/plan-claude`, `/plan-codex`,
  `/review-plan-claude`, `/review-plan-codex`.
- `depends_on: codex-native-effort-runner` — Stage 3 codex execution + `executor-codex-session` use
  native effort.
- `depends_on: skill-taxonomy-governance` — the `executor-*` prefix + plan-mode gate rules.
- Independent of `executor-prex-refactor`: both are executors and can land in parallel after their
  shared deps. The `runner-*` orchestration of these executors is `runner-queue` (only prompt-form
  recognition is touched here, not a new runner).
