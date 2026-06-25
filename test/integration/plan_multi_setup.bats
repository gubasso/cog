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

@test "cog plan-multi-setup creates default run state" {
  run cog plan-multi-setup --json "build a foo"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .solo == false and
    .repo_root == "/tmp/fake-repo" and
    .output == (.run_dir + "/final-plan.md") and
    .research_root == "" and
    .brief_file == (.run_dir + "/plan-brief.md") and
    .claude_plan == (.run_dir + "/claude-plan.md") and
    .codex_plan == (.run_dir + "/codex-plan.md")
  ' >/dev/null
  assert_file_contains "$(printf '%s\n' "$output" | jq -r '.orientation_file')" "build a foo"
}

@test "cog plan-multi-setup accepts solo output and research root" {
  run cog plan-multi-setup --json "--solo --output /abs/p.md --research-root /abs/r build a foo"

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.solo == true and .output == "/abs/p.md" and .research_root == "/abs/r"' >/dev/null
}

@test "cog plan-multi-setup rejects empty input and unknown flags" {
  run --separate-stderr cog plan-multi-setup --json ""
  assert_failure 2
  [[ $stderr == *"err.kind: MissingArgument"* ]]

  run --separate-stderr cog plan-multi-setup --json "--bogus thing"
  assert_failure 2
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog plan-multi-setup rejects relative output without exit 2 assertion" {
  run --separate-stderr cog plan-multi-setup --json "--output relative.md build a foo"

  assert_failure
  [[ $status -ne 2 ]]
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog plan-multi-setup --help dispatches" {
  run cog plan-multi-setup --help

  assert_success
  [[ $output == *"Parse plan-multi"* ]]
}
