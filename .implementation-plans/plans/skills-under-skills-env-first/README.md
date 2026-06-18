# Skills Under Skills, Processes Under Processes — the lean correct way

> Complexity: L | Rounds: 3 | Generated: 2026-06-18 | Repo: /workspaces/cog

## Problem Statement

`cog` ships Claude/Codex skills and Claude agents that orchestrate recursive, multi-step agentic
work (`prex`, `plan-queue-runner`, `review-loop`, `ask`, `plan-writer-multi`) by delegating to
nested foreground subagents and by driving Codex through `cog codex-runner`. We want this — skills
calling skills, processes under processes — to work the lean, correct way, and to revert a previous
attempt that did not work, with no leftovers.

A previous architectural attempt tried to GUARANTEE that long-running Codex Bash calls are never
backgrounded by registering a `PreToolUse(Bash)` hook (`cog hook-guard codex-foreground`, deployed
via a `guard-codex-foreground.sh` wrapper and registered in the `claude-session` `base.json` layer).
Verified research shows this hook is **structurally insufficient** for its stated purpose:

- Claude Code (changelog v2.0.19) **auto-backgrounds long-running Bash commands at RUNTIME**
  (threshold `BASH_DEFAULT_TIMEOUT_MS`, default 120000ms; per-call ceiling `BASH_MAX_TIMEOUT_MS`,
  default 600000ms).
- A `PreToolUse(Bash)` hook only sees the model's **requested** `run_in_background`/`timeout`
  **before** the call runs; the harness auto-backgrounds **later**, at runtime, after the hook
  already allowed the call. Demonstrated in the field: a `prex` Stage-3 Codex call requested
  foreground + `timeout: 600000` (passed the hook) yet was still auto-backgrounded, breaking
  Stage 3→4 sequencing. The hook was registered and active — and still could not prevent it.

The real lever is **session ENV**, owned by the `claude-session` wrapper that launches `claude`:
`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` disables all background-task functionality (keeps spawns
synchronous, stops bash auto-backgrounding); raising `BASH_DEFAULT_TIMEOUT_MS` /
`BASH_MAX_TIMEOUT_MS` pushes the auto-background threshold past the longest Codex call.

This plan implements the correct, lean feature from scratch and reverts the failed attempt with **no
leftovers**:

1. **Env-first guarantee.** The no-backgrounding guarantee becomes session env around
   `claude-session`, asserted at runtime by a fail-closed `cog` preflight. The ineffective
   `codex-foreground` `PreToolUse` hook is removed end-to-end. The genuinely-useful `prex-stop`
   Stop-gate is kept and fixed (it currently misses a `stage3-impl-report.txt` completeness check).
2. **Harness setup lives around `claude-session`, not `cog`.** Env vars and hook registration live in
   the `claude-session` config in the `/home/gbasso/.dotfiles` repo. `cog` only ASSERTS env; it never
   writes Claude settings. This makes the plan multi-repo (cog + dotfiles satellite).
