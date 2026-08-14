setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_claude.sh"
  printf '%s\n' "do the thing" >"${BATS_TEST_TMPDIR}/prompt.md"
}

@test "claude exec argv builds a wrapper prefix and a child suffix" {
  local -a argv=()
  cog::fn::claude_exec_argv work default read-only medium opus "${BATS_TEST_TMPDIR}/prompt.md" argv
  [ "${argv[0]}" = "claude-session-rs" ]
  [ "${argv[1]}" = "--account" ]
  [ "${argv[2]}" = "work" ]
  [ "${argv[3]}" = "--profile" ]
  [ "${argv[4]}" = "default" ]
  # The wrapper owns no exec verb: everything after -- reaches claude verbatim.
  [ "${argv[5]}" = "--" ]
  [ "${argv[6]}" = "-p" ]
  # The prompt is the final positional, read from the file.
  [ "${argv[${#argv[@]} - 1]}" = "do the thing" ]
}

@test "claude exec argv omits an unset account and profile" {
  local -a argv=()
  cog::fn::claude_exec_argv "" "" read-only low "" "${BATS_TEST_TMPDIR}/prompt.md" argv
  [ "${argv[0]}" = "claude-session-rs" ]
  [ "${argv[1]}" = "--" ]
  printf '%s\n' "${argv[@]}" | grep -qv -- "--account"
}

@test "claude read-only denies the write tools rather than entering plan mode" {
  local -a argv=()
  cog::fn::claude_exec_argv "" "" read-only medium opus "${BATS_TEST_TMPDIR}/prompt.md" argv
  local joined="${argv[*]}"
  [[ $joined == *"--permission-mode dontAsk"* ]]
  [[ $joined == *"--disallowedTools Edit,Write,NotebookEdit"* ]]
  [[ $joined != *"plan"* ]]
  [[ $joined != *"--dangerously-skip-permissions"* ]]
}

@test "claude write posture skips permissions" {
  local -a argv=()
  cog::fn::claude_exec_argv "" "" write medium opus "${BATS_TEST_TMPDIR}/prompt.md" argv
  local joined="${argv[*]}"
  [[ $joined == *"--dangerously-skip-permissions"* ]]
  [[ $joined != *"--permission-mode"* ]]
}

@test "claude none effort is an omission rather than a value" {
  local -a argv=()
  cog::fn::claude_exec_argv "" "" read-only none opus "${BATS_TEST_TMPDIR}/prompt.md" argv
  # claude --effort none is rejected with a warning and silently defaults, so
  # the none rung must dispatch with no --effort flag at all.
  [[ ${argv[*]} != *"--effort"* ]]
}

@test "claude effort rejects the codex vocabulary" {
  local -a argv=()
  run cog::fn::claude_exec_argv "" "" read-only minimal opus "${BATS_TEST_TMPDIR}/prompt.md" argv
  assert_failure
  assert_output --partial "invalid claude effort"
}

@test "claude extracts the final result envelope into the output artifact" {
  local events="${BATS_TEST_TMPDIR}/events.jsonl"
  local out="${BATS_TEST_TMPDIR}/out.md"
  {
    printf '%s\n' '{"type":"system","session_id":"sess-1"}'
    printf '%s\n' '{"type":"assistant"}'
    printf '%s\n' '{"type":"result","session_id":"sess-1","result":"the answer"}'
  } >"$events"

  run cog::fn::claude_extract_result "$events" "$out"
  assert_success
  assert_file_contains "$out" "the answer"

  run cog::fn::claude_extract_session "$events"
  assert_success
  assert_output "sess-1"
}

@test "claude result extraction fails when no result envelope arrived" {
  local events="${BATS_TEST_TMPDIR}/events.jsonl"
  printf '%s\n' '{"type":"system","session_id":"sess-1"}' >"$events"
  run cog::fn::claude_extract_result "$events" "${BATS_TEST_TMPDIR}/out.md"
  assert_failure
  [ ! -e "${BATS_TEST_TMPDIR}/out.md" ]
}

@test "claude classifies from the exit code and artifact emptiness alone" {
  local out="${BATS_TEST_TMPDIR}/out.md"
  printf '%s\n' "content" >"$out"

  run cog::fn::claude_classify_status 0 "$out"
  assert_output "ok"

  run cog::fn::claude_classify_status 0 "${BATS_TEST_TMPDIR}/absent.md"
  assert_output "empty-output"

  run cog::fn::claude_classify_status 1 "$out"
  assert_output "nonzero"

  # 64 is both EX_USAGE and a legal agent exit. The preflight is what makes that
  # unambiguous, so the classifier never tries to disambiguate it here.
  run cog::fn::claude_classify_status 64 "$out"
  assert_output "nonzero"

  run cog::fn::claude_classify_status 124 "$out"
  assert_output "timeout-124"

  run cog::fn::claude_classify_status 143 "$out"
  assert_output "sigterm"
}

@test "claude reconstructs a status from durable artifacts when the exit code was lost" {
  local events="${BATS_TEST_TMPDIR}/events.jsonl"
  local out="${BATS_TEST_TMPDIR}/out.md"
  printf '%s\n' "content" >"$out"

  printf '%s\n' '{"type":"result","result":"x"}' >"$events"
  run cog::fn::claude_reconstruct_status "$events" "$out"
  assert_output "ok"

  printf '%s\n' '{"type":"error"}' >"$events"
  run cog::fn::claude_reconstruct_status "$events" "$out"
  assert_output "nonzero"

  printf '%s\n' '{"type":"assistant"}' >"$events"
  run cog::fn::claude_reconstruct_status "$events" "$out"
  assert_output "sigterm"

  run cog::fn::claude_reconstruct_status "$events" "${BATS_TEST_TMPDIR}/absent.md"
  assert_output "empty-output"
}
