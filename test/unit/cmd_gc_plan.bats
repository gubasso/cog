setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export REPO_A="${BATS_TEST_TMPDIR}/repo-a"
  export REPO_B="${BATS_TEST_TMPDIR}/repo-b"
  export CLEAN_REPO="${BATS_TEST_TMPDIR}/clean-repo"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$REPO_A/src" "$REPO_B/lib" "$CLEAN_REPO" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-C" ]; then
  root="$2"
  shift 2
else
  root="${PWD}"
fi
case "$*" in
  "rev-parse --show-toplevel")
    case "$root" in
      "$REPO_A"|"$REPO_A"/*) printf '%s\n' "$REPO_A" ;;
      "$REPO_B"|"$REPO_B"/*) printf '%s\n' "$REPO_B" ;;
      "$CLEAN_REPO"|"$CLEAN_REPO"/*) printf '%s\n' "$CLEAN_REPO" ;;
      *) exit 1 ;;
    esac
    ;;
  "status --porcelain=v1 -uall")
    case "$root" in
      "$REPO_A") printf '%s\n' " M src/a.txt" " M src/extra.txt" ;;
      "$REPO_B") printf '%s\n' " M lib/b.txt" ;;
      "$CLEAN_REPO") : ;;
      *) exit 1 ;;
    esac
    ;;
  "status --porcelain=v1")
    case "$root" in
      "$CLEAN_REPO") : ;;
      *) printf '%s\n' " M dirty.txt" ;;
    esac
    ;;
  *)
    printf 'unexpected git args: root=%s args=%s\n' "$root" "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_git.sh"
  source "${LIB_DIR}/commands/cmd_gc_plan.sh"
}

write_session() {
  printf '%s\n' "$@" >"${BATS_TEST_TMPDIR}/session.txt"
}

@test "gc-plan freeform accepts multiple touched repos and reports extra dirty paths" {
  write_session "$REPO_A/src/a.txt" "$REPO_B/lib/b.txt"

  run cog::cmd::gc_plan --session-files "${BATS_TEST_TMPDIR}/session.txt" --json

  assert_success
  printf '%s\n' "$output" | jq -e --arg a "$REPO_A" --arg b "$REPO_B" '
    .ok == true and
    (.repos[] | select(.root == $a and .paths == ["src/a.txt"] and .extra_dirty == ["src/extra.txt"])) and
    (.repos[] | select(.root == $b and .paths == ["lib/b.txt"] and .extra_dirty == []))
  ' >/dev/null
}

@test "gc-plan allowlist reports undeclared repo as surprise" {
  write_session "$REPO_A/src/a.txt" "$REPO_B/lib/b.txt"

  run cog::cmd::gc_plan --session-files "${BATS_TEST_TMPDIR}/session.txt" --repo "$REPO_A" --json

  assert_success
  printf '%s\n' "$output" | jq -e --arg b "$REPO_B" '
    .ok == true and
    (.undeclared_dirty[] | select(.root == $b and .paths == ["lib/b.txt"])) and
    (.surprises | index("undeclared-repo:" + $b))
  ' >/dev/null
}

@test "gc-plan records escapes invalid repos declared no-change and repo-set entries" {
  write_session "$REPO_A/src/a.txt" "${BATS_TEST_TMPDIR}/outside.txt"
  printf '%s\n' "$CLEAN_REPO" "${BATS_TEST_TMPDIR}/not-a-repo" >"${BATS_TEST_TMPDIR}/repos.txt"

  run cog::cmd::gc_plan --session-files "${BATS_TEST_TMPDIR}/session.txt" --repo "$REPO_A" --repo-set "${BATS_TEST_TMPDIR}/repos.txt" --json

  assert_failure
  printf '%s\n' "$output" | jq -e --arg clean "$CLEAN_REPO" --arg invalid "${BATS_TEST_TMPDIR}/not-a-repo" '
    .ok == false and
    (.escapes | length == 1) and
    (.invalid_repos | index($invalid)) and
    (.declared_no_change | index($clean)) and
    any(.surprises[]; startswith("escape:"))
  ' >/dev/null
}
