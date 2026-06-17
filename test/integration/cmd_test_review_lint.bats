setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
}

@test "cog test-review-lint emits deterministic rule signals" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo/tests"
  cat >"$repo/tests/test_cli.py" <<'EOF'
import os, time
from unittest import mock

time.sleep(1)
os.environ["X"] = "1"
client.assert_called()
assert snapshot == "x"
tmp = "/tmp/shared"
assert requests.get("https://example.test")
mock.patch("project.helper")
EOF

  run cog test-review-lint --repo-root "$repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .files_scanned == 1 and
    ([.signals[].rule_id] | index("TR-SLEEP")) and
    ([.signals[].rule_id] | index("TR-GLOBAL-ENV")) and
    ([.signals[].rule_id] | index("TR-MOCK-ONLY")) and
    ([.signals[].rule_id] | index("TR-SNAPSHOT-BRITTLE")) and
    ([.signals[].rule_id] | index("TR-TEMP-SHARED")) and
    ([.signals[].rule_id] | index("TR-THIRD-PARTY-SUBJECT")) and
    ([.signals[].rule_id] | index("TR-MOCKING-OWN-PURE")) and
    ([.signals[].rule_id] | index("TR-HELP-MISSING")) and
    .summary.critical_hint >= 3 and .summary.high_hint >= 3 and .summary.info_hint >= 2
  ' >/dev/null
}

@test "cog test-review-lint excludes and includes e2e paths" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo/tests/e2e"
  printf '%s\n' 'sleep(1)' >"$repo/tests/e2e/test_browser.py"

  run cog test-review-lint --repo-root "$repo" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.files_scanned == 0 and (.signals | length) == 0' >/dev/null

  run cog test-review-lint --repo-root "$repo" --include-e2e --json
  assert_success
  printf '%s\n' "$output" | jq -e '.files_scanned == 1 and (.signals[] | select(.rule_id == "TR-SLEEP"))' >/dev/null
}

@test "cog test-review-lint rejects escaping scope" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"

  run --separate-stderr cog test-review-lint --repo-root "$repo" --scope ../outside --json

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
  [[ $stderr == *"--scope escapes repo root"* ]]
}
