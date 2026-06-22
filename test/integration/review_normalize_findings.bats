setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_findings() {
  cat >"${BATS_TEST_TMPDIR}/findings.json" <<'JSON'
{"decision":"comment","summary":"s","strengths":[],"findings":[
{"severity":"suggestion","file":"b.sh","line_start":9,"line_end":9,"category":"style","headline":"Suggestion","evidence":"","reasoning":"","suggestion":"","confidence":"high"},
{"severity":"important","file":"a.sh","line_start":2,"line_end":2,"category":"test","headline":"Important","evidence":"","reasoning":"","suggestion":"","confidence":"medium"}
]}
JSON
}

@test "cog review-normalize-findings emits normalized JSON" {
  write_findings

  run cog review-normalize-findings --findings "${BATS_TEST_TMPDIR}/findings.json" --severity important --json

  assert_success
  printf '%s\n' "$output" | jq -e '(.findings | length) == 1 and .findings[0].headline == "Important"' >/dev/null
}

@test "cog review-normalize-findings writes output file" {
  write_findings
  local out="${BATS_TEST_TMPDIR}/out.json"

  run cog review-normalize-findings --findings "${BATS_TEST_TMPDIR}/findings.json" --out "$out"

  assert_success
  assert_output "RESOLVED $out"
  jq -e '.findings | length == 2' "$out" >/dev/null
}
