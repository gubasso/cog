setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export GIT_FAKE_LOG="${BATS_TEST_TMPDIR}/git-argv.log"
  export GIT_STAGE_FINAL="${GIT_STAGE_FINAL:-session.txt}"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<'EOF'
#!/usr/bin/env bash
git_root="/tmp/repo"
if [ "$1" = "-C" ]; then
  git_root="$2"
  printf '%s\n' "$*" >>"${GIT_FAKE_LOG}"
  shift 2
else
  printf '%s\n' "$*" >>"${GIT_FAKE_LOG}"
fi
case "$*" in
  "rev-parse --show-toplevel")
    printf '%s\n' "$git_root"
    ;;
  "diff --staged --no-renames --name-only")
    count="$(grep -c 'diff --staged --no-renames --name-only$' "${GIT_FAKE_LOG}" 2>/dev/null || true)"
    if [ "$count" -eq 1 ]; then
      printf '%s\n' "old.txt"
    elif [ "$count" -eq 2 ]; then
      :
    else
      printf '%s\n' "${GIT_STAGE_FINAL}"
    fi
    ;;
  "diff --no-renames --name-only")
    printf '%s' "${GIT_STAGE_DIRTY:-}"
    ;;
  "ls-files --others --exclude-standard")
    printf '%s' "${GIT_STAGE_UNTRACKED:-}"
    ;;
  reset\ HEAD\ --*)
    ;;
  add\ --*)
    ;;
  *)
    printf 'unexpected git args: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
}

# Drop the fake git so a test can drive a real repository. The worktree-aware
# reconciliation is easier to state — and far stronger — against real git.
_use_real_git() {
  PATH="${PATH#"${BATS_TEST_TMPDIR}/fakebin:"}"
}

_new_repo() {
  local repo="${BATS_TEST_TMPDIR}/real-repo"
  mkdir -p "$repo"
  git init -q "$repo"
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name t
  printf '%s\n' "$repo"
}

@test "cog gc-stage reconciles staged files" {
  local session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' session.txt >"$session"

  run cog gc-stage --session-files "$session" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .unstaged == ["old.txt"] and .staged == ["session.txt"]' >/dev/null
  assert_file_contains "$GIT_FAKE_LOG" "reset HEAD -- old.txt"
  assert_file_contains "$GIT_FAKE_LOG" "add -- session.txt"
}

@test "cog gc-stage targets repo-root with git -C" {
  local session="${BATS_TEST_TMPDIR}/session.txt"
  local repo="${BATS_TEST_TMPDIR}/target-repo"
  mkdir -p "$repo"
  printf '%s\n' session.txt >"$session"

  run cog gc-stage --session-files "$session" --repo-root "$repo" --json

  assert_success
  assert_file_contains "$GIT_FAKE_LOG" ".*-C $repo diff --staged --no-renames --name-only"
  assert_file_contains "$GIT_FAKE_LOG" ".*-C $repo reset HEAD -- old.txt"
  assert_file_contains "$GIT_FAKE_LOG" ".*-C $repo add -- session.txt"
}

@test "cog gc-stage reports mismatch after emitting JSON" {
  export GIT_STAGE_FINAL="other.txt"
  local session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' session.txt >"$session"

  run cog gc-stage --session-files "$session" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.mismatch | length > 0)' >/dev/null
}

@test "cog gc-stage rejects absolute session paths" {
  local session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' /abs/path >"$session"

  run --separate-stderr cog gc-stage --session-files "$session" --json

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog --json gc-stage honors the global JSON flag" {
  local session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' session.txt >"$session"

  run cog --json gc-stage --session-files "$session"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .staged == ["session.txt"]' >/dev/null
}

