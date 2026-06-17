link_required_tool() {
  local tool="$1" target
  target="$(command -v "$tool")"
  ln -sf "$target" "${BATS_TEST_TMPDIR}/fakebin/$tool"
}

use_fakebin_only() {
  local tool
  for tool in bash jq realpath readlink dirname pwd date mkdir; do
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
  export GIT_FAKE_LOG="${BATS_TEST_TMPDIR}/git-argv.log"
  export MAKE_FAKE_LOG="${BATS_TEST_TMPDIR}/make-argv.log"
  export GIT_FAKE_ROOT="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$GIT_FAKE_ROOT" "${BATS_TEST_TMPDIR}/fakebin"
  printf '%s\n' diff >"${BATS_TEST_TMPDIR}/patch.diff"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GIT_FAKE_LOG"
case "$*" in
  "rev-parse --show-toplevel") printf '%s\n' "$GIT_FAKE_ROOT" ;;
  apply\ --check\ --3way*)
    [[ ${GIT_FAKE_MODE:-direct} == threeway ]] && exit 0
    exit 1
    ;;
  apply\ --3way*) exit 0 ;;
  apply\ --check*)
    [[ ${GIT_FAKE_MODE:-direct} == direct ]] && exit 0
    exit 1
    ;;
  apply*) exit 0 ;;
  *) printf 'unexpected git args: %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  cat >"${BATS_TEST_TMPDIR}/fakebin/make" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MAKE_FAKE_LOG"
[[ ${MAKE_FAKE_FAIL:-0} == 1 && $# -eq 0 ]] && exit 3
exit 0
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git" "${BATS_TEST_TMPDIR}/fakebin/make"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
}

@test "cog suckless-apply applies directly and builds" {
  run cog suckless-apply --patch "${BATS_TEST_TMPDIR}/patch.diff" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .method == "git-apply" and .needs_conflict_resolution == false' >/dev/null
  assert_file_contains "$GIT_FAKE_LOG" "apply --check ${BATS_TEST_TMPDIR}/patch.diff"
  assert_file_contains "$MAKE_FAKE_LOG" "clean"
}

@test "cog suckless-apply uses three-way fallback" {
  # shellcheck disable=SC2030 # Each bats @test runs in its own subshell; exporting the fake mode here is intentional.
  export GIT_FAKE_MODE=threeway

  run cog suckless-apply --patch "${BATS_TEST_TMPDIR}/patch.diff" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .method == "git-apply-3way"' >/dev/null
  assert_file_contains "$GIT_FAKE_LOG" "apply --check --3way ${BATS_TEST_TMPDIR}/patch.diff"
}

@test "cog suckless-apply reports conflict and build failures" {
  # shellcheck disable=SC2031 # Each bats @test runs in its own subshell; exporting the fake mode here is intentional.
  export GIT_FAKE_MODE=conflict
  run --separate-stderr cog suckless-apply --patch "${BATS_TEST_TMPDIR}/patch.diff" --json
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .method == "none" and .needs_conflict_resolution == true' >/dev/null

  export GIT_FAKE_MODE=direct
  export MAKE_FAKE_FAIL=1
  run --separate-stderr cog suckless-apply --patch "${BATS_TEST_TMPDIR}/patch.diff" --json
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "build failed" and .build.exit_code == 3' >/dev/null
}

@test "cog suckless-apply fails closed when make is missing" {
  local tight_path
  rm -f "${BATS_TEST_TMPDIR}/fakebin/make"
  tight_path="$(use_fakebin_only)"

  run --separate-stderr env PATH="$tight_path" "${BATS_TEST_DIRNAME}/../../bin/cog" suckless-apply --patch "${BATS_TEST_TMPDIR}/patch.diff" --json

  assert_failure
  [[ $stderr == *"err.kind: MissingRequirement"* ]]
  [[ $stderr == *"command: make"* ]]
}
