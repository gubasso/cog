setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_json_write.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_rundir.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_longrun.sh"
  RD="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$RD"
}

# Write a synthetic state file. A pgid of 1 is never alive for our purposes
# (is_alive requires pgid > 1), so liveness is deterministically false.
_write_state() {
  local sf="$1" state="$2" boot="$3"
  jq -cn \
    --arg state "$state" --arg boot "$boot" \
    --arg dmark "${RD}/j.done" --arg exitf "${RD}/j.exit" \
    --arg stdout "${RD}/j.stdout.log" --arg stderr "${RD}/j.stderr.log" --arg output "${RD}/j.out" \
    '{schema:"cog.longrun.v1", label:"j", state:$state, cmd:["true"], cwd:".",
      pid:1, pgid:1, host_boot_id:$boot,
      started_at:"t", exited_at:null, finalized_at:null, exit_code:null, exit_source:null,
      artifacts:{stdout:$stdout, stderr:$stderr, output:$output, exit_code_file:$exitf, done_marker:$dmark},
      engine:"generic", engine_meta:{}}' >"$sf"
}

@test "observe marks a dead group with matching boot as lost" {
  local sf="${RD}/j.longrun.json"
  _write_state "$sf" running "$(cog::fn::longrun::boot_id)"
  run cog::fn::longrun::observe "$sf"
  assert_output "lost"
}

@test "observe treats a present done-marker as exited regardless of liveness" {
  local sf="${RD}/j.longrun.json"
  _write_state "$sf" running "$(cog::fn::longrun::boot_id)"
  : >"${RD}/j.done"
  run cog::fn::longrun::observe "$sf"
  assert_output "exited"
}

@test "resolve_exit lets the exit-code file win over a dead group" {
  local sf="${RD}/j.longrun.json"
  _write_state "$sf" running "$(cog::fn::longrun::boot_id)"
  printf '%s\n' 0 >"${RD}/j.exit"
  run cog::fn::longrun::resolve_exit "$sf"
  assert_success
  printf '%s\n' "$output" | jq -e '.state == "exited" and .exit_code == 0 and .exit_source == "wrapper"' >/dev/null
}

@test "resolve_exit reports reconstructed when nothing recorded the exit" {
  local sf="${RD}/j.longrun.json"
  _write_state "$sf" running "$(cog::fn::longrun::boot_id)"
  run cog::fn::longrun::resolve_exit "$sf"
  assert_success
  printf '%s\n' "$output" | jq -e '.state == "lost" and .exit_code == null and .exit_source == "reconstructed"' >/dev/null
}

@test "observe never resurrects a terminal state" {
  local sf="${RD}/j.longrun.json"
  _write_state "$sf" finalized-ok "$(cog::fn::longrun::boot_id)"
  : >"${RD}/j.done"
  run cog::fn::longrun::observe "$sf"
  assert_output "finalized-ok"
}

@test "observe flags a boot-id mismatch as lost (host rebooted)" {
  local sf="${RD}/j.longrun.json"
  _write_state "$sf" running "stale-boot-id-from-a-previous-boot"
  : >"${RD}/j.done"
  # Even with a done-marker present, exited wins; mismatch only matters with no marker.
  run cog::fn::longrun::observe "$sf"
  assert_output "exited"

  rm -f "${RD}/j.done"
  _write_state "$sf" running "stale-boot-id-from-a-previous-boot"
  run cog::fn::longrun::observe "$sf"
  assert_output "lost"
}

@test "signal_code maps a disposition to the GR4 exit code (single source of truth)" {
  run cog::fn::longrun::signal_code ok
  assert_output "0"
  run cog::fn::longrun::signal_code running
  assert_output "75"
  run cog::fn::longrun::signal_code failed
  assert_output "1"
  # An unknown disposition is treated as not-ok rather than masquerading as success.
  run cog::fn::longrun::signal_code anything-else
  assert_output "1"
}
