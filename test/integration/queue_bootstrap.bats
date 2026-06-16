setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog queue-bootstrap creates plans and rounds queues" {
  local plans="${BATS_TEST_TMPDIR}/plans/QUEUE.yaml"
  local rounds="${BATS_TEST_TMPDIR}/rounds/QUEUE.yaml"

  run cog queue-bootstrap --schema plans --queue "$plans" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.created == true and .list_key == "plans"' >/dev/null
  grep -F "plans: []" "$plans"

  run cog queue-bootstrap --schema rounds --queue "$rounds" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.created == true and .list_key == "rounds"' >/dev/null
  grep -F "rounds: []" "$rounds"
}

@test "cog queue-bootstrap is idempotent and rejects invalid schema" {
  local queue="${BATS_TEST_TMPDIR}/QUEUE.yaml"
  run cog queue-bootstrap --schema rounds --queue "$queue" --json
  assert_success

  run cog queue-bootstrap --schema rounds --queue "$queue" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.created == false' >/dev/null

  run --separate-stderr cog queue-bootstrap --schema bad --queue "$queue" --json
  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog queue-bootstrap --help dispatches" {
  run cog queue-bootstrap --help

  assert_success
  [[ $output == *"Create and validate"* ]]
}
