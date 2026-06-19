# Document the orchestration contract, findings, and guards

> Plan: skills-under-skills-env-first | Round: 2 of 3 | Complexity: L | Generated: 2026-06-18 |
> Repo: /workspaces/cog

## Context

`cog` ships Claude/Codex skills and agents that orchestrate recursive agentic work. Round 1 made the
no-backgrounding guarantee real via session env around `claude-session` (asserted by a fail-closed
`cog` preflight), removed the ineffective `codex-foreground` `PreToolUse` hook end-to-end, fixed the
`prex-stop` Stop-gate, and updated the core orchestration prose. This round records the corrected
architecture at its proper Diátaxis homes so it is durable and AI-friendly, and so any new or
refactored skill/script follows the rules.

The architecture being documented (verified facts):

- **Recursion primitives.** Skill tool = inline (same context window, 0 depth cost). Agent tool /
  foreground subagent = delegation (own context; BLOCKS the parent until the loop returns; costs 1
  depth level). Workflow tool = background parallel fan-out (not synchronous recursion). Headless
  `claude -p` = the abandoned model (reap-prone).
- **Hard 5-level subagent nesting cap** (changelog v2.1.172 "up to 5 levels deep"; v2.1.181
  "foreground subagents … now respect the same 5-level depth limit"). The live sub-agents doc prose
  still says foreground "can spawn at any depth" — it lags the v2.1.181 release; treat 5 as the cap.
- **Design corollary.** Chain skills cheaply via Skill-inline (0 depth); spend an Agent-subagent level
  only at true isolation boundaries; flatten beyond depth 5 via durable-queue iteration (the pattern
  `plan-queue-runner` already embodies) — the durable-queue **trampoline** is the documented future
  option for true unbounded composition.
- **Env-first guarantee + delegate-and-verify.** The no-backgrounding guarantee is session env around
  `claude-session`; cog asserts it fail-closed. Every orchestration boundary verifies a durable
  post-condition (re-read state), never trusting a returned summary alone.

## Previous Rounds

Round 1 (`revert-and-assert-core`) is expected to have: removed the `codex-foreground` hook
end-to-end (cog action + tests + `base.json` registration + dotfiles wrapper + core prose); added a
fail-closed `cog` env-assertion mechanic wired into `/prex`; fixed `prex-stop` with the
`stage3-impl-report.txt` check; and injected the env vars into `claude-session` `base.json`. The
env-first guarantee is therefore already real and the CORE orchestration prose already reflects it —
this round documents and codifies those decisions. (`claude-session` should have been restarted after
Round 1 so the env is in force.)

## Scope of This Round

IN scope:

- A new ADR superseding/amending ADR-0007's hook stance: the env-first model, the 5-level subagent
  cap, why a `PreToolUse` hook cannot catch runtime auto-backgrounding, and what is KEPT (`prex-stop`,
  now with the stage3 check). ADR-0007 is NOT deleted (accepted ADRs are never deleted).
- A reference doc: the orchestration contract — recursion primitives (Skill-inline vs Agent-delegate
  vs Workflow vs headless), the env requirements, the delegate-and-verify boundary contract, the
  depth budget. Preserve ALL external reference URLs (listed below).
- An explanation doc: the "one live session, foreground all the way down" call-stack mental model, the
  corrected backgrounding findings, AND the deferred durable-queue TRAMPOLINE option for going beyond
  depth 5 (Q4 — document the future possibility here).
- Short imperative guards in AGENTS.md + CLAUDE.md.
- Reconcile `docs/reference/skill-contract.md` (the SoT for authoring rules + the lint allowlist) and
  `docs/reference/codex-single-entrypoint.md` (which currently documents the now-removed
  `codex-foreground` recognition).
- Teach `.claude/skills/skill-builder/SKILL.md` the new rules so newly authored skills follow them.

OUT of scope: implementing the new `cog skill-lint` rules and the full per-skill/per-script audit +
sweep (Round 3); anything Round 1 owns.

## Current State

### Key Files

