# Remove Human-UX Leakage from `cmd_msg.sh` and Friends

> Plan: cog-contract-and-spec-uplift | Round: 3 of 4 | Complexity: L (override) | Generated: 2026-06-19 |
> Repo: /workspaces/cog

## Context

ADR-0009 declares `cog` machine-facing: stdout carries only the successful result, errors/warnings go
to stderr with non-zero exit codes, JSON when machine-output is requested, and human-UX is "optional
and opt-in, never the default contract." The ADR explicitly records a known exception: *"Existing
human-message paths such as `cmd_msg.sh` are acknowledged leakage to keep scoped behind explicit
human-UX behavior."*

In practice `cog` has **no present need to emit any human-facing content** — every caller is an agent
or a script. Rather than build an opt-in human-UX surface (a `--human` flag / `COG_UI_HUMAN` env) that
nothing would use, this round **removes the decorative human-UX leakage** so `cog` is machine-facing
end to end, and updates ADR-0009 to record the closure. The universal Unix stream contract is
untouched: errors and warnings still go to stderr with non-zero exit codes — that is not "human-UX,"
it is the stream contract ADR-0009 keeps.

## Previous Rounds

Rounds are independent and may run in any order. If `cog-init-subcommand` (Round 2) ran first, it
added a machine-facing `init` command and a shared prerequisite helper; it did not change the UI
helpers this round touches.

## Scope of This Round

IN scope — remove **decorative/progress** human output:

- The emoji decoration and human-progress kinds in `lib/commands/cmd_msg.sh` (`▶` in `stage`, the
  `info` passthrough, and `❌` in `error`/`fatal`).
- The friendly success/status lines in `lib/commands/cmd_doctor.sh` (`cog doctor: ok` /
  `cog doctor: <overall>`), which duplicate the machine lines `DOCTOR_OK` / `DOCTOR_FAILED <kind>`.
- Any other purely-decorative `ui_human` call surfaced by the audit (see Step 1).
- Update ADR-0009's acknowledgement paragraph to record that the leakage is closed.
- Update the gc skills if they relied on a removed `cog msg` kind.

OUT of scope — **keep** the stderr error/warning contract:

- `cog::fn::ui_warn`, `cog::fn::ui_error_line`, and the error/log plumbing in
  `lib/functions/fn_error_raise.sh` and `lib/functions/fn_log.sh` (these emit errors/warnings to
  stderr with non-zero exit — required by ADR-0009, not "human-UX").
- Adding a `--human`/`COG_UI_HUMAN` opt-in surface (explicitly rejected — `cog` has no human-UX need).
- `cmd_init.sh`/`cmd_digest_*.sh` from the other rounds.

## Current State

### Key Files

- `lib/functions/fn_ui_print.sh` — the helpers. `cog::fn::ui_data`/`ui_dataf` write the result to
  stdout; `cog::fn::ui_human`/`ui_humanf` write to **stderr**; `ui_warn` = `ui_human "Warning: $*"`;
  `ui_error_line` = `ui_human "$*"`. Decorative output flows through `ui_human`/`ui_humanf`.
- `lib/commands/cmd_msg.sh` — the main leakage site. Relevant lines:

  ```bash
  stage)  cog::fn::ui_human "▶ $*" ;;
  info)   cog::fn::ui_human "$*" ;;
  warn)   cog::fn::ui_warn "$*" ;;
  error)  ... cog::fn::ui_human "❌ ${error_ctx}: $*" ;;
  fatal)  ... cog::fn::ui_human "❌ ${fatal_ctx}: $*" ; exit "$EX_SOFTWARE" ;;
  ```

  Its line-2 sentinel reads `: 'desc: Emit uniform machine status lines and human messages.'` — update
  the "and human messages" wording once the human kinds are gone.
- `lib/commands/cmd_doctor.sh:166-171` — the non-JSON branch emits the machine line via `ui_data`
  **and** a friendly line via `ui_human`/`ui_warn`:

  ```bash
  cog::fn::ui_data "DOCTOR_OK"
  cog::fn::ui_human "cog doctor: ok"
  ...
  cog::fn::ui_data "DOCTOR_FAILED ${hard_failure_kind:-unknown}"
  cog::fn::ui_warn "cog doctor: ${overall}"
  ```

  Remove the `ui_human`/`ui_warn` decoration lines; keep the `ui_data` machine lines.
- Other `ui_human` call sites to audit (from `grep -rn 'ui_human\|ui_humanf\|ui_warn' lib/`):
  `cmd_require.sh:84` (`ui_human "MISSING $name"`), `cmd_preflight.sh:195` (a `WARNING ...` advisory),
  and the plumbing in `fn_error_raise.sh`/`fn_log.sh` (KEEP). Judge each: machine-status-on-stderr
  (e.g. `MISSING`) may be converted to the proper machine channel; genuine error/warning stays.
- `docs/decisions/0009-machine-facing-output-contract.md` — the ADR to update (paragraph beginning
  *"`cog` already ships `help`, `doctor`, ..."*).
