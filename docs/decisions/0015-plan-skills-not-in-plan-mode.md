# ADR-0015: Plan-Emitting Skills Must Not Run in Claude Plan Mode

## Context and Problem Statement

Several shipped skills produce a plan as their primary output and **write it to disk** — the
plan-writer family writes plan directories under `.implementation-plans/`, `plan-reviewer` writes a
rewritten plan, `refactor-migration-plan` writes a plan directory, and
`review-implementation-plans` mutates plan queues and files.

Claude Code's native **plan mode** (`permission_mode = "plan"`, entered via `Shift+Tab` or `/plan`)
is read-only: it permits reading, exploration, and writing the harness plan file, but blocks source
edits and writes. Invoking a plan-emitting skill while plan mode is active therefore either fails
confusingly when the first `Write` is blocked, or wastes a full research/interview pass before dying.
We want a deterministic, durable rule: a plan-emitting skill must detect plan mode at its pre-flight
phase, stop before doing any work, and tell the user to exit plan mode and re-invoke.

### What official Claude Code docs establish about detection

Research against the official documentation
(`code.claude.com/docs/en/permission-modes.md`, `/hooks.md`, `/settings.md`, `/skills.md`):

- Plan mode is the `permission_mode = "plan"` state. It allows reads/exploration and writing the
  plan, but blocks source edits/writes.
- `permission_mode` is delivered **only to hooks** (PreToolUse / UserPromptSubmit / PermissionRequest
  receive it in their stdin JSON; possible values include `default`, `plan`, `acceptEdits`, `auto`,
  `dontAsk`, `bypassPermissions`). It is **not** injected as an environment variable into the Bash
  tool environment — there is no `$CLAUDE_PERMISSION_MODE` / `$CLAUDE_PLAN_MODE`.
- The model running a skill **does** receive a system-reminder stating plan mode is active and that
  it must not make edits.

Consequence: a `cog` subcommand cannot deterministically detect plan mode (no readable signal). The
only in-skill signal is the model's own context, which is probabilistic.

## Considered Options

- **A `PreToolUse` (or `UserPromptSubmit`) hook** that reads `permission_mode` and blocks plan-emitter
  tool calls in plan mode. Deterministic, but ADR-0010 deliberately retired hook-based runtime
  enforcement in favor of an env-first contract, and a hook lives in environment settings — it does
  not ship self-contained with the skills installed to XDG.
- **A `cog` subcommand** that asserts "not in plan mode" at pre-flight. Impossible: plan mode is not
  exposed to the Bash environment, so the deterministic layer is blind to it.
- **A skill-prose gate** (probabilistic detection from the model's own context) plus a deterministic
  `cog skill-lint` check that every plan-emitter carries the gate.

## Decision Outcome

Chosen option: **skill-prose gate enforced by `cog skill-lint`.**

1. Every plan-emitting Claude skill carries a **Phase 0 plan-mode gate**: before any other work, if
   plan mode is active (the model has a plan-mode system-reminder), it **stops and notifies** the
   user to exit plan mode (`Shift+Tab`) and re-invoke. The gate does **not** call `ExitPlanMode` —
   that tool presents a plan for approval, which is the wrong semantics for a skill whose job is to
   write a plan file — and it does not silently continue.
2. Detection stays probabilistic and in prose, consistent with [ADR-0008](0008-skill-script-boundary.md):
   skills own probabilistic judgment; deterministic mechanics live in `cog`.
3. The deterministic part we can own lives in `cog skill-lint`: a new `plan-mode-gate` rule. A Claude
   skill marked `<!-- cog-skill: plan-emitter -->` must contain the `<!-- cog-plan-mode-gate -->`
   stanza, or the lint fails. Codex skills are exempt — Codex has no Claude plan mode.

The gate currently applies to `plan-writer`, `plan-writer-multi`, `plan-reviewer`,
`refactor-migration-plan`, and `review-implementation-plans`. The lint rule makes the requirement
self-propagating: any future plan-emitter that declares itself must carry the gate.

The contract and the canonical gate wording live in
[skill-contract.md](../reference/skill-contract.md) (`Plan-mode gate`).

## Consequences

- Good: Plan-emitting skills fail fast with a clear message instead of a confusing mid-run write
  block.
- Good: The rule is enforced by the existing quality gate (`cog skill-lint`, run by pre-commit), so
  it cannot silently drift as skills are added.
- Good: No reintroduced hook; the env-first contract of ADR-0010 is preserved, and skills stay
  self-contained for XDG install.
- Bad: Detection is probabilistic — a model that ignores its plan-mode system-reminder could still
  attempt to proceed (where the harness then blocks the write). The gate reduces, but cannot
  hardware-enforce, the failure.
- Bad: The canonical gate wording is duplicated across plan-emitter skills (skills must be
  self-contained at runtime); the lint rule checks only for the marker, not the exact prose.

## Status

Accepted; gate placement superseded by
[ADR-0037](0037-plan-mode-gate-canonical-render.md).

The detection contract and cheap-fail goal stand. ADR-0037 moves the gate off the plan/review workers
onto the executor-*/runner-* orchestrator layer that drives them, and makes the wording a cog-rendered
single source of truth (`cog plan-mode-gate render`) enforced by `cog skill-lint`.
