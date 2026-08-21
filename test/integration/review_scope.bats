setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export GIT_FAKE_LOG="${BATS_TEST_TMPDIR}/git-argv.log"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GIT_FAKE_LOG}"
case "$*" in
  "rev-parse --show-toplevel")
    [ "${GIT_ROOT_FAIL:-0}" = 1 ] && exit 1
    printf '%s\n' "/tmp/repo"
    ;;
  "branch --show-current")
    printf '%s\n' "main"
    ;;
  "diff --staged --name-only")
    [ "${GIT_TREE_CLEAN:-0}" = 1 ] || printf '%s\n' "staged.txt"
    ;;
  "diff --name-only")
    [ "${GIT_TREE_CLEAN:-0}" = 1 ] || printf '%s\n' "unstaged.txt"
    ;;
  "status --porcelain=v1 -uall")
    [ "${GIT_TREE_CLEAN:-0}" = 1 ] || printf '%s\n' "M  staged.txt" " M unstaged.txt" "?? new.txt"
    ;;
  "diff --staged --numstat")
    [ "${GIT_TREE_CLEAN:-0}" = 1 ] || printf '1\t0\tstaged.txt\n'
    ;;
  "diff --numstat")
    [ "${GIT_TREE_CLEAN:-0}" = 1 ] || printf '2\t1\tunstaged.txt\n'
    ;;
  # A movable ref that actually resolves to a different string, so a test can
  # tell "resolved once and reused" apart from "re-resolved per collector".
  "rev-parse --verify --quiet topic^{commit}")
    printf '%s\n' "topichash"
    ;;
  "rev-parse --verify --quiet base^{commit}")
    printf '%s\n' "basehash"
    ;;
  # Peeling a --sha selector to a commit. GIT_RANGE_FAIL makes it fail the same
  # way the diff arms do, so an unresolvable selector still fails at the first
  # git command that touches it.
  "rev-parse --verify --quiet "*"^{commit}")
    [ "${GIT_RANGE_FAIL:-0}" = 1 ] && exit 128
    # Real git exits 1 with no output when --verify --quiet cannot peel the
    # object to a commit, which is exactly the blob case.
    [ "${GIT_PEEL_FAIL:-0}" = 1 ] && exit 1
    peel="$4"
    printf '%s\n' "${peel%%^*}"
    ;;
  # The commit-selector arms are suffixed globs and the worktree arms above are
  # exact strings, so a bare `diff --numstat` can never fall through to them.
  "diff --name-only "*)
    [ "${GIT_RANGE_FAIL:-0}" = 1 ] && exit 128
    [ "${GIT_RANGE_EMPTY:-0}" = 1 ] && exit 0
    printf '%s\n' "ranged.txt" "shared.txt"
    ;;
  "diff --numstat "*)
    [ "${GIT_RANGE_FAIL:-0}" = 1 ] && exit 128
    [ "${GIT_RANGE_EMPTY:-0}" = 1 ] && exit 0
    printf '3\t1\tranged.txt\n5\t0\tshared.txt\n'
    ;;
  "show --name-only --format= "*)
    [ "${GIT_RANGE_FAIL:-0}" = 1 ] && exit 128
    printf '\n%s\n' "shown.txt"
    ;;
  "show --numstat --format= "*)
    [ "${GIT_RANGE_FAIL:-0}" = 1 ] && exit 128
    printf '\n4\t2\tshown.txt\n'
    ;;
  "log -z --no-walk --format="*)
    [ "${GIT_RANGE_FAIL:-0}" = 1 ] && exit 128
    printf 'abc123def\x1fabc123d\x1fsubject line\x1fbody\x00'
    ;;
  "log -z --format="*)
    [ "${GIT_RANGE_FAIL:-0}" = 1 ] && exit 128
    [ "${GIT_RANGE_EMPTY:-0}" = 1 ] && exit 0
    printf 'abc123def\x1fabc123d\x1fsubject line\x1fbody\x00'
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

@test "cog review-scope emits changed file union" {
  run cog review-scope --json

  assert_success
  printf '%s\n' "$output" | jq -e '.changed_files == ["new.txt","staged.txt","unstaged.txt"]' >/dev/null
}

@test "cog review-scope surfaces git failures" {
  export GIT_ROOT_FAIL=1

  run --separate-stderr cog review-scope --json

  assert_failure
  [[ $stderr == *"err.kind:"* ]]
}

@test "cog review-scope writes fragments" {
  local out="${BATS_TEST_TMPDIR}/scope.json"

  run cog review-scope "$out"

  assert_success
  assert_output "RESOLVED $out"
  jq -e '.repo_root == "/tmp/repo"' "$out" >/dev/null
}

@test "cog review-scope --help dispatches" {
  run cog review-scope --help

  assert_success
  [[ $output == *"Detect changed-file"* ]]
}

