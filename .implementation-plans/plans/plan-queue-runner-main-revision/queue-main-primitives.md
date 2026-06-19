# Queue Main Primitives: Schema-Generic Selection, `queue-status-set`, `resolve-plan`, Setup Detection

> Plan: plan-queue-runner-main-revision | Round: 1 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

`cog`'s implementation-plan queue helpers in `/workspaces/cog/lib/functions/fn_queue.sh` are already
schema-generic for `plans|rounds` EXCEPT the selection path, and there is no helper that can safely
flip a main `plans[]` item to `done`. This round lands the deterministic `cog` foundations Feature A
needs, with NO skill-prose or orchestration changes (those are Round 3):

1. Generalize the rounds-hardcoded selection helpers and the `cog queue-select` caller to a
   `--schema plans|rounds` parameter (default `rounds`, behavior preserved).
2. Add `cog queue-status-set` — the ONLY authorized way to flip a `plans[].status` (e.g.
   `todo -> done`), a single-item guarded transition.
3. Add `cog runner-queue-resolve-plan` — resolve a selected main-queue plan entry to its
   executable `inner_queue` form, parsing the `/prex -ar [@]<target>` prompt. The live data is
   directory-only: a valid plan target is a directory containing `queue-rounds.yaml`. File targets
   and directories without `queue-rounds.yaml` fail closed.
4. Extend `cog runner-queue-setup` to detect the queue schema and persist `QUEUE_SCHEMA`
   (+ `MAIN_QUEUE_PATH` when `plans`) so the first `queue-select` no longer dies on a `plans:` queue.

All work is deterministic `cog` mechanics under ADR-0008, with `bats` coverage and
doc/completion/man/help drift updates.

## Previous Rounds

This is the first round — no prior rounds.

## Scope of This Round

- IN scope:
  - Generalize `cog::fn::queue_select_next_round` -> `cog::fn::queue_select_next_item <queue> <schema>`
    (operate on `.<schema>[]?` instead of hardcoded `.rounds[]?`).
  - Generalize `cog::fn::queue_validate_rounds_selectable` -> `cog::fn::queue_validate_selectable
    <queue> <schema>` (validate file + reject any `doing` item) for both schemas.
  - Add `--schema plans|rounds` to `cog queue-select` (default `rounds`); preserve the JSON output
    contract and self-check filter; add an additive `schema` field.
  - Add `cog queue-status-set --queue <path> --schema <plans|rounds> --item <item> --from <status>
    --to <status> (<out.json>|--json)`: single-item guarded flip.
  - Add `cog runner-queue-resolve-plan --repo-root <dir> --queue <main-queue> --item <item>
    (<out.json>|--json)`: classify a/b/c, fail closed on ambiguity.
  - Extend `cog runner-queue-setup` with schema detection + `QUEUE_SCHEMA` / `MAIN_QUEUE_PATH`.
  - `bats` tests; update `docs/reference/cli-commands.md`, `completions/cog.bash`, `man/cog.1(.scd)`,
    and help snapshots.
- OUT of scope: any `runner-queue` skill prose change; the plans-revision skill/commands
  (Round 2); the runner orchestration rewrite (Round 3). No change to `queue-bootstrap`/`queue-append`
  (already dual-schema) or `cmd_runner_queue_parse_commit.sh`.

## Current State

### Key Files

- `/workspaces/cog/lib/functions/fn_queue.sh` — queue helpers. Already schema-generic via
  `cog::fn::queue_schema_key` (accepts `plans|rounds`, line 29) and `__cog_queue_key_or_die`.
  `cog::fn::queue_status_valid` (line 40) validates `backlog|todo|doing|done`. The two hardcoded
  helpers to generalize:

  ```bash
  cog::fn::queue_validate_rounds_selectable() {            # line 138
    local queue_path="${1:-}"
    local doing
    cog::fn::queue_validate_file "$queue_path" rounds
    doing="$(yq e -r '.rounds[]? | select(.status == "doing") | .item' "$queue_path")"
    [[ -z $doing ]] || cog::helpers::die ... "rounds already doing" ...
  }

  cog::fn::queue_select_next_round() {                     # line 262
    __cog_queue_require_jq_yq
    local queue_path="${1:-}"
    cog::fn::queue_validate_rounds_selectable "$queue_path"
    yq e -o=json '.' "$queue_path" | jq -c '
      ([.rounds[]? | select(.status == "done") | .item]) as $done
      | ([.rounds[]? | select(.status == "todo")]) as $todo
      | ([ $todo[]? | select(all(.depends_on[]?; . as $d | ($done | index($d)))) ]) as $runnable
      | if ($runnable | length) > 0 then {state: "selected", selected: $runnable[0], todo_remaining: ($todo | map(.item)), blocked: []}
        elif ($todo | length) == 0 then {state: "complete", selected: null, todo_remaining: [], blocked: []}
        else {state: "blocked", selected: null, todo_remaining: ($todo | map(.item)), blocked: ($todo | map(.item))} end '
  }
  ```

  Drive the jq array path via `jq --arg key "$schema"` and `.[$key][...]`; drive the `yq` doing-check
  via `KEY="$schema" ... .[strenv(KEY)][]?`. Reuse `queue_status_valid` and the existing
  `__cog_queue_validate_entry_filter` for `queue-status-set`.

