setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "rev-parse --show-toplevel") printf '%s\n' "/tmp/fake-repo" ;;
  *) printf 'unexpected git args: %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
}

@test "cog review-plan-multi-setup classifies inline input and writes raw file" {
  run cog review-plan-multi-setup --json "--solo review this plan: do X then Y"

  assert_success
  printf '%s\n' "$output" | jq -e '.mode == "inline" and .solo == true and .repo_root == "/tmp/fake-repo"' >/dev/null
  assert_file_contains "$(printf '%s\n' "$output" | jq -r '.raw_input_file')" "do X then Y"
}

@test "cog review-plan-multi-setup classifies a plan file" {
  local plan="${BATS_TEST_TMPDIR}/plan.md"
  printf '# Plan\n' >"$plan"

  run cog review-plan-multi-setup --json "$plan"

  assert_success
  printf '%s\n' "$output" | jq -e --arg p "$plan" '.mode == "file" and .plan_path == $p and .solo == false' >/dev/null
}

@test "cog review-plan-multi-setup enumerates plan-directory markdown sources in order" {
  local dir="${BATS_TEST_TMPDIR}/plandir"
  mkdir -p "$dir"
  printf '# r2\n' >"$dir/round-2.md"
  printf '# r1\n' >"$dir/round-1.md"
  printf 'rounds: []\n' >"$dir/queue-rounds.yaml"

  run cog review-plan-multi-setup --json "$dir"

  assert_success
  printf '%s\n' "$output" | jq -e '.mode == "dir"' >/dev/null
  local sources
  sources="$(printf '%s\n' "$output" | jq -r '.plan_sources')"
  assert_file_contains "$sources" "round-1.md"
  assert_file_contains "$sources" "round-2.md"
  run cat "$sources"
  [[ $output != *"queue-rounds.yaml"* ]]
  [[ $(sed -n '1p' "$sources") == *round-1.md ]]
}

@test "cog review-plan-multi-setup rejects empty input and unknown flags" {
  run --separate-stderr cog review-plan-multi-setup --json ""
  assert_failure 2
  [[ $stderr == *"err.kind: MissingArgument"* ]]

  run --separate-stderr cog review-plan-multi-setup --json "--bogus thing"
  assert_failure 2
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog review-plan-multi-setup --help dispatches" {
  run cog review-plan-multi-setup --help

  assert_success
  [[ $output == *"Parse review-plan-multi"* ]]
}
