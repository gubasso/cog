setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  mkdir -p "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GH_LOG}"
case "$*" in
  "pr view 7 --json comments --jq .comments[].body")
    printf '%s\n' "<!-- cog-review-finding:${EXISTING_KEY} -->"
    ;;
  pr\ comment\ 7\ --body*)
    exit 0
    ;;
  *)
    printf 'unexpected gh args: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/gh"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
  export GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
}

write_findings() {
  cat >"${BATS_TEST_TMPDIR}/findings.json" <<'JSON'
{"decision":"comment","summary":"s","strengths":[],"findings":[
{"severity":"important","file":"a.sh","line_start":1,"line_end":2,"category":"correctness","headline":"Same","evidence":"","reasoning":"Bad behavior.","suggestion":"Fix it.","confidence":"high"}
]}
JSON
}

@test "cog review-comment dry-run does not call gh" {
  write_findings

  run cog review-comment --findings "${BATS_TEST_TMPDIR}/findings.json" --pr 7 --dry-run --json

  assert_success
  [ ! -f "$GH_LOG" ]
  printf '%s\n' "$output" | jq -e '.dry_run == true and (.planned_comments | length) == 1' >/dev/null
}

@test "cog review-comment skips duplicate marker from gh" {
  write_findings
  EXISTING_KEY="$(cog review-comment --findings "${BATS_TEST_TMPDIR}/findings.json" --pr 7 --dry-run --json | jq -r '.planned_comments[0].key')"
  export EXISTING_KEY
  : >"$GH_LOG"

  run cog review-comment --findings "${BATS_TEST_TMPDIR}/findings.json" --pr 7 --json

  assert_success
  printf '%s\n' "$output" | jq -e '(.posted | length) == 0 and (.skipped_duplicates | length) == 1' >/dev/null
}