- `/workspaces/cog/lib/commands/cmd_queue_select.sh` — the rounds-hardcoded caller and output
  contract. The self-check filter (line 4) and `__cog_queue_select_result_json` shape must be
  preserved:

  ```bash
  __cog_queue_select_self_check='(.ok|type=="boolean") and (.queue_path|type=="string") and (.clean_check|type=="boolean") and (.state == "selected" or .state == "complete" or .state == "blocked") and ((.selected == null) or (.selected.item|type=="string")) and (.todo_remaining|type=="array") and (.blocked|type=="array")'
  # line 32: cog::fn::queue_validate_rounds_selectable "$queue_path"
  # line 50: selected_json="$(cog::fn::queue_select_next_round "$queue_path")"
  ```

  `__cog_queue_select_build_json` currently takes `(queue_path repo_root clean_check extra_repos...)`;
  it must accept a `schema` argument and forward it to the generalized helpers. Note
  `cmd_runner_queue_setup.sh:108` calls `__cog_queue_select_build_json` directly, so its
  signature change must be coordinated within THIS round (setup detection is Step 5 below).

- `/workspaces/cog/lib/commands/cmd_runner_queue_setup.sh` — normalizes the target to a
  `queue-rounds.yaml`, writes `ctx.env`, and runs the first `queue-select`. The relevant lines:

  ```bash
  case "$target" in                          # lines 85-89
    */queue-rounds.yaml) queue_path="$target" ;;
    *) queue_path="${target}/queue-rounds.yaml" ;;
  esac
  # ctx.env keys (__cog_runner_queue_setup_write_ctx, lines 63-78):
  #   REPO_ROOT QUEUE_PATH RUN_DIR DRY_RUN MAX_ROUNDS REPOS  (%q-quoted)
  # first select (lines 104-110): sources cmd_queue_select.sh and runs __cog_queue_select_build_json
  #   -> today runs queue_validate_rounds_selectable and WOULD FAIL on a plans: queue.
  __cog_runner_queue_setup_self_check='(.run_dir|type=="string") and (.queue_path|type=="string") and (.repo_root|type=="string") and (.dry_run|type=="boolean") and has("max_rounds") and (.repos|type=="array")'
  ```

- `/workspaces/cog/.implementation-plans/queue-plans.yaml` — the real main `plans:` queue (canonical schema
  fixture): entries `item/status/depends_on/prompt/notes`, statuses `backlog|todo|doing|done`. Plan
  prompts use the directory form `/prex -ar @<dir>/`; the data is directory-only, so every plan
  target is a directory containing `queue-rounds.yaml`. The resolver parses both the `@`-prefixed and
  bare directory forms; a bare `/prex -ar <file>` target (a file rather than a plan directory) is not
  valid live data and fails closed.

- `/workspaces/cog/lib/loader.sh` — derives `cmd_<slug>.sh` and `cog::cmd::<slug>` from the dashed
  command name (`queue-status-set` -> `cmd_queue_status_set.sh` / `cog::cmd::queue_status_set`;
  `runner-queue-resolve-plan` -> `cmd_runner_queue_resolve_plan.sh`).

### Existing Patterns

- Command modules: `lib/commands/cmd_<slug_with_underscores>.sh`, handler
  `cog::cmd::<slug_with_underscores>`, MANDATORY line-2 `: 'desc: ...'` sentinel (root help / man /
  completion drift checks depend on it). Shared `cog::fn::*` helpers in `lib/functions/`.
