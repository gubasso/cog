setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  cat >"$queue" <<'EOF'
plans:
  - item: first
    status: todo
    depends_on: []
    prompt: /executor-prex -ar @plans/first/
    notes: note one
  - item: second
    status: backlog
    depends_on:
      - first
    prompt: /executor-lean -ar @plans/second/
    notes: note two
EOF
}

@test "cog queue-prompt-set rewrites one prompt with guard" {
  run cog queue-prompt-set --queue "$queue" --schema plans --item first \
    --from "/executor-prex -ar @plans/first/" \
    --to "/runner-plan -ar @plans/first/" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .changed == true and .prompt_before == "/executor-prex -ar @plans/first/" and .prompt_after == "/runner-plan -ar @plans/first/"' >/dev/null
  yq e -r '.plans[] | select(.item == "first") | .prompt' "$queue" | grep -Fx "/runner-plan -ar @plans/first/" >/dev/null
  yq e -o=json '.' "$queue" | jq -e '
    .plans[0].status == "todo" and
    .plans[0].depends_on == [] and
    .plans[0].notes == "note one" and
    .plans[1].item == "second" and
    .plans[1].prompt == "/executor-lean -ar @plans/second/"
  ' >/dev/null
}

@test "cog queue-prompt-set fails on wrong expected prompt" {
  run --separate-stderr cog queue-prompt-set --queue "$queue" --schema plans --item first \
    --from "/wrong" --to "/runner-plan -ar @plans/first/" --json

  assert_failure
  [[ $stderr == *"queue item prompt mismatch"* ]]
  yq e -r '.plans[] | select(.item == "first") | .prompt' "$queue" | grep -Fx "/executor-prex -ar @plans/first/" >/dev/null
}

@test "cog queue-prompt-set fails on missing and duplicate items" {
  run --separate-stderr cog queue-prompt-set --queue "$queue" --schema plans --item missing \
    --from "/old" --to "/new" --json
  assert_failure
  [[ $stderr == *"queue item not found"* ]]

  cat >>"$queue" <<'EOF'
  - item: first
    status: todo
    depends_on: []
    prompt: /executor-prex -ar @plans/dupe/
    notes: duplicate
EOF
  run --separate-stderr cog queue-prompt-set --queue "$queue" --schema plans --item first \
    --from "/executor-prex -ar @plans/first/" --to "/runner-plan -ar @plans/first/" --json
  assert_failure
  [[ $stderr == *"duplicate queue items"* ]]
}

@test "cog queue-prompt-set supports rounds schema" {
  local rounds="${BATS_TEST_TMPDIR}/queue-rounds.yaml"
  cat >"$rounds" <<'EOF'
rounds:
  - item: round
    status: todo
    depends_on: []
    prompt: /executor-prex -ar old.md
    notes: note
EOF

  run cog queue-prompt-set --queue "$rounds" --schema rounds --item round \
    --from "/executor-prex -ar old.md" --to "/executor-prex -ar new.md" --json

  assert_success
  yq e -r '.rounds[] | select(.item == "round") | .prompt' "$rounds" | grep -Fx "/executor-prex -ar new.md" >/dev/null
}

@test "cog queue-prompt-set --help dispatches" {
  run cog queue-prompt-set --help

  assert_success
  [[ $output == *"Set one queue item prompt"* ]]
}