- `/workspaces/cog/docs/decisions/0007-in-session-subagent-delegation.md` — Accepted ADR. States "We
  deliberately did NOT add the backgrounding hook … the rule stays inline … as the prose safeguard."
  A new ADR supersedes/amends the hook stance (env-first); 0007 is left in place.
- `/workspaces/cog/docs/decisions/` — ADR-0001..0008 + `template.md`. New ADR is the next sequential
  number (`0009-*.md`). Use the template + ADR-0008 as format references.
- `/workspaces/cog/docs/reference/skill-contract.md` — the authoritative local skill-authoring
  contract; structural checks ~lines 59–69, premise checks ~74–90, allowlist note ~56–57. Update for
  the new rules (the exact lint encoding lands in Round 3, but the contract prose is set here).
- `/workspaces/cog/docs/reference/codex-single-entrypoint.md` — currently documents that
  `cog hook-guard codex-foreground` recognizes a Codex spawn. Reconcile: that recognition is gone
  after Round 1. Keep the `cog codex-runner run-exec|run-resume` single-entrypoint invariant and the
  `cog lint-codex-wrapper` enforcement; remove the codex-foreground recognition paragraph; point to
  the env preflight instead.
- `/workspaces/cog/docs/explanation/architecture.md` and `/workspaces/cog/docs/README.md` (index
  only) — the new explanation doc lands under `docs/explanation/`; add it to the index.
- `/workspaces/cog/AGENTS.md` — has "Skill and Script Responsibility Boundary" (~lines 25–32) and "no
  git commands" (~44–45). `/workspaces/cog/CLAUDE.md` — `@AGENTS.md` + the non-negotiable
  skills-orchestrate/cog-does-mechanics line. Add short imperative guards.
- `/workspaces/cog/.claude/skills/skill-builder/SKILL.md` — the canonical skill-builder (`model:
  opus`, `effort: low`); already runs `cog skill-builder-validate` + `cog skill-lint` and reads
  `docs/reference/skill-contract.md`. Teach the new rules in its interview/rules.

### Existing Patterns

- ADRs: accepted ADRs are never deleted; record changed decisions with a new superseding ADR.
  Markdown fenced blocks declare a language (MD040); use `text` when none applies.
- `docs/README.md` is an index only — add the new explanation/reference docs to it; do not put
  content there.
- Keep guards in AGENTS.md/CLAUDE.md short and imperative — they are loaded into every agent's
  context; verbosity is a cost.
