# `cog init` Subcommand (DRY against `doctor`)

> Plan: cog-contract-and-spec-uplift | Round: 2 of 4 | Complexity: L (override) | Generated: 2026-06-19 |
> Repo: /workspaces/cog

## Context

`cog` is a machine-facing Bash CLI whose self-documentation surfaces (generated `help`, man pages,
Bash completion, `doctor`, `--json`) are meant for agents and scripts. The architecture documents
`init` as the remaining target-state setup/scaffold/bootstrap surface, but it does not exist yet:
`docs/reference/cli-commands.md` says *"`init` is the remaining target-state setup surface; it is not
currently a command."* and ADR-0009 says *"Target state adds an `init` surface for
setup/scaffold/bootstrap."* Until `init` ships, `cog` does not fully satisfy the
self-documenting-surfaces standard it now documents.

This round implements `cog init`. To avoid duplicating logic, `init` is built DRY against `doctor`:
the prerequisite/XDG/install checks that `doctor` already performs become a shared `cog::fn::*` helper
that both commands consume — `doctor` reports health, `init` ensures/creates the same prerequisites.

## Previous Rounds

Rounds are independent and may run in any order. If `python-cli-spec-chapters` (Round 1) ran first, it
changed only the `docs-n-notes` repo and has no effect here.

## Scope of This Round

IN scope:

- A shared prerequisite/XDG-check helper under `lib/functions/` (extracted from `doctor`).
- `lib/commands/cmd_init.sh` defining `cog::cmd::init`, with the line-2 `: 'desc: ...'` sentinel.
- `init` creates/ensures the XDG state/config/cache/data directories `cog` relies on, is idempotent,
  honors `--dry-run`, and emits machine output (plain status lines + `--json`) consistent with
  ADR-0009.
- Unit tests (bats) under `test/unit/`.
- Self-documentation mirrors updated: `completions/cog.bash`, `man/cog.1.scd`,
  `docs/reference/cli-commands.md`, and the generated-help snapshot(s).

OUT of scope:

- Removing human-UX leakage (that is Round 3 `msg-machine-facing-cleanup`). `init` must itself follow
  the machine-facing contract, but do not refactor `cmd_msg.sh`/`fn_ui_print.sh` here.
- The digest tooling (Round 4).
- Scaffolding project files outside `cog`'s own runtime dirs (keep `init` scoped to `cog`'s
  setup/bootstrap, matching how `doctor` checks them).

## Current State

### Key Files

- `lib/commands/cmd_doctor.sh` — the SoT to factor against. It builds a `checks` array via the private
  `__cog_doctor_add_check`, probes deps `(bash jq git find sed mktemp)`, checks XDG homes
  (`XDG_CONFIG_HOME`/`STATE`/`CACHE`/`DATA` with `$HOME/...` fallbacks), and verifies install paths
  (`bin/cog`, `LIB_DIR`, `LIB_DIR/commands`, eager modules). It emits either JSON
  (`schema: cog.doctor.v1`) when `COG_UI_JSON == true` or plain `DOCTOR_OK` / `DOCTOR_FAILED <kind>`.
  Exit codes: `EX_UNAVAILABLE` (missing dep), `EX_CONFIG` (state/install problem), else 0. The XDG
  derivation and the state-home creatability probe:

  ```bash
  local xdg_state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
  local state_parent="${xdg_state_home%/*}"
  if [[ -d $state_parent && -w $state_parent ]] || mkdir -p "$xdg_state_home" 2>/dev/null; then
  ```

  This `mkdir -p` ensure-or-fail logic is exactly what `init` needs as its create action.
- `lib/commands/cmd_plan_init.sh` (`cog::cmd::plan_init`) — an existing init-style command:
  bootstrap-if-missing, idempotent, `--json` output listing `created` vs `existing`. Use it as the
  output-shape model for `cog init` (`created` / `existing` arrays).
- `lib/functions/fn_json_write.sh` — provides `cog::fn::json_emit '<jq filter>' "$json"` (used by
  `doctor` to validate-and-emit). Reuse it.
- `lib/functions/fn_ui_print.sh` — `cog::fn::ui_data` (stdout result) and `COG_UI_JSON`. `init`'s
  default (non-JSON) output should be plain machine lines via `ui_data`, JSON when
  `COG_UI_JSON == true`, mirroring `doctor`.
- `lib/loader.sh` — dispatches `cog <name>` to `lib/commands/cmd_<name>.sh` → `cog::cmd::<name>`. No
  registration list to edit; the command is discovered by filename. (`cog init` → `cmd_init.sh` →
  `cog::cmd::init`.)

### Existing Patterns

- Command module conventions (from `AGENTS.md`): module at `lib/commands/cmd_<slug>.sh`, handler
  `cog::cmd::<slug>`, public shared helpers `cog::fn::*` in `lib/functions/`, private helpers prefixed
  `__cog_`. **The line-2 `: 'desc: ...'` sentinel is mandatory** — root help, the `cli-commands.md`
  table, the man-page command summary, and completion drift checks all parse it.