- Machine-facing JSON (ADR-0009): build JSON, define a `__cog_<cmd>_self_check` jq predicate, emit via
  `cog::fn::json_emit` (or `cog::fn::json_write_fragment` for an out-file), honor `${COG_UI_JSON:-false}`
  and a `--json` / `<out.json>` toggle. Errors via `cog::fn::error_raise` / `cog::helpers::die` with
  `$EX_*` exit codes (`$EX_USAGE` 2 for bad args; data errors otherwise).
- Tests: existing specs include `test/integration/queue_select.bats`, `test/integration/queue_append.bats`,
  `test/integration/runner_queue_setup.bats`, and unit `queue` specs. Mirror those for the new
  commands and the generalized selection.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: queue-main-primitives`) `status` to `doing`.

### Step 1: Generalize the selection helpers in `fn_queue.sh`

- Add `cog::fn::queue_validate_selectable <queue_path> <schema>` — validate the file for `<schema>`
  (`queue_validate_file`), then reject any item in `.<schema>` whose status is `doing` (failure text
  mentions the schema, e.g. `plans already doing` / `rounds already doing`).
- Add `cog::fn::queue_select_next_item <queue_path> <schema>` — same jq logic as
  `queue_select_next_round`, with the array path parameterized (`jq --arg key "$schema"`, `.[$key][]?`).
  Output shape unchanged (`state/selected/todo_remaining/blocked`).
- Keep `queue_select_next_round` / `queue_validate_rounds_selectable` as thin back-compat shims that
  delegate with `rounds` (so any other caller and tests keep working), OR migrate all callers in this
  round. Document the choice. Recommended: keep shims; migrate `cmd_queue_select.sh` and setup to the
  new names in Steps 2 and 5.

### Step 2: Add `--schema` to `cog queue-select`

In `cmd_queue_select.sh`: add a `schema` local (default `rounds`), parse `--schema <plans|rounds>` in
`cog::cmd::queue_select`, validate via `cog::fn::queue_schema_key`, and thread it into
`__cog_queue_select_build_json` -> `queue_validate_selectable` / `queue_select_next_item`. Add an
additive `schema` field to the result JSON and to `__cog_queue_select_self_check`
(`and (.schema=="plans" or .schema=="rounds")`) WITHOUT changing any existing field. Keep the
clean-tree loop over `repo_root`/`extra_repos`. Update the blocked `reason` text to reflect the schema
(e.g. `todo plans remain but dependencies are not done`).

### Step 3: Add the `cog queue-status-set` command

Create `lib/commands/cmd_queue_status_set.sh` (line-2 `: 'desc: Set one queue item status with an
expected-current-status guard.'`, handler `cog::cmd::queue_status_set`). Flags:
`--queue <path> --schema <plans|rounds> --item <item> --from <status> --to <status>
(<out.json>|--json)`. Behavior (deterministic, fail-closed):

1. Validate args (all required); `--from`/`--to` via `cog::fn::queue_status_valid`; schema via
   `queue_schema_key`.
2. `cog::fn::queue_validate_file "$queue" "$schema"`.
3. Require the item exists exactly once and its current status equals `--from`; else fail closed with
   a precise error.
4. Flip only that item's `status` field. Write to a temp file via `yq`, then re-read and assert ONLY
   that item changed (status went `--from` -> `--to`, entry count unchanged, all other entries
   byte-identical), then atomic `mv` into place (mirror the verification discipline of
   `cog::fn::queue_append_entry`). No reordering/rewriting of other entries.
5. Emit JSON `{ok, queue_path, schema, item, from, to, status_before, status_after, changed}` with a
   `__cog_queue_status_set_self_check` predicate.

Exit codes: `$EX_USAGE` (2) for bad/missing args; a data-error code for missing item / status
mismatch / invalid status; an IO-error code for write failure.

### Step 4: Add `cog runner-queue-resolve-plan`

Create `lib/commands/cmd_runner_queue_resolve_plan.sh` (line-2 `: 'desc: Resolve a selected main
queue plan entry to its executable form.'`, handler `cog::cmd::runner_queue_resolve_plan`).
Flags: `--repo-root <dir> --queue <main-queue> --item <item> (<out.json>|--json)`. Behavior:

1. Validate `--queue` as `plans`; load the matching `plans[]` entry (fail closed if missing/duplicate).
2. Parse the execution target from the entry's `prompt`, supporting BOTH `/prex -ar <target>` and
   `/prex -ar @<target>` (strip a single leading `@`); normalize a relative target against `repo_root`.
3. Resolve `kind`. The live data is directory-only, so there is exactly one valid kind:
   - `inner_queue` — target is a directory containing `queue-rounds.yaml`. Resolve `inner_queue_path`
     and surface any `repos:` the inner queue declares.
