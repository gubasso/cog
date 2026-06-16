setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_classification() {
  cat >"${BATS_TEST_TMPDIR}/classification.json" <<'JSON'
{"git_root":"/tmp/repo","is_cli":true,"cli_signals":["bin entry"],"project_types":["cli"],"languages":[{"lang":"bash"}],"frameworks":[]}
JSON
}

@test "cog review-cli-signals projects classification" {
  write_classification

  run cog review-cli-signals --classification "${BATS_TEST_TMPDIR}/classification.json" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.is_cli == true and .signal_count == 1 and .languages[0].lang == "bash"' >/dev/null
}

@test "cog review-cli-signals requires classification this round" {
  run --separate-stderr cog review-cli-signals --json

  assert_failure
  [[ $stderr == *"err.kind: MissingClassification"* ]]
}

@test "cog review-cli-signals rejects invalid classification" {
  printf '%s\n' "{" >"${BATS_TEST_TMPDIR}/bad.json"

  run --separate-stderr cog review-cli-signals --classification "${BATS_TEST_TMPDIR}/bad.json" --json

  assert_failure
  [[ $stderr == *"err.kind: InvalidJsonInput"* ]]
}

@test "cog review-cli-signals writes fragments and supports help" {
  write_classification
  local out="${BATS_TEST_TMPDIR}/cli.json"

  run cog review-cli-signals --classification "${BATS_TEST_TMPDIR}/classification.json" "$out"
  assert_success
  assert_output "RESOLVED $out"

  run cog review-cli-signals --help
  assert_success
}
