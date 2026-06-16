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
  source "${LIB_DIR}/functions/fn_refactor.sh"
}

@test "refactor_scan_fingerprint is independent of file creation order" {
  local a="${BATS_TEST_TMPDIR}/a"
  local b="${BATS_TEST_TMPDIR}/b"
  mkdir -p "$a/nested" "$b/nested"
  printf '%s' second >"$a/nested/two.txt"
  printf '%s' first >"$a/one.txt"
  printf '%s' first >"$b/one.txt"
  printf '%s' second >"$b/nested/two.txt"

  run cog::fn::refactor_scan_fingerprint "$a"
  assert_success
  local first_hash="$output"

  run cog::fn::refactor_scan_fingerprint "$b"
  assert_success
  [ "$output" = "$first_hash" ]
}

@test "refactor_scan_fingerprint handles empty directories" {
  local scan="${BATS_TEST_TMPDIR}/empty"
  mkdir -p "$scan"
  local expected
  expected="$(printf '' | sha256sum | cut -d' ' -f1)"

  run cog::fn::refactor_scan_fingerprint "$scan"

  assert_success
  assert_output "$expected"
}

@test "refactor_scan_fingerprint missing directory exits noinput" {
  run --separate-stderr cog::fn::refactor_scan_fingerprint "${BATS_TEST_TMPDIR}/missing"

  assert_failure 66
  [[ $stderr == *"err.kind: InputNotFound"* ]]
}

@test "refactor_scan_fingerprint_recipe prints documented command" {
  run cog::fn::refactor_scan_fingerprint_recipe

  assert_success
  # shellcheck disable=SC2016
  assert_output '( cd "$SCAN" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 cat 2>/dev/null | sha256sum | cut -d'\'' '\'' -f1 )'
}
