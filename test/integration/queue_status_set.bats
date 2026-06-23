setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_plans_queue() {
  local queue="$1"
  cat >"$queue" <<'EOF'
plans:
  - item: first
    status: done
    depends_on: []
    prompt: /executor-prex -ar @plans/first/
    notes: note
  - item: second
    status: todo
    depends_on: [first]
    prompt: /executor-prex -ar @plans/second/
    notes: note
EOF
}

write_rounds_queue() {
  local queue="$1"
  cat >"$queue" <<'EOF'
rounds:
  - item: first
    status: done
    depends_on: []
    prompt: /executor-prex -ar first.md
    notes: note
  - item: second
    status: todo
    depends_on: [first]
    prompt: /executor-prex -ar second.md
    notes: note
EOF
}

@test "cog queue-status-set flips one plans item" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  write_plans_queue "$queue"

  run cog queue-status-set --queue "$queue" --schema plans --item second --from todo --to "done" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .schema == "plans" and .item == "second" and .status_before == "todo" and .status_after == "done" and .changed == true' >/dev/null
  yq e -e '.plans | length == 2' "$queue" >/dev/null
  yq e -e '.plans[0].status == "done" and .plans[1].status == "done"' "$queue" >/dev/null
  yq e -e '.plans[0].prompt == "/executor-prex -ar @plans/first/" and .plans[1].prompt == "/executor-prex -ar @plans/second/"' "$queue" >/dev/null
}

@test "cog queue-status-set flips one rounds item" {
  local queue="${BATS_TEST_TMPDIR}/queue-rounds.yaml"
  write_rounds_queue "$queue"

  run cog queue-status-set --queue "$queue" --schema rounds --item second --from todo --to "done" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .schema == "rounds" and .status_before == "todo" and .status_after == "done"' >/dev/null
  yq e -e '.rounds | length == 2' "$queue" >/dev/null
  yq e -e '.rounds[0].status == "done" and .rounds[1].status == "done"' "$queue" >/dev/null
}

@test "cog queue-status-set --idempotent is a no-op when already at target" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  write_plans_queue "$queue"
  local before
  before="$(cat "$queue")"

  run cog queue-status-set --queue "$queue" --schema plans --item first --from todo --to "done" --idempotent --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .changed == false and .status_before == "done" and .status_after == "done"' >/dev/null
  [[ "$(cat "$queue")" == "$before" ]]
}

@test "cog queue-status-set --idempotent still flips from todo" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  write_plans_queue "$queue"

  run cog queue-status-set --queue "$queue" --schema plans --item second --from todo --to "done" --idempotent --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .changed == true and .status_before == "todo" and .status_after == "done"' >/dev/null
  yq e -e '.plans[1].status == "done"' "$queue" >/dev/null
}

@test "cog queue-status-set --idempotent fails closed on an unexpected current status" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  write_plans_queue "$queue"
  yq e -i '.plans[1].status = "doing"' "$queue"

  run --separate-stderr cog queue-status-set --queue "$queue" --schema plans --item second --from todo --to "done" --idempotent --json
  assert_failure
  [[ $stderr == *"queue item status mismatch"* ]]
  yq e -e '.plans[1].status == "doing"' "$queue" >/dev/null
}

@test "cog queue-status-set fails for missing item and wrong from status" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  write_plans_queue "$queue"

  run --separate-stderr cog queue-status-set --queue "$queue" --schema plans --item missing --from todo --to "done" --json
  assert_failure
  [[ $stderr == *"queue item not found"* ]]

  run --separate-stderr cog queue-status-set --queue "$queue" --schema plans --item second --from doing --to "done" --json
  assert_failure
  [[ $stderr == *"queue item status mismatch"* ]]
  yq e -e '.plans[1].status == "todo"' "$queue" >/dev/null
}

@test "cog queue-status-set fails for invalid status duplicate item and missing queue" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  write_plans_queue "$queue"

  run --separate-stderr cog queue-status-set --queue "$queue" --schema plans --item second --from invalid --to "done" --json
  assert_failure 2
  [[ $stderr == *"invalid from status"* ]]

  cat >"$queue" <<'EOF'
plans:
  - item: same
    status: todo
    depends_on: []
    prompt: /executor-prex -ar @plans/same/
    notes: note
  - item: same
    status: todo
    depends_on: []
    prompt: /executor-prex -ar @plans/same-again/
    notes: note
EOF
  run --separate-stderr cog queue-status-set --queue "$queue" --schema plans --item same --from todo --to "done" --json
  assert_failure
  [[ $stderr == *"duplicate queue items"* ]]

  run --separate-stderr cog queue-status-set --queue "${BATS_TEST_TMPDIR}/missing.yaml" --schema plans --item same --from todo --to "done" --json
  assert_failure
  [[ $stderr == *"queue file not found"* ]]
}
