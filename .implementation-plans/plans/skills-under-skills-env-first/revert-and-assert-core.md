# Revert the codex-foreground hook and assert the env-first guarantee

> Plan: skills-under-skills-env-first | Round: 1 of 3 | Complexity: L | Generated: 2026-06-18 |
> Repo: /workspaces/cog

## Context

`cog` ships orchestration skills that drive nested foreground subagents and Codex via
`cog codex-runner`. A previous attempt tried to guarantee Codex Bash calls are never backgrounded
using a `PreToolUse(Bash)` hook (`cog hook-guard codex-foreground`, registered in the
`claude-session` `base.json` layer). This is structurally insufficient: Claude Code (changelog
v2.0.19) auto-backgrounds long-running Bash at RUNTIME (threshold `BASH_DEFAULT_TIMEOUT_MS` default
120000ms; ceiling `BASH_MAX_TIMEOUT_MS` default 600000ms), while a `PreToolUse` hook only sees the
model's REQUESTED `run_in_background`/`timeout` BEFORE the call runs. A `prex` Stage-3 Codex call
passed the hook (foreground + timeout 600000) yet was still auto-backgrounded, breaking Stage 3→4
sequencing — the hook was registered and active and still could not prevent it.

The real lever is SESSION ENV, owned by the `claude-session` wrapper that launches `claude`:
`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` (disable all background tasks; keeps spawns synchronous)
plus raising `BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS`. This round implements the env-first
guarantee end-to-end and reverts the failed hook with no leftovers, while keeping and fixing the
genuinely-useful `prex-stop` Stop-gate. Harness env + hook registration live in the `claude-session`
config in the `/home/gbasso/.dotfiles` repo (this is a multi-repo round); `cog` only ASSERTS env at
runtime via a fail-closed preflight — it never writes Claude settings.

This is a correction of ADR-0007's hook stance, NOT a teardown of the in-session foreground subagent
architecture (`claude-delegate`, verify-don't-set stay).

**Env-rollout sequencing — read before implementing.** Claude Code applies env at `claude-session`
launch. Editing `base.json` only affects a freshly launched session. A fail-closed preflight wired
into `/prex` bootstrap would therefore block this plan's own Rounds 2–3 (which run via `/prex` in the
current session, where the new env is not yet present). Therefore: inject the `base.json` env FIRST,
and introduce the preflight so it is **advisory (warn, non-blocking) when the env is absent in the
current session** but **fail-closed for newly launched sessions**. Document the explicit "restart
`claude-session` after this round" step. Do not let the new assertion brick the in-flight plan.

## Previous Rounds

This is the first round — no prior rounds.

## Scope of This Round

IN scope:

- Inject the harness env vars into the `claude-session` `base.json` `env` block and REMOVE the
  `PreToolUse` `guard-codex-foreground.sh` registration there; KEEP the `Stop` `prex-stop-gate.sh`
  registration. Delete the dotfiles `guard-codex-foreground.sh` wrapper (SoT + deployed). (Satellite
  repo: `/home/gbasso/.dotfiles`.)
- Add a fail-closed `cog` env-assertion mechanic (a `cog` subcommand and/or `cog::fn::*` helper) that
  asserts the no-backgrounding guarantee (background tasks disabled OR both `BASH_*_TIMEOUT_MS` set
  past the Codex window), with advisory-vs-fail-closed behavior per the sequencing note. Wire it into
  `/prex` bootstrap.
- Remove the `codex-foreground` sub-action from `cog hook-guard` (cog action), its tests, and the
  `hook-guard` token in `prex`'s `cog require` line where tied to it (keep `hook-guard` only because
  `prex-stop` survives in the same module).
- Fix the `prex-stop` Stop-gate: add the missing `stage3-impl-report.txt` completeness check; keep
  orphaned/corrupt-lock auto-clean and PID-scoping. Extend its tests.
- Remove the core "the hook is the guarantee" / `codex-foreground` prose and replace with the
  env-first guarantee + in-session foreground discipline in the CORE orchestration surfaces:
  `prex/SKILL.md` (+ its `references/stage-2-through-5-details.md`), `runner-queue/SKILL.md`,
  and `agents/claude/claude-delegate.md`.

OUT of scope (later rounds): the ADR/reference/explanation docs, AGENTS/CLAUDE guards,
`skill-contract.md`/`codex-single-entrypoint.md` reconcile, `skill-builder` teach-up (Round 2); the
new `cog skill-lint` rules and the full per-skill/per-script audit + sweep — including the
review-loop / ask / plan-writer-multi prose still carrying foreground/600000/reap wording (Round 3).