- Tests: bats under `test/unit/`, one file per subcommand (e.g. `test/unit/msg.bats`,
  `test/unit/log.bats`). Helpers in `test/test_helper/` (bats-support/assert/file). New file:
  `test/unit/init.bats`.
- Machine-facing contract (ADR-0009): stdout carries only the successful result; errors/warnings go to
  stderr with non-zero exit; structured JSON when machine-output. No friendly/emoji decoration.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `QUEUE.yaml`, set this round's (`item: cog-init-subcommand`) `status` to `doing`.

### Step 1: Extract a shared prerequisite-check helper

Create a `lib/functions/fn_<name>.sh` (e.g. `fn_prereq.sh`) exposing a `cog::fn::*` function that
encapsulates the dependency probe, XDG-home resolution, and the install-path checks currently inlined
in `cmd_doctor.sh`. The helper should return structured results (the existing
`{name,status,detail,path}` check shape) so `doctor` can keep reporting and `init` can act on the same
data. Keep `doctor`'s observable output byte-identical — this is a refactor, not a behavior change.
Add/extend `test/unit/` coverage for the new helper.

### Step 2: Refactor `doctor` to consume the helper

Update `cmd_doctor.sh` to call the shared helper instead of its private inline logic. Re-run
`test/unit/` (and any doctor snapshot) to confirm `DOCTOR_OK` / JSON output is unchanged.

### Step 3: Implement `lib/commands/cmd_init.sh`

- Line 1: `# shellcheck shell=bash`. Line 2: `: 'desc: Initialize cog runtime directories and
  prerequisites.'` (mandatory sentinel).
- `cog::cmd::init` uses the shared helper to determine what is missing, then **creates** the XDG
  runtime dirs `cog` needs (state/config/cache/data) idempotently via `mkdir -p`.
- Honor `--dry-run` (report intended actions, change nothing). Honor `-h`/`--help`.
- Emit machine output: plain status (e.g. `INIT_OK`, or `created`/`existing` lines) by default, and a
  validated JSON document (own `schema:` string, e.g. `cog.init.v1`) when `COG_UI_JSON == true`, via
  `cog::fn::json_emit`. Model the `created`/`existing` arrays on `cmd_plan_init.sh`.
- Exit codes per sysexits: `EX_CONFIG` when a required dir cannot be created; 0 on success.
- No human-UX decoration (no emoji, no friendly prose) — machine-facing only.

### Step 4: Add `test/unit/init.bats`

Cover: fresh init creates dirs; idempotent re-run reports them existing; `--dry-run` creates nothing;
`--json` emits a valid document; failure to create a dir exits `EX_CONFIG`. Follow the structure of
`test/unit/msg.bats` / existing command tests.

### Step 5: Update the self-documentation mirrors

- `docs/reference/cli-commands.md` — add an `init` row to the Commands table (alphabetical position),
  and update the prose at the top that currently says `init` "is not currently a command."
- `completions/cog.bash` — add `init` to the completed command list.
- `man/cog.1.scd` — add `init` to the command summary. If the in-flight `man-page-sync-precommit-hook`
  plan has landed, regenerate `man/cog.1` via `cog man-build`; otherwise update `man/cog.1` to match
  by the same method the repo currently uses.
- Refresh the generated-help snapshot(s) (e.g. under `test/`) so the help drift check passes.

### Step 6: Run the gates

Run `just lint` and `just test`. Resolve any completion/man/help drift the new command surfaces.

### Final Step: Update the queue

1. In this plan's `QUEUE.yaml`, set this round's (`item: cog-init-subcommand`) `status` to `done`.

(This is not the final round — do not touch the top-level ledger.)

## Acceptance Criteria

- [ ] A `cog::fn::*` prerequisite helper exists and is consumed by both `doctor` and `init`; `doctor`
      output is unchanged.
- [ ] `lib/commands/cmd_init.sh` exists with the line-2 `desc:` sentinel and `cog::cmd::init`.
- [ ] `cog init` is idempotent, honors `--dry-run`, emits plain + `--json` machine output, and exits
      `EX_CONFIG` when a dir cannot be created. No emoji/human decoration.
- [ ] `test/unit/init.bats` passes; `just lint` and `just test` are green.
- [ ] `cli-commands.md`, `completions/cog.bash`, `man/cog.1.scd`/`man/cog.1`, and the help snapshot all
      list `init`; no drift checks fail.
- [ ] This plan's `QUEUE.yaml` shows round `cog-init-subcommand` as `done`.

## Next Round

`msg-machine-facing-cleanup` — remove the acknowledged human-UX leakage so `cog` emits no
human-facing content. Independent of this round.
