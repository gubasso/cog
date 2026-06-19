setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_graph_queue() {
  local queue="$1"
  cat >"$queue" <<'EOF'
rounds:
  - item: done
    status: done
    depends_on: []
    prompt: /prex -ar done.md
    notes: ""
  - item: first
    status: todo
    depends_on: []
    prompt: /prex -ar first.md
    notes: ""
  - item: second
    status: todo
    depends_on:
      - first
    prompt: /prex -ar second.md
    notes: ""
EOF
}

@test "queue-graph-check reports valid graph and blocked diagnostics" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_graph_queue "$queue"

  run cog queue-graph-check --queue "$queue" --schema rounds --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true and
    .schema == "rounds" and
    .dangling_refs == [] and
    .cycles == [] and
    .canonical_order == ["done","first","second"] and
    (.blocked[] | select(.item == "second" and .missing_done == ["first"]))
  ' >/dev/null
}

@test "queue-graph-check fails closed on dangling dependency" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_graph_queue "$queue"
  yq e -i '(.rounds[] | select(.item == "first") | .depends_on) = ["missing"]' "$queue"

  run --separate-stderr cog queue-graph-check --queue "$queue" --schema rounds --json

  assert_failure
  [[ $stderr == *"queue dependency graph is invalid"* ]]
}

@test "queue-graph-check fails closed on cycle" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_graph_queue "$queue"
  yq e -i '(.rounds[] | select(.item == "first") | .depends_on) = ["second"]' "$queue"

  run --separate-stderr cog queue-graph-check --queue "$queue" --schema rounds --json

  assert_failure
  [[ $stderr == *"queue dependency graph is invalid"* ]]
}

@test "queue-graph-check --help dispatches" {
  run cog queue-graph-check --help

  assert_success
  [[ $output == *"Validate queue dependency graph"* ]]
}