## Current State

### Key Files

- `/workspaces/cog/lib/commands/cmd_hook_guard.sh` — two sub-actions. `codex-foreground` (const
  `__COG_HOOK_GUARD_CODEX_MIN_TIMEOUT_MS=600000` ~line 4; `__cog_hook_guard_codex_foreground()`
  ~lines 38–67; dispatch arm `codex-foreground)` in `cog::cmd::hook_guard()` ~lines 140–143) is the
  ineffective feature to REMOVE. `prex-stop` (`__cog_hook_guard_prex_stop()` ~lines 69–136) is KEPT.
  Its completeness check currently lists only three artifacts and MUST gain a fourth:

  ```bash
  [[ -s "$run_dir/stage1-plan.txt" ]] || missing+=("Stage 1: Plan")
  [[ -s "$run_dir/stage2-reviewed-plan.md" ]] || missing+=("Stage 2: Reviewed plan")
  [[ -s "$run_dir/stage4-review.md" ]] || missing+=("Stage 4: Implementation review")
  ```

  After removing `codex-foreground`, also prune its `__cog_hook_guard_usage()` text, the dispatch
  arm, and update the line-2 `: 'desc: ...'` sentinel (currently "Deterministic PreToolUse/Stop hook
  decisions.") to a Stop-only description.

- `/workspaces/cog/test/unit/cmd_hook_guard.bats` and
  `/workspaces/cog/test/integration/hook_guard.bats` — cover BOTH sub-actions. Remove the
  codex-foreground assertions; keep and EXTEND the prex-stop assertions (add a case that blocks when
  stage1/stage2/stage4 exist but `stage3-impl-report.txt` is missing, and update the all-present
  allow case to create all four artifacts).

- `/workspaces/cog/test/integration/help_snapshots.bats` — snapshots the `hook-guard` description;
  update if the sentinel changes.

- `/workspaces/cog/lib/commands/cmd_preflight.sh` — `cog::cmd::preflight()` dispatches
  `codex|sandbox|git|agents` sub-checks, each writing a JSON fragment via `__cog_preflight_write` and
  raising via `cog::fn::error_raise`. This is the natural home for a new env-assertion (e.g.
  `cog preflight claude-env <out.json>`). Follow the existing fragment/`error_raise` patterns.

- `/workspaces/cog/lib/commands/cmd_require.sh` — `cog require` only checks `cmd_<name>.sh` existence
  (`__cog_require_command_path`, ~line 10). The `hook-guard` token survives because `prex-stop` keeps
  the module; reconcile `prex`'s require line wording so it no longer implies backgrounding
  enforcement.

- `/workspaces/cog/skills/claude/prex/SKILL.md` — the discipline block ~lines 49–66 ends with "the
  prose remains as the rationale; the hook is the guarantee" and names
  `cog hook-guard codex-foreground` `PreToolUse(Bash)`. Line ~101:
  `cog require hook-guard codex-runner rundir lock prex-parse-args prex-tsk-resolve`. Rewrite the
  discipline block to state the ENV-first guarantee (the env is the guarantee; foreground discipline
  remains the in-session contract) and add the `cog preflight claude-env` assertion after run-dir
  creation, before Stage 1. `references/stage-2-through-5-details.md` references the `prex-stop`
  dependency (`stage4-review.md`) — keep that; remove any `codex-foreground` claim.

- `/workspaces/cog/skills/claude/runner-queue/SKILL.md` — ~lines 26–38 reference "prevented
  deterministically by the `cog hook-guard codex-foreground` `PreToolUse(Bash)` hook". Replace with
  the env-first guarantee; keep the nested-subagent + verify-don't-set prose.

- `/workspaces/cog/agents/claude/claude-delegate.md` — ~lines 30–38 carry "FOREGROUND … hook-guard
  codex-foreground enforces this" prose. Replace with env-first + foreground discipline.

- `/home/gbasso/.dotfiles/claude-session/.config/claude-session/settings/base.json` — `env` currently
  holds only `CLAUDE_SESSION_OAUTH_CMD`; `hooks.PreToolUse[0]` matcher `Bash` registers
  `bash -c '"$HOME/.claude/hooks/guard-codex-foreground.sh"'` (timeout 5); `hooks.Stop[0]` registers
  `prex-stop-gate.sh` (KEEP); `permissions.defaultMode: "bypassPermissions"`. Add
  `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` (+ `BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS`) to
  `env`; REMOVE the `hooks.PreToolUse` block. Committed in the `/home/gbasso/.dotfiles` git repo.

- `/home/gbasso/.dotfiles/claude/.claude/hooks/guard-codex-foreground.sh` — the thin shim wrapper
  (SoT). DELETE it (and the deployed `~/.claude/hooks/guard-codex-foreground.sh`). KEEP
  `prex-stop-gate.sh`.

- `/home/gbasso/Projects/_sources/claude-session-develop` — the wrapper source. Verified: it composes
  ordered settings layers and exports each key of the merged `env` block before launching `claude`
  (`lib/commands/cmd_run.sh`, `lib/functions/fn_apply_profile_env.sh`). CONFIRM no source change is
  needed — env-block injection is sufficient.

### Existing Patterns

- cog command modules: `lib/commands/cmd_<slug>.sh`, handler `cog::cmd::<slug>`, line-2
  `: 'desc: ...'` sentinel (root help/reference/man/completion drift depend on it). Shared helpers
  `cog::fn::*` in `lib/functions/`. Loader maps dash command names to underscore module/handler.
- Preflight checks emit JSON fragments and raise via `cog::fn::error_raise`; match this shape for the
  new env-assertion. Keep deterministic logic in cog (ADR-0008), not inline shell in skills.
- Hook deny contract: `PreToolUse` exit 2 + stderr reason blocks, exit 0 allows; `Stop` blocks via
  `{"decision":"block","reason":...}` on stderr + exit 2.
- Markdown fenced blocks must declare a language (MD040); use `text` when none applies.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: revert-and-assert-core`) `status` to `doing`.

### Step 1: Inject the env into claude-session base.json (dotfiles satellite, do this first)

In `/home/gbasso/.dotfiles/claude-session/.config/claude-session/settings/base.json`: add to the
`env` block `"CLAUDE_CODE_DISABLE_BACKGROUND_TASKS": "1"` and
`"BASH_DEFAULT_TIMEOUT_MS": "600000"`, `"BASH_MAX_TIMEOUT_MS": "600000"` (values per the precise
assertion in Step 3). REMOVE the `hooks.PreToolUse[0]` `guard-codex-foreground.sh` registration; KEEP
`hooks.Stop[0]` (`prex-stop-gate.sh`). Confirm (by reading `cmd_run.sh` / `fn_apply_profile_env.sh`)
that the wrapper source needs no change. Doing this first means a restarted session satisfies the
preflight before Round 2.

### Step 2: Delete the dotfiles hook wrapper (SoT + deployed)

Delete `/home/gbasso/.dotfiles/claude/.claude/hooks/guard-codex-foreground.sh` and the deployed
`~/.claude/hooks/guard-codex-foreground.sh`. KEEP `prex-stop-gate.sh` in both locations. Confirm no
stale duplicate remains.

### Step 3: Add the fail-closed cog env-assertion mechanic

In `/workspaces/cog/lib/commands/cmd_preflight.sh` (or a shared `cog::fn::*` helper), add a
deterministic check (e.g. `cog preflight claude-env <out.json>`) that PASSES when
`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` is in force OR both `BASH_DEFAULT_TIMEOUT_MS` and
`BASH_MAX_TIMEOUT_MS` are integers ≥ 600000; otherwise FAILS CLOSED (non-zero, with the observed
values in the JSON/error detail; no Claude settings-file access required). Update
`__cog_preflight_usage` + dispatch, the command-surface mirrors, help snapshots, and the man/reference
summary if a new subcommand name is introduced. Keep deterministic logic in cog (ADR-0008).

### Step 4: Fix the prex-stop Stop-gate (add the stage3 check)

In `/workspaces/cog/lib/commands/cmd_hook_guard.sh`, in `__cog_hook_guard_prex_stop()`, add a
`stage3-impl-report.txt` completeness check between the stage2 and stage4 checks so the block reason
reflects workflow order. Do not disturb orphaned/corrupt-lock auto-clean or PID-scoping.

### Step 5: Remove the codex-foreground sub-action from cog hook-guard

In the same file, delete `__cog_hook_guard_codex_foreground()`, the
`__COG_HOOK_GUARD_CODEX_MIN_TIMEOUT_MS` const, the `codex-foreground)` dispatch arm in
`cog::cmd::hook_guard()`, and the `codex-foreground` lines from `__cog_hook_guard_usage()`. Update the
line-2 desc sentinel to a Stop-only description. The module survives because `prex-stop` remains.

### Step 6: Update tests

In `/workspaces/cog/test/unit/cmd_hook_guard.bats` and
`/workspaces/cog/test/integration/hook_guard.bats`, remove all codex-foreground assertions; keep the
prex-stop assertions; add a case asserting the new `stage3-impl-report.txt` completeness check blocks
when stage1/2/4 exist but stage3 is missing, and update the all-present allow case to create all four
artifacts. Add coverage for the new env preflight (export env vars in the test process). Update
`test/integration/help_snapshots.bats` if the sentinel changed.

### Step 7: Wire the env preflight into prex bootstrap and rewrite the core hook prose

- In `/workspaces/cog/skills/claude/prex/SKILL.md`, rewrite the discipline block (~lines 49–66) to the
  env-first guarantee + in-session foreground discipline; remove the "hook is the guarantee" /
  `cog hook-guard codex-foreground` `PreToolUse` claim. Add the `cog preflight claude-env` assertion
  after run-dir creation, before Stage 1 (advisory-now / fail-closed-for-new-sessions per the
  sequencing note). Reconcile the `cog require` line (~line 101): `hook-guard` stays only because
  `prex-stop` keeps the module; drop wording implying it gates backgrounding.
- In `/workspaces/cog/skills/claude/prex/references/stage-2-through-5-details.md`, keep the `prex-stop`
  dependency reference; remove any `codex-foreground` claim.
- In `/workspaces/cog/skills/claude/runner-queue/SKILL.md` (~lines 26–38) and
  `/workspaces/cog/agents/claude/claude-delegate.md` (~lines 30–38), replace hook claims with the
  env-first guarantee + foreground discipline. (review-loop / ask / plan-writer-multi prose is swept
  in Round 3.)

### Step 8: Verify no leftovers (this round's surface) and run gates

Grep `/workspaces/cog` and `/home/gbasso/.dotfiles` for `codex-foreground`, `guard-codex-foreground`,
and "hook is the guarantee"; confirm the only surviving `hook-guard` references are the `prex-stop`
ones plus the Round-3-scoped skill prose still pending sweep. Run `just lint` and `just test`
(pre-commit is the quality SoT). Commit via `/gc` (cog repo) and the dotfiles satellite via
`/runner-queue` / `/gc -a --repo /home/gbasso/.dotfiles` — the executor must NOT run git
directly.

### Final Step: Update the queue

In this plan's `queue-rounds.yaml`, set this round's (`item: revert-and-assert-core`) `status` to `done`.
Then restart `claude-session` before Round 2 so the new `base.json` env is in force.

## Acceptance Criteria

- [ ] `base.json` `env` carries `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` (+ `BASH_*_TIMEOUT_MS`) and
      no longer registers `guard-codex-foreground.sh`; the `Stop` `prex-stop-gate.sh` registration is
      kept; the wrapper source is unchanged (confirmed).
- [ ] `guard-codex-foreground.sh` is deleted from the dotfiles SoT and the deployed `~/.claude/hooks/`;
      `prex-stop-gate.sh` remains; no stale duplicate remains.
- [ ] A fail-closed `cog` env-assertion mechanic exists in cog (not inline shell), passes when the
      guarantee is in force, fails closed otherwise, and is wired into `/prex` bootstrap
      advisory-now / fail-closed-for-new-sessions.
- [ ] `cog hook-guard codex-foreground` no longer exists (sub-action, const, dispatch arm, usage text,
      sentinel updated); `cog hook-guard prex-stop` still works.
- [ ] `prex-stop` now treats a missing/empty `stage3-impl-report.txt` as incomplete; existing
      stage1/stage2/stage4 checks, orphaned-lock auto-clean, and PID-scoping unchanged.
- [ ] `cmd_hook_guard.bats` (unit + integration) have no codex-foreground assertions and include the
      stage3 prex-stop case; env-preflight coverage added; `just test` passes.
- [ ] No "the hook is the guarantee" / `codex-foreground` `PreToolUse` claim remains in `prex`
      (SKILL.md + stage-2-through-5 reference), `runner-queue`, or `claude-delegate`; replaced
      with env-first prose.
- [ ] `just lint` passes (no MD040 violations; shellcheck clean).
- [ ] This plan's `queue-rounds.yaml` shows round `revert-and-assert-core` as `done`.

## Next Round

`document-orchestration-contract` records the now-settled decisions (ADR-0009 superseding ADR-0007's
hook stance; reference contract; explanation mental model + the deferred durable-queue trampoline),
adds AGENTS/CLAUDE guards, reconciles `skill-contract.md` / `codex-single-entrypoint.md`, and teaches
`skill-builder`. Restart `claude-session` before running it.
