setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR DOCS_NOTES_REPO REFACTOR_GUIDELINE RIPTASK_REPO
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/scan"
  printf 'hello\n' >"${BATS_TEST_TMPDIR}/scan/a.txt"
}

@test "cog refactor-scan-drift computes fingerprint" {
  local expected
  expected="$(cog refactor-scan-drift --scan "${BATS_TEST_TMPDIR}/scan" --json | jq -r '.fingerprint')"

  run cog refactor-scan-drift --scan "${BATS_TEST_TMPDIR}/scan" --expected "$expected" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.matches_expected == true and (.recipe | contains("sha256sum"))' >/dev/null
}

@test "cog refactor-scan-drift --help dispatches" {
  run cog refactor-scan-drift --help

  assert_success
  [[ $output == *"Compute byte-stable source-scan fingerprint"* ]]
}
