setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset XDG_RUNTIME_DIR
  mkdir -p "$HOME" "$XDG_STATE_HOME"
}

guard_stop() {
  printf '{}' | cog hook-guard executor-prex-stop --owner-pid "$1"
}

acquire() {
  local out
  out="$(cog rundir executor-prex --lock --owner-pid "$1")"
  RUN_DIR="$(sed -n 's/^RUN_DIR=//p' <<<"$out")"
  LOCK_FILE="$(sed -n 's/^LOCK_FILE=//p' <<<"$out")"
}

@test "executor-prex-stop allows when there are no locks" {
  run guard_stop 999999

  [ "$status" -eq 0 ]
}

@test "executor-prex-stop writes and looks for the lock in the same dir with XDG_RUNTIME_DIR unset" {
  local expected_dir
  acquire "$$"
  expected_dir="$(env -u XDG_RUNTIME_DIR XDG_STATE_HOME="$XDG_STATE_HOME" bash -c '
    source "'"$BATS_TEST_DIRNAME"'/../../lib/functions/fn_rundir.sh"; cog::fn::rundir_lock_dir')"
  [[ $LOCK_FILE == "$expected_dir/"* ]]

  run --separate-stderr guard_stop "$$"

  [ "$status" -eq 2 ]
  [[ $stderr == *'"decision":"block"'* ]]
  rm -rf "$RUN_DIR" "$LOCK_FILE"
}

@test "executor-prex-stop blocks the owning session while artifacts are incomplete" {
  acquire "$$"

  run --separate-stderr guard_stop "$$"

  [ "$status" -eq 2 ]
  [[ $stderr == *'"decision":"block"'* ]]
  rm -rf "$RUN_DIR" "$LOCK_FILE"
}

@test "executor-prex-stop allows once all required artifacts exist" {
  acquire "$$"
  printf '%s\n' x >"$RUN_DIR/stage1-plan.txt"
  printf '%s\n' x >"$RUN_DIR/stage2-reviewed-plan.md"
  printf '%s\n' x >"$RUN_DIR/stage3-impl-report.txt"
  printf '%s\n' x >"$RUN_DIR/stage4-review.md"

  run guard_stop "$$"

  [ "$status" -eq 0 ]
  rm -rf "$RUN_DIR" "$LOCK_FILE"
}

@test "executor-prex-stop blocks when stage3 artifact is missing" {
  acquire "$$"
  printf '%s\n' x >"$RUN_DIR/stage1-plan.txt"
  printf '%s\n' x >"$RUN_DIR/stage2-reviewed-plan.md"
  printf '%s\n' x >"$RUN_DIR/stage4-review.md"

  run --separate-stderr guard_stop "$$"

  [ "$status" -eq 2 ]
  [[ $stderr == *"Stage 3: Implementation report"* ]]
  rm -rf "$RUN_DIR" "$LOCK_FILE"
}

@test "executor-prex-stop does not block a session that does not own the lock" {
  acquire "$$"

  run guard_stop 424242

  [ "$status" -eq 0 ]
  rm -rf "$RUN_DIR" "$LOCK_FILE"
}

@test "executor-prex-stop auto-cleans an orphaned lock (dead owner)" {
  acquire "$$"
  printf '%s\n%s\n' "$RUN_DIR" "999999" >"$LOCK_FILE"

  run guard_stop "$$"

  [ "$status" -eq 0 ]
  [ ! -e "$LOCK_FILE" ]
  rm -rf "$RUN_DIR"
}

@test "executor-prex-stop auto-cleans a lock whose run dir was deleted" {
  acquire "$$"
  rm -rf "$RUN_DIR"

  run guard_stop "$$"

  [ "$status" -eq 0 ]
  [ ! -e "$LOCK_FILE" ]
}
