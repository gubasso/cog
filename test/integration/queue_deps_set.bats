setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_deps_queue() {
  local queue="$1"
  cat >"$queue" <<'EOF'
rounds:
  - item: done
    status: done
    depends_on: []
    prompt: /executor-prex -ar done.md
    notes: ""
  - item: doing
    status: doing
    depends_on:
      - done
    prompt: /executor-prex -ar doing.md
    notes: ""
  - item: first
    status: todo
    depends_on: []
    prompt: /executor-prex -ar first.md
    notes: ""
  - item: second
    status: backlog
    depends_on:
      - first
    prompt: /executor-prex -ar second.md
    notes: ""
EOF
}

@test "queue-deps-set replaces mutable dependency list" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_deps_queue "$queue"

  run cog queue-deps-set --queue "$queue" --schema rounds --item first --depends-on "done" --expect "" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.changed == true and .depends_before == [] and .depends_after == ["done"]' >/dev/null
  yq e -o=json '.' "$queue" | jq -e '.rounds[] | select(.item == "first") | .depends_on == ["done"]' >/dev/null
}

@test "queue-deps-set refuses done and doing items" {
  local item queue
  for item in "done" "doing"; do
    queue="${BATS_TEST_TMPDIR}/queue-${item}.yaml"
    write_deps_queue "$queue"

    run --separate-stderr cog queue-deps-set --queue "$queue" --schema rounds --item "$item" --depends-on first --json

    assert_failure
    [[ $stderr == *"queue item is not mutable"* ]]
  done
}

@test "queue-deps-set fails on dangling dependency" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_deps_queue "$queue"

  run --separate-stderr cog queue-deps-set --queue "$queue" --schema rounds --item first --depends-on missing --json

  assert_failure
  [[ $stderr == *"queue dependency graph is invalid"* ]]
}

@test "queue-deps-set fails on cycle" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_deps_queue "$queue"

  run --separate-stderr cog queue-deps-set --queue "$queue" --schema rounds --item first --depends-on second --json

  assert_failure
  [[ $stderr == *"queue dependency graph is invalid"* ]]
}

@test "queue-deps-set requires --depends-on and leaves queue unchanged when omitted" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_deps_queue "$queue"
  local before
  before="$(yq e -o=json '.' "$queue")"

  run --separate-stderr cog queue-deps-set --queue "$queue" --schema rounds --item second --json

  assert_failure
  [[ $stderr == *"--depends-on"* ]]
  [[ "$(yq e -o=json '.' "$queue")" == "$before" ]]
}

@test "queue-deps-set clears dependencies with explicit empty --depends-on" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_deps_queue "$queue"

  run cog queue-deps-set --queue "$queue" --schema rounds --item second --depends-on "" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.changed == true and .depends_before == ["first"] and .depends_after == []' >/dev/null
  yq e -o=json '.' "$queue" | jq -e '.rounds[] | select(.item == "second") | .depends_on == []' >/dev/null
}

@test "queue-deps-set enforces expect guard" {
  local queue="${BATS_TEST_TMPDIR}/queue.yaml"
  write_deps_queue "$queue"

  run --separate-stderr cog queue-deps-set --queue "$queue" --schema rounds --item second --depends-on "done" --expect "done" --json

  assert_failure
  [[ $stderr == *"queue item dependency mismatch"* ]]
}
