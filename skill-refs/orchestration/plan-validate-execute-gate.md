# Plan-validate-execute gate

Single source of truth for the plan-first gate. Every plan-originating mutator — a user-launched skill whose job includes mutating user-owned files, repositories, or services without an already-approved plan — carries a short in-body pointer stanza that points here; this file owns the full protocol.

The polarity rule: a plan-consuming skill, one that executes an already-approved plan, instead carries the STOP directive in `orchestration/plan-mode-gate.md`. One skill carries exactly one polarity, because a skill cannot both stop on plan mode and enter it. The gate lives on the user-launched entry layer — a fresh-context worker never sees plan mode and cannot run the approval turn, so the entry skill gates once and delegates to gate-free workers. Codex skills are exempt — Codex has no Claude plan mode.

A skill that presents its complete proposed artifact verbatim and waits for an explicit approve/abort before writing already satisfies this contract with a stronger preview; it keeps its own gate and adds no second approval turn.

The three phases are standing instructions for the whole task, not one-time steps; apply them to every further request in the same session.

## Phase 1 — Plan

Before the first mutation of any kind, enter Claude Code plan mode (`EnterPlanMode`) and research read-only. The agent's own plan file is not such a mutation — plan mode writes one, and this phase depends on it.

Write the ordered plan: the exact commands with their flags, every file or remote object written, every step the operator must run by hand, the closing verification command, and the open risks. Ask what the plan cannot decide with `AskUserQuestion` — a choice that changes the work, never whether the plan is acceptable.

Present the plan with `ExitPlanMode` and end the turn; its approval prompt is the gate. Never pre-approve or allowlist `ExitPlanMode` — approving it automatically is the same as having no gate.

## Phase 2 — Validate

The plan is a claim about what will happen; check it against something that knows, never against your own confidence.

Preview every command that has a preview — a `--dry-run` or `--check` form, or a probe such as `git apply --check`. Validate each no-preview action against what states it instead: read-only observations of the current state and the owning docs.

Compare against the plan: the targets, their count, and the steps in their order. When an observation disagrees with the plan, stop, say what differs, and return to Phase 1. Never reconcile a surprise by widening the plan silently.

## Phase 3 — Execute

Execute in the planned order, one mutation at a time, re-observing after each and reporting what the command returned rather than that it succeeded.

Gate every step the operator must run by hand: print the exact command, say what it changes and why, wait, then re-observe before continuing.

Close with the verification command the plan named. When execution shows the plan wrong, stop and re-plan; never expand the scope of an approved plan.

## The `--no-plan` flag

`--no-plan` replaces the Phase 1 approval turn only: do not call `EnterPlanMode` or `ExitPlanMode` — plan mode's read-only hold would block Phase 3 with no approval prompt to release it. Do the same read-only research in normal mode, state the full ordered plan in the reply, then continue into Phase 2 without ending the turn. Phases 2 and 3 run unchanged.
