setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export GIT_FAKE_LOG="${BATS_TEST_TMPDIR}/git-argv.log"
  export GIT_FAKE_ROOT="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$GIT_FAKE_ROOT" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GIT_FAKE_LOG"
case "$*" in
  "rev-parse --show-toplevel")
    if [[ ${GIT_FAKE_NO_WORKTREE:-0} == 1 ]]; then
      exit 128
    fi
    printf '%s\n' "$GIT_FAKE_ROOT"
    ;;
  "branch --show-current") printf '%s\n' main ;;
  "status --porcelain=v1 -uall")
    if [[ ${GIT_FAKE_DIRTY:-0} == 1 ]]; then printf '%s\n' " M config.h"; fi
    ;;
  *) printf 'unexpected git args: %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
}

@test "cog suckless-preflight passes for clean suckless tree" {
  touch "$GIT_FAKE_ROOT/config.mk" "$GIT_FAKE_ROOT/Makefile" "$GIT_FAKE_ROOT/config.def.h" "$GIT_FAKE_ROOT/config.h" "$GIT_FAKE_ROOT/dwm.c"

  run bash -c 'cd "$1" && cog suckless-preflight --json' _ "$GIT_FAKE_ROOT"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .detected_project == "dwm" and .clean_tree == true' >/dev/null
  assert_file_contains "$GIT_FAKE_LOG" "status --porcelain=v1 -uall"
}

@test "cog suckless-preflight fails on dirty tree" {
  touch "$GIT_FAKE_ROOT/config.mk" "$GIT_FAKE_ROOT/Makefile" "$GIT_FAKE_ROOT/dwm.c"
  export GIT_FAKE_DIRTY=1

  # shellcheck disable=SC2016 # The single-quoted body is a deferred bash -c script; positional args expand inside it, not here.
  run --separate-stderr bash -c 'cd "$1" && cog suckless-preflight --json' _ "$GIT_FAKE_ROOT"

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "dirty git tree"' >/dev/null
}

@test "cog suckless-preflight fails on non-suckless tree" {
  touch "$GIT_FAKE_ROOT/README"

  # shellcheck disable=SC2016 # The single-quoted body is a deferred bash -c script; positional args expand inside it, not here.
  run --separate-stderr bash -c 'cd "$1" && cog suckless-preflight --json' _ "$GIT_FAKE_ROOT"

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "not a suckless source tree"' >/dev/null
}

@test "cog suckless-preflight reports not a git work tree" {
  export GIT_FAKE_NO_WORKTREE=1

  # shellcheck disable=SC2016 # The single-quoted body is a deferred bash -c script; positional args expand inside it, not here.
  run --separate-stderr bash -c 'cd "$1" && cog suckless-preflight --json' _ "$GIT_FAKE_ROOT"

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .repo_root == null and .reason == "not a git work tree"' >/dev/null
}