4. Fail closed: target missing; a file target (not a directory); a directory with no
   `queue-rounds.yaml`; prompt not a supported `/prex -ar` invocation; queue item missing/duplicate.

Emit JSON `{ok, item, kind, repo_root, main_queue_path, target_path, inner_queue_path, prompt, repos}`
with a self-check predicate (`kind == "inner_queue"`).

### Step 5: Schema detection + `QUEUE_SCHEMA` in setup

In `cmd_runner_queue_setup.sh`: after normalizing `queue_path`, read the top-level key with `yq`
and decide schema — `has("plans") and not has("rounds")` -> `plans`; `has("rounds") and not
has("plans")` -> `rounds`; otherwise fail closed (`InvalidInput`). Pass the detected schema into the
first `__cog_queue_select_build_json` (new signature from Step 2). Add `QUEUE_SCHEMA` and, when
`plans`, `MAIN_QUEUE_PATH=$queue_path` to `__cog_runner_queue_setup_write_ctx` (ctx.env) and to
the emitted JSON; extend `__cog_runner_queue_setup_self_check` with
`and (.queue_schema=="plans" or .queue_schema=="rounds")`. (For a `rounds:` queue, behavior and ctx
keys are otherwise unchanged.)

### Step 6: Tests

- New `test/integration/queue_status_set.bats`: happy `todo->done` on a `plans:` fixture and a
  `rounds:` fixture; failures for missing item, wrong `--from`, invalid status, duplicate item,
  missing queue.
- New `test/integration/runner_queue_resolve_plan.bats`: a directory plan with `queue-rounds.yaml`
  resolves to `inner_queue` (covering both the `@`-prefixed and bare directory prompt forms and
  surfacing any inner `repos:`); a file target, a directory without `queue-rounds.yaml`, a missing
  target, a non-`/prex -ar` prompt, and a missing/duplicate item each fail closed.
- Extend `test/integration/queue_select.bats`: a `--schema plans` selection case AND a regression case
  proving the default (`rounds`) path output is byte-identical (plus the additive `schema` field).
- Extend `test/integration/runner_queue_setup.bats`: `QUEUE_SCHEMA=plans` + `MAIN_QUEUE_PATH` on
  a `plans:` fixture; `QUEUE_SCHEMA=rounds` on an inner queue; both/neither fail closed.

### Step 7: Doc / completion / man / help-snapshot drift

Update `docs/reference/cli-commands.md` (rows for `queue-status-set` and `runner-queue-resolve-plan`;
note the `queue-select --schema` flag), `completions/cog.bash`, `man/cog.1.scd` (regenerate `man/cog.1`
per the repo's man-build workflow), and refresh help snapshots so the drift checks and
`test/integration/*help*` pass.

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: queue-main-primitives`) `status` to `done`.

## Acceptance Criteria

- [ ] `cog queue-select --queue <plans-queue> --schema plans --json` selects the first runnable `todo`
      plan and emits the unchanged output contract plus an additive `schema` field.
- [ ] `cog queue-select` with no `--schema` is byte-identical to before (default `rounds`); regression
      test passes.
- [ ] `cog queue-status-set --schema plans --item <i> --from todo --to done` flips only that item and
      fails closed on missing item, wrong `--from`, invalid status, or duplicate item.
- [ ] `cog runner-queue-resolve-plan` resolves a directory plan carrying `queue-rounds.yaml` to
      `kind: inner_queue` (both prompt forms), and fails closed on a file target, a directory without
      `queue-rounds.yaml`, a missing target, an unsupported prompt, or a missing/duplicate item.
- [ ] `cog runner-queue-setup` emits `QUEUE_SCHEMA` (+ `MAIN_QUEUE_PATH` for `plans`) and the
      first `queue-select` no longer dies on a `plans:` queue; a `rounds:` target is unchanged.
- [ ] No skill prose changed this round; each new command module has its line-2 `: 'desc:'` sentinel.
- [ ] `just lint` (pre-commit) and `just test` pass, including drift checks for
      cli-commands/completions/man/help snapshots.
- [ ] This plan's `queue-rounds.yaml` shows round `queue-main-primitives` as `done`.

## Next Round

Round 2 (`plans-revision-mechanics`) builds the deterministic revision scan/verify `cog` commands and
the new project-local `plans-revision` skill on top of `queue-status-set` / `queue-append` and the
schema detection from this round.
