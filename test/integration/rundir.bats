setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
}

@test "cog rundir creates a run directory" {
  run cog rundir review

  assert_success
  assert_line --regexp '^RUN_DIR=.*review-'
  local run_dir="${output#RUN_DIR=}"
  [ -d "$run_dir" ]
}

@test "cog rundir snapshot-children captures only matching child dirs" {
  local base="${XDG_STATE_HOME}/cog/runs"
  local snap="${BATS_TEST_TMPDIR}/children.snap"
  mkdir -p "${base}/review-loop-old" "${base}/not-review-loop"

  run cog rundir snapshot-children --prefix review-loop --out "$snap"

  assert_success
  assert_output "RESOLVED $snap"
  assert_file_contains "$snap" "${base}/review-loop-old"
  if grep -F "${base}/not-review-loop" "$snap" >/dev/null; then
    return 1
  fi
}

@test "cog rundir locate-child returns the single new child" {
  local old="${BATS_TEST_TMPDIR}/review-loop-old"
  local new="${BATS_TEST_TMPDIR}/review-loop-new"
  local pre="${BATS_TEST_TMPDIR}/pre.snap"
  local post="${BATS_TEST_TMPDIR}/post.snap"
  local proof="${BATS_TEST_TMPDIR}/proof.diff"
  printf '%s\n' "$old" | sort >"$pre"
  printf '%s\n%s\n' "$old" "$new" | sort >"$post"

  run cog rundir locate-child --pre "$pre" --post "$post" --proof "$proof"

  assert_success
  assert_output "CHILD_RUN_DIR=$new"
  assert_file_exists "$proof"
  assert_file_contains "$proof" "$new"
}

@test "cog rundir locate-child emits JSON" {
  local old="${BATS_TEST_TMPDIR}/review-loop-old"
  local new="${BATS_TEST_TMPDIR}/review-loop-new"
  local pre="${BATS_TEST_TMPDIR}/pre.snap"
  local post="${BATS_TEST_TMPDIR}/post.snap"
  printf '%s\n' "$old" | sort >"$pre"
  printf '%s\n%s\n' "$old" "$new" | sort >"$post"

  run cog rundir locate-child --pre "$pre" --post "$post" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.child_run_dir == "'"$new"'"' >/dev/null
}

@test "cog rundir locate-child fails when no new child exists" {
  local old="${BATS_TEST_TMPDIR}/review-loop-old"
  local pre="${BATS_TEST_TMPDIR}/pre.snap"
  local post="${BATS_TEST_TMPDIR}/post.snap"
  printf '%s\n' "$old" | sort >"$pre"
  printf '%s\n' "$old" | sort >"$post"

  run --separate-stderr cog rundir locate-child --pre "$pre" --post "$post"

  assert_failure
  [[ $stderr == *"err.kind: InputNotFound"* ]]
}

@test "cog rundir locate-child fails when multiple children are new" {
  local old="${BATS_TEST_TMPDIR}/review-loop-old"
  local new_a="${BATS_TEST_TMPDIR}/review-loop-new-a"
  local new_b="${BATS_TEST_TMPDIR}/review-loop-new-b"
  local pre="${BATS_TEST_TMPDIR}/pre.snap"
  local post="${BATS_TEST_TMPDIR}/post.snap"
  printf '%s\n' "$old" | sort >"$pre"
  printf '%s\n%s\n%s\n' "$old" "$new_a" "$new_b" | sort >"$post"

  run --separate-stderr cog rundir locate-child --pre "$pre" --post "$post"

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
  [[ $stderr == *"ambiguous child run directory"* ]]
}

@test "cog rundir locks and emits JSON" {
  run cog rundir review --lock --owner-pid 123 --json

  assert_success
  printf '%s\n' "$output" | jq -e '.run_dir and .lock_file' >/dev/null
  [ -f "$(printf '%s\n' "$output" | jq -r '.lock_file')" ]
}

@test "cog rundir requires owner pid when locking" {
  run --separate-stderr cog rundir review --lock

  assert_failure
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}

@test "cog rundir --help dispatches" {
  run cog rundir --help

  assert_success
  [[ $output == *"Create a workflow run directory"* ]]
}