@test "cog review-scope with no sources issues only the working-tree git commands" {
  run cog review-scope --json

  assert_success
  run cat "$GIT_FAKE_LOG"
  assert_output "rev-parse --show-toplevel
branch --show-current
diff --staged --name-only
diff --name-only
rev-parse --show-toplevel
branch --show-current
status --porcelain=v1 -uall
diff --staged --numstat
diff --numstat"
}

@test "cog review-scope unions a commit selector into the changed files" {
  run cog review-scope --sha abc123 --json

  assert_success
  printf '%s\n' "$output" | jq -e '.commit_files == ["shown.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '.changed_files == ["new.txt","shown.txt","staged.txt","unstaged.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '.diff_stats.commits == {mode: "range", files: [{path: "shown.txt", added: 4, deleted: 2}]}' >/dev/null
  printf '%s\n' "$output" | jq -e '.commits == [{sha: "abc123def", short: "abc123d", subject: "subject line"}]' >/dev/null
}

@test "cog review-scope unions a range selector into the changed files" {
  run cog review-scope --range aaa..bbb --json

  assert_success
  printf '%s\n' "$output" | jq -e '.commit_files == ["ranged.txt","shared.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '.changed_files == ["new.txt","ranged.txt","shared.txt","staged.txt","unstaged.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '[.diff_stats.commits.files[] | .added + .deleted] | add == 9' >/dev/null
}

@test "cog review-scope sums a path touched by more than one selector" {
  run cog review-scope --range aaa..bbb --range ccc..ddd --json

  assert_success
  printf '%s\n' "$output" | jq -e '.commit_files == ["ranged.txt","shared.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '.diff_stats.commits.files == [{path: "ranged.txt", added: 6, deleted: 2}, {path: "shared.txt", added: 10, deleted: 0}]' >/dev/null
}

@test "cog review-scope unions an explicit file list into the changed files" {
  local list="${BATS_TEST_TMPDIR}/files.txt"
  printf '%s\n' "lib/a.sh" "unstaged.txt" >"$list"

  run cog review-scope --files "$list" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.requested_files == ["lib/a.sh","unstaged.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '.changed_files == ["lib/a.sh","new.txt","staged.txt","unstaged.txt"]' >/dev/null
}

@test "cog review-scope drops the working tree under --no-worktree" {
  run cog review-scope --no-worktree --sha abc123 --json

  assert_success
  printf '%s\n' "$output" | jq -e '.staged_files == [] and .unstaged_files == [] and .status_files == []' >/dev/null
  printf '%s\n' "$output" | jq -e '.changed_files == .commit_files' >/dev/null
  printf '%s\n' "$output" | jq -e '.diff_stats.staged.files == [] and .diff_stats.unstaged.files == []' >/dev/null
}

@test "cog review-scope refuses a scope with no source" {
  run --separate-stderr cog review-scope --no-worktree --json

  assert_failure
  [[ $stderr == *"review-scope has no source"* ]]
}

@test "cog review-scope fails naming a commit selector that does not resolve" {
  export GIT_RANGE_FAIL=1

  run --separate-stderr cog review-scope --sha nope --json

  assert_failure
  [[ $stderr == *"could not resolve git commit selector"* ]]
  [[ $stderr == *"nope"* ]]
}

@test "cog review-scope rejects a source flag with no value" {
  run --separate-stderr cog review-scope --sha

  assert_failure
  [[ $stderr == *"missing review-scope source value"* ]]
}

@test "cog review-scope rejects an unreadable file list" {
  run --separate-stderr cog review-scope --files "${BATS_TEST_TMPDIR}/absent.txt" --json

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}

@test "cog review-scope records the sources it was given" {
  local list="${BATS_TEST_TMPDIR}/files.txt"
  printf '%s\n' "lib/a.sh" >"$list"

  run cog review-scope --range aaa..bbb --sha abc123 --files "$list" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.sources.worktree == true' >/dev/null
  printf '%s\n' "$output" | jq -e '.sources.ranges == ["aaa..bbb"] and .sources.shas == ["abc123"]' >/dev/null
  printf '%s\n' "$output" | jq --arg l "$list" -e '.sources.files_from == $l' >/dev/null
}

@test "cog review-scope still rejects an unknown option" {
  run --separate-stderr cog review-scope --nope --json

  assert_failure
  [[ $stderr == *"unknown review-scope option"* ]]
}

@test "cog review-scope refuses a commit selector that resolves to no files" {
  # An empty resolution reaches the same place the no-source refusal guards: a
  # successful, empty scope that every consumer reads as a clean review.
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export GIT_RANGE_EMPTY=1

  run --separate-stderr cog review-scope --no-worktree --range HEAD..HEAD --json

  assert_failure
  [[ $stderr == *"resolved to an empty scope"* ]]
}

@test "cog review-scope still emits an empty scope for a clean working tree" {
  # The empty-scope refusal must not fire for the working tree, where nothing
  # to review is a legitimate answer the skills act on themselves.
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export GIT_TREE_CLEAN=1

  run cog review-scope --json

  assert_success
  printf '%s\n' "$output" | jq -e '.changed_files == []' >/dev/null
}

@test "cog review-scope walks each range separately when reporting commits" {
  # Two ranges are two revision walks unioned, not one combined walk: a single
  # `git log aaa..bbb ccc..ddd` excludes a commit that one range does include,
  # and commit_files would then name files no reported commit accounts for.
  run cog review-scope --range aaa..bbb --range ccc..ddd --json

  assert_success
  run grep -c '^log -z --format=' "$GIT_FAKE_LOG"
  assert_output "2"
}

@test "cog review-scope rejects a selector that names a non-commit object" {
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export GIT_PEEL_FAIL=1

  run --separate-stderr cog review-scope --sha "HEAD:AGENTS.md" --json

  assert_failure
  [[ $stderr == *"could not resolve git commit selector"* ]]
  [[ $stderr == *"does not name a commit"* ]]
}

@test "cog review-scope refuses an empty commit selector even with the working tree on" {
  # The exemption is for a working-tree-only run. Once a commit is named, an
  # empty union means the thing the caller asked to review was not found, and a
  # clean tree does not make that any less of a false clean.
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export GIT_TREE_CLEAN=1
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export GIT_RANGE_EMPTY=1

  run --separate-stderr cog review-scope --range HEAD..HEAD --json

  assert_failure
  [[ $stderr == *"resolved to an empty scope"* ]]
}

@test "cog review-scope resolves each sha once and reuses the resolved hash" {
  # A movable ref must not be re-resolved per collector: commit_files,
  # diff_stats.commits, and commits[] would otherwise be able to describe
  # different commits within one scope artifact.
  run cog review-scope --no-worktree --sha topic --json

  assert_success
  # The movable name is resolved exactly once...
  run grep -c '^rev-parse --verify --quiet topic\^{commit}$' "$GIT_FAKE_LOG"
  assert_output "1"
  # ...and every collector afterwards is handed the hash it resolved to.
  run grep -c '^show --name-only --format= topichash --$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^show --numstat --format= topichash --$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^log -z --no-walk --format=.* topichash$' "$GIT_FAKE_LOG"
  assert_output "1"
  # The original selector is still what `sources` reports back to the caller.
  run cog review-scope --no-worktree --sha topic --json
  printf '%s\n' "$output" | jq -e '.sources.shas == ["topic"]' >/dev/null
}

@test "cog review-scope resolves each range endpoint once and reuses the hashes" {
  # The range analogue of resolve-once: `A..B` names whatever A and B point at
  # when git is called, and the three collectors are three separate calls.
  run cog review-scope --no-worktree --range base..topic --json

  assert_success
  run grep -c '^rev-parse --verify --quiet base\^{commit}$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^rev-parse --verify --quiet topic\^{commit}$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^diff --name-only basehash..topichash --$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^diff --numstat basehash..topichash --$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^log -z --format=.* basehash..topichash$' "$GIT_FAKE_LOG"
  assert_output "1"
}

@test "cog review-scope preserves the three-dot form when resolving a range" {
  # `A...B` is merge-base semantics; rewriting it to `A..B` would silently
  # change which commits the review covers.
  run cog review-scope --no-worktree --range base...topic --json

  assert_success
  run grep -c '^diff --name-only basehash\.\.\.topichash --$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^diff --numstat basehash\.\.\.topichash --$' "$GIT_FAKE_LOG"
  assert_output "1"
}

@test "cog review-scope walks a three-dot range as a two-dot history" {
  # `git diff A...B` shows B's side only, while `git log A...B` is the symmetric
  # difference and would put A's unique commits into commits[] — commits whose
  # files commit_files never counted.
  run cog review-scope --no-worktree --range base...topic --json

  assert_success
  run grep -c '^log -z --format=.* basehash\.\.topichash$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^log -z --format=.* basehash\.\.\.topichash$' "$GIT_FAKE_LOG"
  assert_output "0"
}

@test "cog review-scope reports the original range the caller passed" {
  run cog review-scope --no-worktree --range base..topic --json

  assert_success
  printf '%s\n' "$output" | jq -e '.sources.ranges == ["base..topic"]' >/dev/null
}

@test "cog review-scope rejects a --range with no separator" {
  # `git diff HEAD` compares against the working tree, so a bare commit would
  # pull the live tree back into a scope that just declared it out.
  run --separate-stderr cog review-scope --no-worktree --range HEAD --json

  assert_failure
  [[ $stderr == *"needs a .. or ... separator"* ]]
}

@test "cog review-scope rejects a --range with more than one separator" {
  run --separate-stderr cog review-scope --no-worktree --range "aaa..bbb..ccc" --json

  assert_failure
  [[ $stderr == *"more than one separator"* ]]
}

@test "cog review-scope check rejects a separator-free range the same way" {
  # The guard and the review must never come to measure different changesets,
  # so `check` routes through the same builder and refuses the same values.
  run --separate-stderr cog review-scope check --max-files 100 --no-worktree --range HEAD --json

  assert_failure
  [[ $stderr == *"needs a .. or ... separator"* ]]
}
