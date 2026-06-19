setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_queue.sh"
}

entry_json() {
  jq -cn \
    --arg item "$1" \
    --arg status "${2:-todo}" \
    --arg prompt "/prex -ar plan.md" \
    --arg notes "note" \
    '{item: $item, status: $status, depends_on: [], prompt: $prompt, notes: $notes}'
}

@test "queue schema keys and statuses validate" {
  run cog::fn::queue_schema_key plans
  assert_success
  assert_output plans

  run cog::fn::queue_schema_key bad
  assert_failure

  run cog::fn::queue_status_valid doing
  assert_success

  run cog::fn::queue_status_valid bad
  assert_failure
}

@test "queue_bootstrap_file creates plans and rounds queues" {
  local plans="${BATS_TEST_TMPDIR}/plans/queue-plans.yaml"
  local rounds="${BATS_TEST_TMPDIR}/rounds/queue-rounds.yaml"

  cog::fn::queue_bootstrap_file "$plans" plans
  cog::fn::queue_bootstrap_file "$rounds" rounds

  run cat "$plans"
  assert_success
  assert_line "plans: []"
  run cat "$rounds"
  assert_success
  assert_line "rounds: []"
}

@test "queue_validate_file rejects missing bad yaml wrong shape invalid entries and duplicates" {
  run --separate-stderr cog::fn::queue_validate_file "${BATS_TEST_TMPDIR}/missing.yaml" plans
  assert_failure 66
  [[ $stderr == *"err.kind: InputNotFound"* ]]

  local bad_yaml="${BATS_TEST_TMPDIR}/bad.yaml"
  printf '%s\n' 'plans: [' >"$bad_yaml"
  run --separate-stderr cog::fn::queue_validate_file "$bad_yaml" plans
  assert_failure 65
  [[ $stderr == *"err.kind: InvalidInput"* ]]

  local wrong="${BATS_TEST_TMPDIR}/wrong.yaml"
  printf '%s\n' 'rounds: []' >"$wrong"
  run --separate-stderr cog::fn::queue_validate_file "$wrong" plans
  assert_failure 65

  local invalid="${BATS_TEST_TMPDIR}/invalid.yaml"
  cat >"$invalid" <<'EOF'
plans:
  - item: bad item
    status: nope
    depends_on: []
    prompt: ""
    notes: note
EOF
  run --separate-stderr cog::fn::queue_validate_file "$invalid" plans
  assert_failure 65

  local dupes="${BATS_TEST_TMPDIR}/dupes.yaml"
  cat >"$dupes" <<'EOF'
plans:
  - item: same
    status: todo
    depends_on: []
    prompt: /prex -ar one.md
    notes: note
  - item: same
    status: todo
    depends_on: []
    prompt: /prex -ar two.md
    notes: note
EOF
  run --separate-stderr cog::fn::queue_validate_file "$dupes" plans
  assert_failure 65
}

@test "queue_append_entry appends to empty helper-owned queue and rejects duplicates" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  local entry
  printf '%s\n' 'plans: []' >"$queue"
  entry="$(entry_json domain-libs-port todo)"

  run cog::fn::queue_append_entry "$queue" plans "$entry"

  assert_success
  run cog::fn::queue_count "$queue" plans
  assert_success
  assert_output "1"
  assert_file_contains "$queue" "  - item: domain-libs-port"

  run --separate-stderr cog::fn::queue_append_entry "$queue" plans "$entry"
  assert_failure 64
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "queue_append_entry rejects unsupported shape and invalid json" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  printf '%s\n' 'plans: []' 'extra: []' >"$queue"

  run --separate-stderr cog::fn::queue_append_entry "$queue" plans "$(entry_json one todo)"
  assert_failure 65

  printf '%s\n' 'plans: []' >"$queue"
  run --separate-stderr cog::fn::queue_append_entry "$queue" plans '{"item":""}'
  assert_failure 64
  [[ $stderr == *"err.kind: InvalidJsonInput"* ]]
}

@test "queue_select_next_round returns selected complete and blocked states" {
  local queue="${BATS_TEST_TMPDIR}/rounds.yaml"
  cat >"$queue" <<'EOF'
rounds:
  - item: first
    status: done
    depends_on: []
    prompt: /prex -ar first.md
    notes: note
  - item: second
    status: todo
    depends_on: [first]
    prompt: /prex -ar second.md
    notes: note
EOF
  run cog::fn::queue_select_next_round "$queue"
  assert_success
  printf '%s\n' "$output" | jq -e '.state == "selected" and .selected.item == "second"' >/dev/null

  cat >"$queue" <<'EOF'
rounds:
  - item: first
    status: done
    depends_on: []
    prompt: /prex -ar first.md
    notes: note
EOF
  run cog::fn::queue_select_next_round "$queue"
  assert_success
  printf '%s\n' "$output" | jq -e '.state == "complete"' >/dev/null

  cat >"$queue" <<'EOF'
rounds:
  - item: blocked
    status: todo
    depends_on: [missing]
    prompt: /prex -ar blocked.md
    notes: note
EOF
  run cog::fn::queue_select_next_round "$queue"
  assert_success
  printf '%s\n' "$output" | jq -e '.state == "blocked" and .blocked[0] == "blocked"' >/dev/null
}

@test "queue_validate_rounds_selectable rejects active doing round" {
  local queue="${BATS_TEST_TMPDIR}/rounds.yaml"
  cat >"$queue" <<'EOF'
rounds:
  - item: active
    status: doing
    depends_on: []
    prompt: /prex -ar active.md
    notes: note
EOF
  run --separate-stderr cog::fn::queue_validate_rounds_selectable "$queue"

  assert_failure 65
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "queue requires yq with unavailable exit code" {
  __have() {
    [[ $1 != yq ]] && command -v "$1" >/dev/null 2>&1
  }

  run --separate-stderr cog::fn::queue_bootstrap_file "${BATS_TEST_TMPDIR}/queue-plans.yaml" plans

  assert_failure 69
  [[ $stderr == *"err.kind: MissingRequirement"* ]]
}
