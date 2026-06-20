setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_reorder_queue() {
  local queue="$1"
  cat >"$queue" <<'EOF'
rounds:
  - item: done
    status: done
    depends_on: []
    prompt: /executor-prex -ar done.md
    notes: ""
  - item: second
    status: todo
    depends_on:
      - first
    prompt: /executor-prex -ar second.md
    notes: ""
  - item: doing
    status: doing
    depends_on:
      - done
    prompt: /executor-prex -ar doing.md
    notes: ""
  - item: first
    status: backlog
    depends_on: []
    prompt: /executor-prex -ar first.md
    notes: ""
EOF
}

@test "queue-reorder topologically reorders only mutable slots" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_reorder_queue "$queue"

  run cog queue-reorder --queue "$queue" --schema rounds --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .changed == true and
    .order_before == ["done","second","doing","first"] and
    .order_after == ["done","first","doing","second"] and
    .mutable_order == ["first","second"]
  ' >/dev/null
  yq e -o=json '.' "$queue" | jq -e '
    [.rounds[].item] == ["done","first","doing","second"] and
    .rounds[0].status == "done" and
    .rounds[2].status == "doing"
  ' >/dev/null
}

@test "queue-reorder is idempotent when canonical" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_reorder_queue "$queue"
  cog queue-reorder --queue "$queue" --schema rounds --json >/dev/null

  run cog queue-reorder --queue "$queue" --schema rounds --json

  assert_success
  printf '%s\n' "$output" | jq -e '.changed == false' >/dev/null
}

@test "queue-reorder fails closed on dangling dependency" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_reorder_queue "$queue"
  yq e -i '(.rounds[] | select(.item == "first") | .depends_on) = ["missing"]' "$queue"

  run --separate-stderr cog queue-reorder --queue "$queue" --schema rounds --json

  assert_failure
  [[ $stderr == *"queue dependency graph is invalid"* ]]
}

@test "queue-reorder fails closed on cycle" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_reorder_queue "$queue"
  yq e -i '(.rounds[] | select(.item == "first") | .depends_on) = ["second"]' "$queue"

  run --separate-stderr cog queue-reorder --queue "$queue" --schema rounds --json

  assert_failure
  [[ $stderr == *"queue dependency graph is invalid"* ]]
}
