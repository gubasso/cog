setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_findings() {
  cat >"${BATS_TEST_TMPDIR}/one.json" <<'JSON'
{"decision":"comment","summary":"s","strengths":[],"findings":[
{"severity":"important","file":"a.sh","line_start":1,"line_end":1,"category":"correctness","headline":"Same","evidence":"","reasoning":"","suggestion":"","confidence":"high"}
]}
JSON
  cp "${BATS_TEST_TMPDIR}/one.json" "${BATS_TEST_TMPDIR}/two.json"
}

@test "cog review-loop-progress emits comparison JSON" {
  write_findings

  run cog review-loop-progress --current "${BATS_TEST_TMPDIR}/two.json" --previous "${BATS_TEST_TMPDIR}/one.json" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.counts.recurring == 1 and .churn_ratio == 0' >/dev/null
}
