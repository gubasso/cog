setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog queue-append appends one entry without changing prefix" {
  local queue="${BATS_TEST_TMPDIR}/queue-rounds.yaml"
  local prefix="${BATS_TEST_TMPDIR}/prefix.txt"
  cat >"$queue" <<'EOF'
# queue fixture
rounds:
  - item: first
    status: done
    depends_on: []
    prompt: /prex -ar first.md
    notes: note
EOF
  cp "$queue" "$prefix"

  run cog queue-append --schema rounds --queue "$queue" --item second --status todo --prompt "/prex -ar second.md" --depends-on first,setup --notes "note" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.append_only_verified == true and .count_before == 1 and .count_after == 2 and .appended.depends_on == ["first","setup"]' >/dev/null
  head -c "$(wc -c <"$prefix")" "$queue" | cmp -s "$prefix" -
  assert_file_contains "$queue" "  - item: second"
}

@test "cog queue-append rejects duplicate items" {
  local queue="${BATS_TEST_TMPDIR}/queue-rounds.yaml"
  printf '%s\n' "rounds: []" >"$queue"
  cog queue-append --schema rounds --queue "$queue" --item same --status todo --prompt "/prex -ar one.md" --json >/dev/null

  run --separate-stderr cog queue-append --schema rounds --queue "$queue" --item same --status todo --prompt "/prex -ar two.md" --json

  assert_failure
  [[ $stderr == *"duplicate queue item"* ]]
}

@test "cog queue-append --help dispatches" {
  run cog queue-append --help

  assert_success
  [[ $output == *"Append one implementation"* ]]
}
