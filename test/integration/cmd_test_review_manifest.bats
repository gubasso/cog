link_required_tool() {
  local tool="$1" target
  target="$(command -v "$tool")"
  ln -sf "$target" "${BATS_TEST_TMPDIR}/fakebin/$tool"
}

use_fakebin_only() {
  local tool
  for tool in bash jq mktemp cp mv dirname readlink pwd head date mkdir; do
    link_required_tool "$tool"
  done
  printf '%s\n' "${BATS_TEST_TMPDIR}/fakebin"
}

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export YQ_FAKE_LOG="${BATS_TEST_TMPDIR}/yq-argv.log"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
}

make_yq_stub() {
  cat >"${BATS_TEST_TMPDIR}/fakebin/yq" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$YQ_FAKE_LOG"
if [[ $* == "e -o=json .phase // null "* ]]; then
  printf '%s\n' '"4-in-progress"'
  exit 0
fi
if [[ $1 == e && $# -ge 3 ]]; then
  cat "${@: -1}"
  exit 0
fi
exit 0
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/yq"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
}

@test "cog test-review-manifest records yq expressions and emits update summary" {
  make_yq_stub
  local manifest="${BATS_TEST_TMPDIR}/MANIFEST.yaml"
  local update="${BATS_TEST_TMPDIR}/update.json"
  printf '%s\n' 'phase: 3' >"$manifest"
  cat >"$update" <<'EOF'
{
  "phase": "4-in-progress",
  "implementation_log_entry": {"status": "done"},
  "tooling_delta": {"tests": 1},
  "final_summary": {"ok": true}
}
EOF

  run cog test-review-manifest --manifest "$manifest" --update "$update" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .phase == "4-in-progress" and .appended_log == true and .tooling_delta_updated == true and .final_summary_updated == true' >/dev/null
  assert_file_contains "$YQ_FAKE_LOG" ".phase = strenv(PHASE)"
  assert_file_contains "$YQ_FAKE_LOG" "implementation-log"
  assert_file_contains "$YQ_FAKE_LOG" "final-summary"
}

@test "cog test-review-manifest fails closed when yq is missing" {
  local manifest="${BATS_TEST_TMPDIR}/MANIFEST.yaml"
  local update="${BATS_TEST_TMPDIR}/update.json"
  local tight_path
  printf '%s\n' 'phase: 3' >"$manifest"
  printf '%s\n' '{}' >"$update"
  # yq is deliberately NOT linked into fakebin, so it resolves nowhere on PATH.
  tight_path="$(use_fakebin_only)"

  run --separate-stderr env PATH="$tight_path" "${BATS_TEST_DIRNAME}/../../bin/cog" test-review-manifest --manifest "$manifest" --update "$update" --json

  assert_failure
  [[ $stderr == *"err.kind: MissingRequirement"* ]]
  [[ $stderr == *"command: yq"* ]]
}
