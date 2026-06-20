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

@test "cog plan-writer-multi-setup parses executor solo and orientation" {
  run cog plan-writer-multi-setup --json "--executor single-pass --solo Build the thing"

  assert_success
  printf '%s\n' "$output" | jq -e '.executor == "single-pass" and .ef == "1.0" and .solo == true and .repo_root == "/tmp/fake-repo"' >/dev/null
  assert_file_contains "$(printf '%s\n' "$output" | jq -r '.orientation_file')" "Build the thing"
}

@test "cog plan-writer-multi-setup maps effort factors and rejects bad executor" {
  run cog plan-writer-multi-setup --json "--executor=limited Work item"
  assert_success
  printf '%s\n' "$output" | jq -e '.ef == "0.8"' >/dev/null

  run --separate-stderr cog plan-writer-multi-setup --json "--executor bad Work item"
  assert_failure 2
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog plan-writer-multi-setup normalizes executor-prex to prex capacity profile" {
  run cog plan-writer-multi-setup --json "--executor executor-prex Work item"

  assert_success
  printf '%s\n' "$output" | jq -e '.executor == "prex" and .ef == "1.5"' >/dev/null
}

@test "cog plan-writer-multi-setup --help dispatches" {
  run cog plan-writer-multi-setup --help

  assert_success
  [[ $output == *"Parse plan-writer-multi"* ]]
}