- Callers: `skills/claude/gc/SKILL.md` and `skills/codex/gc/SKILL.md` reference `cog msg`. Grep them
  for which kinds they invoke before removing any kind.

### Existing Patterns

- ADR-0009 stream contract: stdout = result only; stderr = errors/warnings/diagnostics with non-zero
  exit. Machine status that is part of the *result* belongs on stdout via `ui_data`.
- Tests: `test/unit/msg.bats` and `test/unit/ui_print.bats` already assert the current output. They
  must be updated to assert the cleaned-up behavior.
- Doc maintenance (AGENTS.md): accepted ADRs are never deleted; changed *decisions* get a superseding
  ADR. This round changes a *consequence/acknowledgement* (the decision — machine-facing — is unchanged
  and in fact completed), so an in-place dated amendment is appropriate.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `QUEUE.yaml`, set this round's (`item: msg-machine-facing-cleanup`) `status` to
`doing`.

### Step 1: Audit every human-UX call site

`grep -rn 'ui_human\|ui_humanf\|ui_warn\|ui_error_line' lib/` and `grep -rn 'cog msg' skills/ lib/`.
For each, classify: (a) decorative/progress → remove; (b) error/warning to stderr → keep; (c)
machine-status routed through `ui_human` by mistake → move to `ui_data` (stdout) or drop. Record the
classification in the commit/PR description.

### Step 2: Clean `cmd_msg.sh`

Remove the emoji decoration and the human-progress kinds. Concretely: drop the `▶` prefix and the
`info`/`stage` human passthroughs (or remove those kinds entirely if Step 1 shows no machine caller),
and strip `❌` from `error`/`fatal` so the error text is plain. `error`/`fatal` must still write to
stderr and exit non-zero (`fatal` keeps `exit "$EX_SOFTWARE"`). Update the line-2 `desc:` sentinel to
drop "and human messages". If any kind is removed, update `cog msg --help` / `__cog_msg_usage`
accordingly.

### Step 3: Clean `cmd_doctor.sh`

Remove the two `ui_human`/`ui_warn` decoration lines (lines ~167 and ~170); keep `DOCTOR_OK` /
`DOCTOR_FAILED <kind>` machine lines and the JSON branch unchanged.

### Step 4: Resolve the other audited sites

Apply the Step 1 classification to `cmd_require.sh:84`, `cmd_preflight.sh:195`, and any others.
Preserve `fn_error_raise.sh`/`fn_log.sh` error/warning behavior exactly.

### Step 5: Update the gc skills if needed

If `skills/claude/gc/SKILL.md` or `skills/codex/gc/SKILL.md` invoked a removed `cog msg` kind, update
those invocations to the machine-facing equivalent. Run `cog skill-lint` on any touched `SKILL.md`.

### Step 6: Update ADR-0009

Edit `docs/decisions/0009-machine-facing-output-contract.md`: change the acknowledgement paragraph to
record that the `cmd_msg.sh` human-UX leakage is now closed (cog emits no human-UX; the stderr
error/warning contract remains), with a dated note. Keep the Decision Outcome and Status (`Accepted`)
intact. If, on inspection, the executor judges this a decision reversal rather than a completion, add a
superseding ADR instead and reference it from 0009.

### Step 7: Update tests and run gates

Update `test/unit/msg.bats` and `test/unit/ui_print.bats` to assert the cleaned output (no emoji, no
decorative lines). Run `just lint` and `just test` until green.

### Final Step: Update the queue

1. In this plan's `QUEUE.yaml`, set this round's (`item: msg-machine-facing-cleanup`) `status` to
   `done`.

(This is not the final round — do not touch the top-level ledger.)

## Acceptance Criteria

- [ ] No emoji (`❌`/`▶`) or decorative `ui_human` progress output remains in `lib/commands/`; an
      audit grep shows only error/warning/diagnostic uses of `ui_human`/`ui_warn`.
- [ ] `cmd_msg.sh` `error`/`fatal` still write to stderr and exit non-zero; `fatal` still exits
      `EX_SOFTWARE`. The line-2 `desc:` sentinel no longer claims "human messages".
- [ ] `doctor` still emits `DOCTOR_OK` / `DOCTOR_FAILED <kind>` and valid JSON; the friendly lines are
      gone.
- [ ] ADR-0009 records the leakage as closed (or a superseding ADR is added) while remaining
      `Accepted`.
- [ ] gc skills still function; `cog skill-lint` passes on any touched `SKILL.md`.
- [ ] `test/unit/msg.bats` and `test/unit/ui_print.bats` updated; `just lint` and `just test` green.
- [ ] This plan's `QUEUE.yaml` shows round `msg-machine-facing-cleanup` as `done`.

## Next Round

`digest-drift-tooling` — add `cog digest-check` and `cog digest-stamp` for the docs-n-notes AGENTS.md
digests. Independent of this round.
