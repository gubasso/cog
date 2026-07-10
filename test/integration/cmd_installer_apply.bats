setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR REFACTOR_GUIDELINE
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/repo"
}

@test "cog installer-apply writes the executable installer trio for bash" {
  run cog installer-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type bash --json

  assert_success
  for f in install.sh uninstall.sh install-common.sh; do
    [ -f "${BATS_TEST_TMPDIR}/repo/$f" ]
    [ "$(stat -c '%a' "${BATS_TEST_TMPDIR}/repo/$f")" = "755" ]
  done
  printf '%s\n' "$output" | jq -e '.ok == true and ([.copied[].dst] | length) == 3' >/dev/null
}

@test "cog installer-apply supports the native-wrap types" {
  run cog installer-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type rust --json

  assert_success
  grep -q 'cargo' "${BATS_TEST_TMPDIR}/repo/install.sh"
  printf '%s\n' "$output" | jq -e '.ok == true' >/dev/null
}

@test "cog installer-apply aborts on an existing installer" {
  : >"${BATS_TEST_TMPDIR}/repo/install.sh"

  run --separate-stderr cog installer-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type bash --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "destination conflict"' >/dev/null
}

@test "cog installer-apply skips an existing installer under skip policy" {
  printf 'keep\n' >"${BATS_TEST_TMPDIR}/repo/install.sh"

  run cog installer-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type bash --conflict skip --json

  assert_success
  grep -qx 'keep' "${BATS_TEST_TMPDIR}/repo/install.sh"
  printf '%s\n' "$output" | jq -e '[.skipped[].dst] | any(endswith("/install.sh"))' >/dev/null
}

@test "cog installer-apply rejects an unknown type" {
  run --separate-stderr cog installer-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type cobol --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "template dir is not a directory"' >/dev/null
}

@test "cog installer-apply rejects an invalid --wire-taskrunner value" {
  run --separate-stderr cog installer-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type bash --wire-taskrunner cmake --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "wire-taskrunner must be just or make"' >/dev/null
}

@test "cog installer-apply injects task-runner recipes idempotently" {
  printf 'default:\n    @just --list\n' >"${BATS_TEST_TMPDIR}/repo/justfile"

  run cog installer-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type bash --wire-taskrunner just --json
  assert_success
  printf '%s\n' "$output" | jq -e '(.wired | sort) == ["install","reinstall","uninstall"]' >/dev/null
  grep -q '^install:' "${BATS_TEST_TMPDIR}/repo/justfile"
  grep -q '^# --- cog installer ---' "${BATS_TEST_TMPDIR}/repo/justfile"

  run cog installer-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type bash --conflict overwrite --wire-taskrunner just --json
  assert_success
  printf '%s\n' "$output" | jq -e '.wired == []' >/dev/null
}

@test "cog installer-apply reports a missing runner without failing" {
  run cog installer-apply --project-root "${BATS_TEST_TMPDIR}/repo" --type bash --wire-taskrunner just --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .wire_target == null and (.wire_reason | test("no just runner"))' >/dev/null
}
