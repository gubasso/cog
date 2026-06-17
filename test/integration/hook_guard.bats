setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset XDG_RUNTIME_DIR
  mkdir -p "$HOME" "$XDG_STATE_HOME"
}

guard_fg() {
  printf '%s' "$1" | cog hook-guard codex-foreground
}

guard_stop() {
  printf '{}' | cog hook-guard prex-stop --owner-pid "$1"
}

acquire() {
  local out
  out="$(cog rundir prex --lock --owner-pid "$1")"
  RUN_DIR="$(sed -n 's/^RUN_DIR=//p' <<<"$out")"
  LOCK_FILE="$(sed -n 's/^LOCK_FILE=//p' <<<"$out")"
}

@test "codex-foreground blocks a backgrounded Codex call" {
  run guard_fg '{"tool_name":"Bash","tool_input":{"command":"cog codex-runner run-resume","run_in_background":true,"timeout":600000}}'

  [ "$status" -eq 2 ]
}

@test "codex-foreground blocks a Codex call with a sub-600000ms timeout" {
  run guard_fg '{"tool_name":"Bash","tool_input":{"command":"cog codex-runner run-exec --mode danger","timeout":120000}}'

  [ "$status" -eq 2 ]
}

@test "codex-foreground blocks a Codex call with no timeout" {
  run guard_fg '{"tool_name":"Bash","tool_input":{"command":"cog codex-runner run-exec"}}'

  [ "$status" -eq 2 ]
}

@test "codex-foreground allows a foreground Codex call with timeout >= 600000" {
  run guard_fg '{"tool_name":"Bash","tool_input":{"command":"cog codex-runner run-exec --mode danger","timeout":600000}}'

  [ "$status" -eq 0 ]
}

@test "codex-foreground ignores a backgrounded NON-Codex call" {
  run guard_fg '{"tool_name":"Bash","tool_input":{"command":"npm run dev","run_in_background":true}}'

  [ "$status" -eq 0 ]
}

@test "codex-foreground ignores a plain non-Codex call" {
  run guard_fg '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'

  [ "$status" -eq 0 ]
}

@test "codex-foreground deny reason is legible on stderr" {
  run --separate-stderr guard_fg '{"tool_input":{"command":"cog codex-runner run-resume","run_in_background":true,"timeout":600000}}'

  [ "$status" -eq 2 ]
  [[ $stderr == *"BLOCKED"* ]]
  [[ $stderr == *"FOREGROUND"* ]]
}

@test "codex-foreground allows codex-session package path mentions" {
  run guard_fg '{"tool_name":"Bash","tool_input":{"command":"git diff -- lib/commands codex-session","run_in_background":true,"timeout":120000}}'
  [ "$status" -eq 0 ]

  run guard_fg '{"tool_name":"Bash","tool_input":{"command":"cat codex-session/foo","run_in_background":true,"timeout":120000}}'
  [ "$status" -eq 0 ]
}

@test "codex-foreground allows fast codex-runner probes" {
  run guard_fg '{"tool_name":"Bash","tool_input":{"command":"cog codex-runner gate sandbox out.json","timeout":120000}}'

  [ "$status" -eq 0 ]
}

@test "codex-foreground allows quoted or echoed wrapper mentions" {
  run guard_fg '{"tool_name":"Bash","tool_input":{"command":"echo cog codex-runner run-exec","timeout":120000}}'

  [ "$status" -eq 0 ]
}

@test "codex-foreground matches multiline wrapper command position" {
  run --separate-stderr guard_fg '{"tool_name":"Bash","tool_input":{"command":"RUNNER_MODE=native\ncog codex-runner run-exec","run_in_background":true,"timeout":600000}}'

  [ "$status" -eq 2 ]
  [[ $stderr == *"BLOCKED"* ]]
}

@test "codex-foreground matches separator wrapper command position" {
  run --separate-stderr guard_fg '{"tool_name":"Bash","tool_input":{"command":"foo && cog codex-runner run-exec","timeout":120000}}'

  [ "$status" -eq 2 ]
  [[ $stderr == *"600000"* ]]
}

@test "codex-foreground matches subshell and trailing ampersand wrapper forms" {
  run --separate-stderr guard_fg '{"tool_name":"Bash","tool_input":{"command":"(cog codex-runner run-exec)","timeout":120000}}'
  [ "$status" -eq 2 ]

  run --separate-stderr guard_fg '{"tool_name":"Bash","tool_input":{"command":"cog codex-runner run-exec&","timeout":120000}}'
  [ "$status" -eq 2 ]
}

@test "prex-stop allows when there are no locks" {
  run guard_stop 999999

  [ "$status" -eq 0 ]
}

@test "prex-stop writes and looks for the lock in the same dir with XDG_RUNTIME_DIR unset" {
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

@test "prex-stop blocks the owning session while artifacts are incomplete" {
  acquire "$$"

  run --separate-stderr guard_stop "$$"

  [ "$status" -eq 2 ]
  [[ $stderr == *'"decision":"block"'* ]]
  rm -rf "$RUN_DIR" "$LOCK_FILE"
}

@test "prex-stop allows once all required artifacts exist" {
  acquire "$$"
  printf '%s\n' x >"$RUN_DIR/stage1-plan.txt"
  printf '%s\n' x >"$RUN_DIR/stage2-reviewed-plan.md"
  printf '%s\n' x >"$RUN_DIR/stage4-review.md"

  run guard_stop "$$"

  [ "$status" -eq 0 ]
  rm -rf "$RUN_DIR" "$LOCK_FILE"
}

@test "prex-stop does not block a session that does not own the lock" {
  acquire "$$"

  run guard_stop 424242

  [ "$status" -eq 0 ]
  rm -rf "$RUN_DIR" "$LOCK_FILE"
}

@test "prex-stop auto-cleans an orphaned lock (dead owner)" {
  acquire "$$"
  printf '%s\n%s\n' "$RUN_DIR" "999999" >"$LOCK_FILE"

  run guard_stop "$$"

  [ "$status" -eq 0 ]
  [ ! -e "$LOCK_FILE" ]
  rm -rf "$RUN_DIR"
}

@test "prex-stop auto-cleans a lock whose run dir was deleted" {
  acquire "$$"
  rm -rf "$RUN_DIR"

  run guard_stop "$$"

  [ "$status" -eq 0 ]
  [ ! -e "$LOCK_FILE" ]
}
