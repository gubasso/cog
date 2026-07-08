setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR REFACTOR_GUIDELINE
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/source/src" "${BATS_TEST_TMPDIR}/run"
  printf '[package]\nname = "demo"\n' >"${BATS_TEST_TMPDIR}/source/Cargo.toml"
  printf '# Demo\n' >"${BATS_TEST_TMPDIR}/source/README.md"
  printf 'pub fn demo() {}\n' >"${BATS_TEST_TMPDIR}/source/src/lib.rs"
  printf 'test\n' >"${BATS_TEST_TMPDIR}/source/src/lib_test.rs"
}

@test "cog refactor-scan-source writes scan artifacts" {
  run cog refactor-scan-source --source-root "${BATS_TEST_TMPDIR}/source" --run-dir "${BATS_TEST_TMPDIR}/run" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .counts.manifest_hits == 1 and (.fingerprint | test("^[0-9a-f]{64}$"))' >/dev/null
  assert_file_exists "${BATS_TEST_TMPDIR}/run/source-scan/root-ls.txt"
  assert_file_exists "${BATS_TEST_TMPDIR}/run/scan-fingerprint.txt"
}

@test "cog refactor-scan-source --help dispatches" {
  run cog refactor-scan-source --help

  assert_success
  [[ $output == *"Run deterministic source static-analysis probes"* ]]
}