- External reference URLs to preserve verbatim in the new docs:
  - https://code.claude.com/docs/en/tools-reference
  - https://code.claude.com/docs/en/env-vars
  - https://code.claude.com/docs/en/sub-agents
  - https://code.claude.com/docs/en/changelog  (v2.0.19, v2.1.163, v2.1.172, v2.1.181)
  - https://code.claude.com/docs/en/hooks  and  https://code.claude.com/docs/en/hooks-guide
  - https://code.claude.com/docs/en/interactive-mode
  - https://code.claude.com/docs/en/workflows
  - https://developers.openai.com/codex/cli/reference

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: document-orchestration-contract`) `status` to
`doing`.

### Step 1: Write the superseding ADR (0009)

Create `/workspaces/cog/docs/decisions/0009-<slug>.md` (next sequential number) recording: the
env-first model; the hard 5-level subagent cap (v2.1.172/v2.1.181, noting the live doc prose lags);
why a `PreToolUse(Bash)` hook cannot catch runtime auto-backgrounding (it sees only requested input);
cog's role as fail-closed runtime assertion only; what is KEPT (`prex-stop`, fixed with the stage3
check); the Skill-inline vs Agent-delegate vs Workflow vs headless distinction; the durable-queue
trampoline as a deferred future option; and the relation to ADR-0007 and ADR-0008. Mark it as
superseding/amending the hook stance of ADR-0007; leave ADR-0007 in place. Follow the ADR template.

### Step 2: Write the reference doc (orchestration contract)

Create `/workspaces/cog/docs/reference/orchestration-contract.md` describing: the recursion-primitive
table (Skill-inline 0-depth / Agent-delegate 1-level, cap 5 / Workflow background fan-out / headless
`claude -p` abandoned); the required session env and minimum values
(`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` and/or `BASH_*_TIMEOUT_MS` ≥ 600000) and that
`claude-session` config is the SoT for env/hook registration while cog asserts runtime state; the
delegate-and-verify boundary contract; and the depth budget. Preserve ALL external URLs above.

### Step 3: Write the explanation doc (mental model + deferred trampoline)

Create `/workspaces/cog/docs/explanation/foreground-orchestration.md` covering: the "one live
session, foreground all the way down" call-stack mental model; the corrected backgrounding findings
(auto-background is real and runtime; a PreToolUse hook can't catch it; env is the lever; the field
demonstration); and the deferred durable-queue TRAMPOLINE option for exceeding depth 5 (documented as
a future possibility, not built — per Q4). Add it (and the reference doc) to `docs/README.md`.

### Step 4: Add guards to AGENTS.md and CLAUDE.md

Add short imperative rules to `/workspaces/cog/AGENTS.md` (reflect via `/workspaces/cog/CLAUDE.md` as
needed): env-first (never rely on a `PreToolUse` hook for backgrounding); never background a Codex /
long orchestration call; Skill-inline for same-context chaining vs Agent-delegate (foreground) only
at isolation boundaries; track the 5-level depth budget; verify a durable post-condition at every
boundary; deterministic mechanics belong in cog. Keep them concise.

### Step 5: Reconcile skill-contract.md and codex-single-entrypoint.md

Update `/workspaces/cog/docs/reference/skill-contract.md` for the new authoring rules (keep it the SoT
for the lint allowlist + checks; the mechanical encoding lands in Round 3). In
`/workspaces/cog/docs/reference/codex-single-entrypoint.md`, remove the `cog hook-guard
codex-foreground` recognition paragraph; keep the single-entrypoint invariant and `cog
lint-codex-wrapper` enforcement; point to the env preflight.

### Step 6: Teach skill-builder the new rules

Update `/workspaces/cog/.claude/skills/skill-builder/SKILL.md` so the authoring interview and rules
teach the new constraints: read the orchestration contract when a skill spawns Codex, delegates,
queues, or orchestrates; choose Skill-inline vs Agent-delegate deliberately; include the env-preflight
requirement where relevant; never reintroduce `codex-foreground`; preserve deterministic mechanics in
cog. Keep mechanics delegated to cog; keep the existing `cog skill-builder-validate` + `cog
skill-lint` gates.

### Step 7: Run gates and commit

Run `just lint` and `just test` until clean. Commit via `/gc`; the executor must NOT run git directly.

### Final Step: Update the queue

In this plan's `queue-rounds.yaml`, set this round's (`item: document-orchestration-contract`) `status` to
`done`.

## Acceptance Criteria

- [ ] A new ADR (`0009-*.md`) records the env-first model, the 5-level cap, why a PreToolUse hook is
      the wrong tool, and the kept/fixed `prex-stop`; supersedes/amends ADR-0007's hook stance;
      ADR-0007 left in place.
- [ ] `docs/reference/orchestration-contract.md` documents the recursion primitives + env
      requirements + delegate-and-verify boundary + depth budget, with ALL external URLs preserved.
- [ ] `docs/explanation/foreground-orchestration.md` documents the foreground call-stack mental
      model, the corrected findings, and the deferred durable-queue trampoline; both new docs are
      listed in `docs/README.md`.
- [ ] AGENTS.md (and CLAUDE.md as needed) carry the new concise imperative guards.
- [ ] `skill-contract.md` reflects the new authoring rules; `codex-single-entrypoint.md` no longer
      documents the removed `codex-foreground` recognition.
- [ ] `.claude/skills/skill-builder/SKILL.md` teaches the new rules.
- [ ] `just lint` and `just test` pass.
- [ ] This plan's `queue-rounds.yaml` shows round `document-orchestration-contract` as `done`.

## Next Round

`encode-lint-and-sweep` encodes the documented rules as mechanical `cog skill-lint` checks (+ tests)
and runs the full per-skill + per-script audit/sweep to clear every violation with no leftovers.
