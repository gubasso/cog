# `cog tracking-scan`: Deterministic Overdue-Entry Reporting + Sweep Cue

> Plan: repo-update-tracking | Round: 2 of 2 | Complexity: M | Generated: 2026-06-19 |
> Repo: /workspaces/cog

## Context

A tracking registry (`docs/reference/maintenance-tracking.yaml`) now lists perishable artifacts with
a `last_checked` date and a `cadence_days`. Deciding "is this entry overdue?" is a deterministic
computation, so per the skill/script boundary (`docs/decisions/0008-skill-script-boundary.md`) it
belongs in a `cog` subcommand — not in skill prose. This round adds `cog tracking-scan`, which reads
the registry and reports overdue entries (machine-output by default, per cog's contract), plus a cue
in `AGENTS.md` so an agent sweeping the codebase knows to run it and act on overdue references.

## Previous Rounds

`tracking-registry` created `docs/reference/maintenance-tracking.yaml` (schema: `schema_version`,
`entries[]` with `id`, `path`, `last_checked`, `cadence_days`, `why`, `revalidate_how`, `references`)
and the runbook `docs/guides/maintenance-tracking.md`. This round consumes that schema. Confirm the
final registry path matches what was written.

## Scope of This Round

- IN scope:
  - New command module `lib/commands/cmd_tracking_scan.sh` (handler `cog::cmd::tracking_scan`) and any
    shared helper in `lib/functions/`.
  - Reads the registry, computes overdue entries (`last_checked + cadence_days < now`), emits
    machine-readable output (JSON via `--json`, plus a default machine line format), exit non-zero or
    a clear status when overdue entries exist (decide and document the convention to match other cog
    commands).
  - A `--now <YYYY-MM-DD>` (or env) override so tests are deterministic.
  - Unit/integration test (`test/integration/tracking_scan.bats`), completion + man entries,
    `docs/reference/cli-commands.md` row.
  - An `AGENTS.md` sweep cue: when sweeping the repo, run `cog tracking-scan` and revalidate overdue
    references per `docs/guides/maintenance-tracking.md`.
- OUT of scope:
  - Auto-revalidating anything (the command only *reports*; revalidation stays a
    human/agent-triggered runbook).
  - CI wiring (note as optional follow-up).

## Current State

### Key Files

- `/workspaces/cog/lib/commands/` — command modules `cmd_<slug_with_underscores>.sh`, handler
  `cog::cmd::<slug>`, mandatory line-2 `: 'desc: ...'` sentinel. Use a sibling module (e.g.
  `cmd_plan_init.sh` or `cmd_queue_select.sh`) as the structural template for arg parsing, `--json`,
  and self-check conventions.
- `/workspaces/cog/lib/functions/` — shared `cog::fn::*` helpers; the YAML read of the registry should
  reuse whatever YAML/parse helper the queue commands already use (grep `lib/functions/` for the
  existing YAML accessor used by `cog queue-select`/`queue-status-set`).
- `/workspaces/cog/lib/loader.sh` — maps `tracking-scan` → `cmd_tracking_scan.sh` +
  `cog::cmd::tracking_scan`. No loader edit needed beyond adding the module.
- `/workspaces/cog/docs/reference/cli-commands.md` — command reference table (add the new row).
- `/workspaces/cog/completions/cog.bash`, `/workspaces/cog/man/cog.1.scd` (+ generated `man/cog.1`) —
  add the command; regenerate via the repo mechanism (`cog man-build` if the
  `man-page-sync-precommit-hook` plan has landed, else the justfile recipe).
- `/workspaces/cog/test/integration/help_snapshots.bats` — will need the new command's summary line
  added when help output changes; update the snapshot.
- `/workspaces/cog/AGENTS.md` — has "Orchestration Guards" and a documentation section; add the sweep
  cue near a fitting location.

### Existing Patterns

- cog is machine-facing: default output is machine-parseable + file-first; human UX is opt-in. Mirror
  the `--json` pattern and the self-check sentinel used by existing commands.
- Deterministic mechanics live in `cog`; the command must not embed judgment beyond the date math.
- Fenced code blocks need a language (MD040).

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: tracking-sweep-tooling`) `status` to
`doing`.

### Step 1: Implement `cog tracking-scan`

Create `lib/commands/cmd_tracking_scan.sh` with the line-2 `desc:` sentinel (e.g. "Report tracked
artifacts whose revalidation cadence is overdue."). The handler:

1. Resolves the registry path (default `docs/reference/maintenance-tracking.yaml`; allow
   `--registry <path>`).
2. Reads each entry's `last_checked` + `cadence_days`; computes due date.
3. Determines "now" from `--now <YYYY-MM-DD>` / an env override if given, else the system clock.
4. Emits overdue entries (id, path, due date, days overdue, `why`, `revalidate_how`) as JSON with
   `--json`, plus a default machine line format; choose and document the exit-status convention (e.g.
   non-zero when any entry is overdue) consistent with sibling commands.

Factor any reusable date/YAML logic into `lib/functions/` (`cog::fn::tracking_*`).

### Step 2: Tests

Add `test/integration/tracking_scan.bats`: a fixture registry with one overdue and one current entry;
assert (via `--now` injection) that only the overdue entry is reported, that `--json` is valid, and
that the exit status matches the documented convention. Reuse the integration harness used by
`plans_revision_scan.bats` et al.

### Step 3: Register the command surface

Update `docs/reference/cli-commands.md` (new row), completions, and man (`man/cog.1.scd` →
regenerate). Update `test/integration/help_snapshots.bats` for the new command summary.

### Step 4: Add the AGENTS.md sweep cue

Add a short line to `AGENTS.md`: when sweeping the repository, run `cog tracking-scan` and revalidate
any overdue references following `docs/guides/maintenance-tracking.md`. Keep it consistent with the
existing guard-bullet style.

### Step 5: Verify

Run `cog tracking-scan --json` against the real registry; run the integration suite (`just test` /
the integration hook); confirm help snapshots and the new bats suite pass; run `just lint`.

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: tracking-sweep-tooling`) `status` to
   `done`.
2. All rounds are now done, so in the top-level `.implementation-plans/queue-plans.yaml` set this
   plan's (`item: repo-update-tracking`) `status` to `done`. Leave the plan directory in place.

## Acceptance Criteria

- [ ] `cog tracking-scan` exists, reads `docs/reference/maintenance-tracking.yaml`, and reports
      overdue entries with `--json` and a default machine format; `--now` makes it deterministic.
- [ ] Exit-status / output convention is documented and consistent with sibling commands; line-2
      `desc:` sentinel present.
- [ ] `test/integration/tracking_scan.bats` passes (overdue vs current via injected `now`).
- [ ] `docs/reference/cli-commands.md`, completions, man, and help snapshots include the command.
- [ ] `AGENTS.md` carries the sweep cue pointing at the runbook.
- [ ] `just lint` and the integration suite pass.
- [ ] This plan's `queue-rounds.yaml` shows round `tracking-sweep-tooling` as `done`, and the
      top-level `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

This is the final round.