3. **Document everything, AI-friendly and self-enforcing.** Record the corrected findings and the
   recursion-primitive model at their proper Diátaxis homes (ADR superseding ADR-0007's hook stance;
   reference contract; explanation mental model + the deferred durable-queue trampoline for going
   beyond Claude Code's hard 5-level subagent cap), add short imperative guards to AGENTS.md and
   CLAUDE.md, encode the new rules as mechanical `cog skill-lint` checks (gated by pre-commit), teach
   `skill-builder`, and run a full per-skill + per-script audit/sweep so every existing and future
   skill/script conforms.

This is a **refinement** of the existing, correct architecture (ADR-0007's in-session foreground
subagents, `claude-delegate`, verify-don't-set), **not a teardown**. The only thing torn out is the
ineffective `codex-foreground` `PreToolUse` hook and its overstated "the hook is the guarantee"
prose.

## Strategy

Three cohesive rounds on clean dependency seams. Round 1 (`revert-and-assert-core`) lands the
deterministic core atomically across both repos: inject the env into `claude-session` `base.json`
**first** (so new sessions get it), add the fail-closed `cog` env-preflight, remove the
`codex-foreground` hook end-to-end (cog action + tests + base.json registration + dotfiles wrapper +
require token + core prose), and fix the `prex-stop` stage3 gap. Round 2 (`document-orchestration-
contract`) documents the now-settled decisions (ADR + reference + explanation + guards +
skill-builder). Round 3 (`encode-lint-and-sweep`) encodes the rules as `cog skill-lint` checks, then
runs the full per-skill + per-script audit/sweep and verifies no leftovers. The heavy sweep gets its
own `/prex` session so its completeness is independently verifiable — the explicit "no leftovers"
requirement makes that completeness load-bearing.

**Env-rollout sequencing (critical, applies across rounds).** Claude Code applies env at
`claude-session` launch. So after Round 1 edits `base.json`, the new env only reaches a **freshly
launched** session. To avoid the new fail-closed preflight deadlocking the plan's own later rounds,
Round 1 (a) injects the `base.json` env first, (b) introduces the preflight in **advisory/warn**
mode for the current session and documents an explicit "restart `claude-session` to pick up the env,
then the preflight is fail-closed for new sessions" step. The fail-closed behavior is correct for
all future sessions; it must not brick the in-flight execution of this very plan.

## Rounds

The authoritative order and status live in `QUEUE.yaml`. Overview:

1. `revert-and-assert-core.md` — Inject env into `claude-session` `base.json`; add the fail-closed
   `cog` env-preflight (advisory-now / fail-closed-for-new-sessions); remove the `codex-foreground`
   hook end-to-end (cog action, tests, base.json registration, dotfiles wrapper, require token, core
   orchestration prose in prex/plan-queue-runner/claude-delegate); fix the `prex-stop` stage3 gap.
   Multi-repo: `/workspaces/cog` + `/home/gbasso/.dotfiles`.
2. `document-orchestration-contract.md` — ADR-0009 (supersedes ADR-0007's hook stance); reference
   doc (recursion primitives + env requirements + delegate-and-verify + depth budget; all external
   URLs preserved); explanation doc (foreground call-stack mental model + corrected findings +
   deferred durable-queue trampoline); AGENTS.md + CLAUDE.md guards; reconcile `skill-contract.md`
   and `codex-single-entrypoint.md`; teach `skill-builder`.
3. `encode-lint-and-sweep.md` — Encode the new rules as `cog skill-lint` checks + tests; run the
   full per-skill (~30) + per-script (~66) audit/sweep; clear every violation (including any
   remaining foreground/600000/reap prose in review-loop, ask, plan-writer-multi); verify no
   leftovers across both repos.

## Execution Commands

```bash
# Execute the next todo round (executor reads QUEUE.yaml, runs the first `todo` round, then stops):
/prex -ar @.implementation-plans/plans/skills-under-skills-env-first/

# Or target a specific round file directly:
/prex -ar .implementation-plans/plans/skills-under-skills-env-first/revert-and-assert-core.md
/prex -ar .implementation-plans/plans/skills-under-skills-env-first/document-orchestration-contract.md
/prex -ar .implementation-plans/plans/skills-under-skills-env-first/encode-lint-and-sweep.md
```

This plan writes into more than one repo. Run it through `/plan-queue-runner`, which guards every
declared repo's clean tree and commits each via `/gc -a --repo <sat>` — the inner `QUEUE.yaml`
declares `/home/gbasso/.dotfiles` as a satellite.

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for
a single `/prex` session. Do not implement multiple rounds in one session.

When `/prex` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `QUEUE.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh `/prex` session is launched for any subsequent round.

After Round 1, **restart `claude-session`** before running Round 2 so the new `base.json` env is in
force (see the env-rollout sequencing note above).

## Decisions & Constraints

- **Executor: prex (EF 1.5).** Sized accordingly; XL is unreachable (max grade L, ≤3 rounds). Both
  independent draft engines graded this L; the 3-round split was confirmed with the maintainer to
  isolate the load-bearing no-leftovers sweep.
- **Q1 — Env-first, remove the hook.** Session env (`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` +
  bumped `BASH_*_TIMEOUT_MS`) is the real guarantee, enforced by a fail-closed `cog` preflight. The
  `codex-foreground` `PreToolUse` hook is removed end-to-end (cog action + its tests + base.json
  registration + dotfiles wrapper script + the `require hook-guard` dependency where tied to it +
  every "the hook is the guarantee" prose claim). Keep and fix the `prex-stop` Stop-gate.
- **Q2 — `cog` asserts; `claude-session` owns settings.** Harness env + hook registration live in the
  `claude-session` config in `/home/gbasso/.dotfiles`, not managed by cog. Verified: the wrapper
  exports each key of the merged `env` block before launching `claude`
  (`claude-session-develop/lib/commands/cmd_run.sh`, `lib/functions/fn_apply_profile_env.sh`), so
  adding env vars to a settings layer's `env` block is sufficient — no wrapper source change is
  needed. cog's role is a runtime preflight that ASSERTS env and fails closed.
- **Q3 — Full per-skill/per-script audit + encode rules as lint + sweep.** Do both: a thorough
  per-item audit AND mechanical `cog skill-lint` rule encoding AND a sweep that applies/clears lint
  across all skills and scripts.
- **Q4 — Defer the trampoline, document it.** Document the depth budget (Claude Code's hard 5-level
  subagent cap) and the durable-queue trampoline as a FUTURE option for going beyond depth 5; do not
  build it now. Document it alongside the corrected findings (the explanation doc).
- **ADR-0008 boundary holds for new code.** The env-assertion belongs in a `cog` subcommand /
  `cog::fn::*` helper, not inline shell. New `skill-lint` premise rules go in
  `lib/commands/cmd_skill_lint.sh` + `lib/functions/fn_skill.sh`.
- **Repo conventions.** Command modules `lib/commands/cmd_<slug>.sh` + `cog::cmd::<slug>` + line-2
  `: 'desc: ...'` sentinel; shared helpers `cog::fn::*` in `lib/functions/`; dash↔underscore loader
  mapping; markdown fenced blocks declare a language (MD040), use `text` when none applies; accepted
  ADRs are never deleted (supersede instead); `just lint` / `just test` are the quality SoT
  (pre-commit).
- **No git commands by the orchestrator.** Commits happen via `/gc`; multi-repo commits via
  `/plan-queue-runner` (the dotfiles satellite). The executor must not run git directly.
- **Keep the genuinely-correct architecture.** ADR-0007's in-session foreground subagents,
  `claude-delegate`, and verify-don't-set stay. This is a correction of ADR-0007's hook stance, not
  a teardown.

## Rejected Alternatives

- **Keep a `PreToolUse(Bash)` hook to enforce foreground (as defense-in-depth).** Rejected:
  structurally insufficient — the hook only sees the requested input at PreToolUse; the harness
  auto-backgrounds at runtime after the hook allowed the call. Demonstrated to fail in the field
  even while registered. Keeping it conflicts with the "no leftovers" requirement.
- **Have `cog` manage/write Claude `settings.json`.** Rejected per Q2: the harness setup is owned by
  `claude-session` in `/home/gbasso/.dotfiles`. cog only asserts env at runtime.
- **Patch the `claude-session` wrapper source to inject env.** Rejected: unnecessary. The wrapper
  already exports every key of the merged `env` block; adding keys to `base.json`'s `env` suffices.
- **Build the durable-queue trampoline now to exceed the 5-level cap.** Rejected per Q4: defer it;
  document the future possibility. Most recursion chains via Skill-inline (0 depth) and spend an
  Agent-subagent level only at true isolation boundaries, so the 5-level cap is not yet binding.
- **2-round split (revert; then docs+lint+full-audit combined).** Rejected: cramming all
  documentation plus the full ~96-item audit/sweep into one prex 600s round risks a half-finished
  sweep — directly conflicting with the no-leftovers requirement. The sweep gets its own round.

## Risks & Edge Cases

- **Env-rollout deadlock (handled).** A fail-closed env-preflight wired into `/prex` bootstrap would
  block this plan's own later rounds because env applies only at `claude-session` launch. Handled:
  Round 1 injects `base.json` env first and introduces the preflight advisory-now /
  fail-closed-for-new-sessions, with an explicit restart step before Round 2. NEEDS HANDLING.
- **Multi-repo coordination.** Changes span `/workspaces/cog` and `/home/gbasso/.dotfiles`. The
  dotfiles edits (base.json env + removing the PreToolUse registration + deleting the wrapper) must
  land or the runtime env assertion has nothing to assert. Commit both via `/plan-queue-runner`
  satellites; never run git directly. NEEDS HANDLING.
- **Stale deployed copies.** The dotfiles repo also carries parallel copies of cog skills/agents
  (`dotfiles/claude/.claude/skills/...`, `.../agents/...`) deployed to `~/.claude/skills` +
  `~/.agents/skills`; `claude-session` symlinks skills/agents/hooks into each session dir. Prose
  edits must reach deployed copies, and the removed `guard-codex-foreground.sh` must be gone from
  both SoT and the deployed `~/.claude/hooks/`. Confirm the deploy path. NEEDS HANDLING.
- **Pre-commit gate churn.** Extending `cog skill-lint` propagates new rules to ALL skills via the
  local pre-commit hook — the sweep must clear every newly-flagged violation or `just lint` fails.
  NEEDS HANDLING (sweep is Round 3's terminal step).
- **Fail-closed preflight false positives.** If the assertion is too strict it could block valid
  sessions. Define it precisely: PASS when background tasks are disabled
  (`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`) OR both `BASH_*_TIMEOUT_MS` are set past the Codex
  window; FAIL otherwise. NEEDS HANDLING.
- **`prex-stop` regression.** Adding the `stage3-impl-report.txt` check must not break existing
  `prex-stop` behavior (orphaned/corrupt lock auto-clean, PID-scoping). Extend tests, don't replace.
  NEEDS HANDLING.
- **ADR-0007 supersession.** ADR-0007 is Accepted and must not be deleted. Record the changed
  decision with a new superseding ADR that flips only the hook stance. NEEDS HANDLING.
- **Inventory drift.** Skill/script counts (~30 skills, ~66 scripts) are approximate. Round 3 must
  inventory the actual checkout at execution time, not rely on these numbers. NEEDS HANDLING.

## Completion

When all rounds are done, set each round `done` in this plan's `QUEUE.yaml` and set this plan `done`
in the top-level `.implementation-plans/QUEUE.yaml`. Nothing moves on disk.
