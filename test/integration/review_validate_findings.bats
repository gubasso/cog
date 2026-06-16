setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_findings() {
  cat >"${BATS_TEST_TMPDIR}/findings.json" <<'JSON'
{"decision":"comment","summary":"Looks good","strengths":[],"findings":[{"severity":"important","file":"lib/a.sh","line_start":1,"line_end":1,"category":"correctness","headline":"Issue","evidence":"","reasoning":"","suggestion":"","confidence":"high"}]}
JSON
}

@test "cog review-validate-findings validates findings" {
  write_findings

  run cog review-validate-findings --findings "${BATS_TEST_TMPDIR}/findings.json" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .findings_count == 1' >/dev/null
}

@test "cog review-validate-findings reports schema errors" {
  write_findings
  jq '.findings[0].severity = "bad"' "${BATS_TEST_TMPDIR}/findings.json" >"${BATS_TEST_TMPDIR}/bad.json"

  run --separate-stderr cog review-validate-findings --findings "${BATS_TEST_TMPDIR}/bad.json" --json

  assert_failure
  [[ $stderr == *"severity is invalid"* ]]
}

@test "cog review-validate-findings writes fragments" {
  write_findings
  local out="${BATS_TEST_TMPDIR}/validated.json"

  run cog review-validate-findings --findings "${BATS_TEST_TMPDIR}/findings.json" "$out"

  assert_success
  assert_output "RESOLVED $out"
  jq -e '.findings_count == 1' "$out" >/dev/null
}

@test "cog review-validate-findings --help dispatches" {
  run cog review-validate-findings --help

  assert_success
  [[ $output == *"Validate review findings"* ]]
}