@test "cog gc-stage matches a staged rename via raw delete+add paths" {
  # Regression: git rename detection collapses delete old + add new into one
  # destination line, which broke the literal path-set equality vs session_files
  # (observed on a queue-rounds.yaml rename round). --no-renames must keep both
  # the old and new path so the staged set equals the session-files set.
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-C" ] && shift 2
printf '%s\n' "$*" >>"${GIT_FAKE_LOG}"
case "$*" in
  "rev-parse --show-toplevel") printf '/tmp/repo\n' ;;
  "diff --staged --no-renames --name-only")
    printf '%s\n%s\n' "old.txt" "new.txt"
    ;;
  "diff --no-renames --name-only") ;;
  "ls-files --others --exclude-standard") ;;
  reset\ HEAD\ --*) ;;
  add\ --*) ;;
  *) printf 'unexpected git args: %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git"
  local session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n%s\n' old.txt new.txt >"$session"

  run cog gc-stage --session-files "$session" --json

  assert_success
  printf '%s\n' "$output" \
    | jq -e '.ok == true and (.mismatch | length == 0) and (.final_staged | sort == ["new.txt","old.txt"])' >/dev/null
}

@test "cog gc-stage re-stages a staged rename that gained later worktree edits" {
  # Regression: a rename staged before gc-stage runs already puts both raw paths
  # in the index, so the index-only check skipped `git add` and every edit made
  # to the renamed file after the rename was silently dropped from the commit.
  _use_real_git
  local repo session
  repo="$(_new_repo)"
  printf 'one\ntwo\nPIN=1\n' >"$repo/a.md"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  git -C "$repo" mv a.md b.md
  printf 'one\ntwo\n' >"$repo/b.md"
  session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n%s\n' a.md b.md >"$session"

  run cog gc-stage --session-files "$session" --repo-root "$repo" --json

  assert_success
  printf '%s\n' "$output" \
    | jq -e '.ok == true and .restaged == ["b.md"] and (.mismatch | length == 0)' >/dev/null
  run git -C "$repo" show :b.md
  refute_output --partial 'PIN=1'
}

@test "cog gc-stage expands a session directory into its dirty paths" {
  # Regression: git's index never lists a directory, so a bare directory in the
  # session list could never appear in the staged set and always reported a
  # false mismatch.
  _use_real_git
  local repo session
  repo="$(_new_repo)"
  printf 'seed\n' >"$repo/seed.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  mkdir -p "$repo/newdir" "$repo/cleandir"
  printf 'n\n' >"$repo/newdir/n.txt"
  printf 'm\n' >"$repo/newdir/m.txt"
  session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' newdir >"$session"

  run cog gc-stage --session-files "$session" --repo-root "$repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true and .requested == ["newdir"]
    and (.session_files | sort == ["newdir/m.txt", "newdir/n.txt"])
    and (.final_staged | sort == ["newdir/m.txt", "newdir/n.txt"])
    and (.mismatch | length == 0)' >/dev/null
}

@test "cog gc-stage keeps files staged under a declared session directory" {
  # The unstage sweep is equally directory-blind: without expansion it resets
  # files that legitimately live under a declared directory.
  _use_real_git
  local repo session
  repo="$(_new_repo)"
  mkdir -p "$repo/docs"
  printf 'seed\n' >"$repo/docs/seed.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  printf 'edited\n' >"$repo/docs/seed.txt"
  git -C "$repo" add docs/seed.txt
  session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' docs >"$session"

  run cog gc-stage --session-files "$session" --repo-root "$repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true and .unstaged == [] and .final_staged == ["docs/seed.txt"]' >/dev/null
}

@test "cog gc-stage fails closed when no session path has stageable content" {
  _use_real_git
  local repo session
  repo="$(_new_repo)"
  printf 'seed\n' >"$repo/seed.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm init
  mkdir -p "$repo/cleandir"
  session="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' cleandir >"$session"

  run cog gc-stage --session-files "$session" --repo-root "$repo" --json

  assert_failure
  printf '%s\n' "$output" \
    | jq -e '.ok == false and .session_files == [] and (.reason | test("stageable content"))' >/dev/null
}

@test "cog gc-stage --help dispatches" {
  run cog gc-stage --help

  assert_success
  [[ $output == *"Reconcile and stage"* ]]
}
