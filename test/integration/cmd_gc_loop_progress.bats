setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_round() {
  local path="$1"
  shift
  : >"$path"
  local hook
  for hook in "$@"; do
    {
      printf '%s' "$hook"
      printf '...Failed\n'
      printf -- '- hook id: %s\n' "$hook"
      printf -- '- exit code: 1\n\n'
    } >>"$path"
  done
}

@test "cog gc-loop-progress partitions hook signatures across rounds" {
  write_round "${BATS_TEST_TMPDIR}/r1.log" trailing-whitespace shellcheck
  write_round "${BATS_TEST_TMPDIR}/r2.log" shellcheck markdownlint

  run cog gc-loop-progress --current "${BATS_TEST_TMPDIR}/r2.log" --previous "${BATS_TEST_TMPDIR}/r1.log" --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    (.new == ["hook:markdownlint"]) and
    (.recurring == ["hook:shellcheck"]) and
    (.resolved == ["hook:trailing-whitespace"]) and
    (.counts.current == 2) and (.counts.previous == 2)
  ' >/dev/null
}

@test "cog gc-loop-progress reports zero churn for identical reports" {
  write_round "${BATS_TEST_TMPDIR}/r1.log" shellcheck markdownlint

  run cog gc-loop-progress --current "${BATS_TEST_TMPDIR}/r1.log" --previous "${BATS_TEST_TMPDIR}/r1.log" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.churn_ratio == 0 and .counts.recurring == 2' >/dev/null
}

@test "cog gc-loop-progress falls back to failure class when no hook ids" {
  printf 'commit message rejected by the Conventional Commits check\n- subject is too long\n' \
    >"${BATS_TEST_TMPDIR}/m1.log"
  cp "${BATS_TEST_TMPDIR}/m1.log" "${BATS_TEST_TMPDIR}/m2.log"

  run cog gc-loop-progress --current "${BATS_TEST_TMPDIR}/m2.log" --previous "${BATS_TEST_TMPDIR}/m1.log" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.recurring == ["class:commit-message"]' >/dev/null
}

@test "cog gc-loop-progress requires both report paths" {
  run cog gc-loop-progress --current "${BATS_TEST_TMPDIR}/only.log" --json
  assert_failure
}
