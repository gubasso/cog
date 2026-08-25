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
  "diff --staged --numstat --no-renames")
    [ "${GIT_TREE_CLEAN:-0}" = 1 ] || printf '1\t0\tstaged.txt\n'
    ;;
  "diff --numstat --no-renames")
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
  # exact strings, so a bare `diff --numstat --no-renames` can never fall
  # through to them. There is one arm per selector kind, not two: the file list
  # and the line stats are read from this single numstat record set, so a shim
  # that could disagree with itself no longer exists.
  "diff --numstat --no-renames --first-parent "*)
    [ "${GIT_RANGE_FAIL:-0}" = 1 ] && exit 128
    [ "${GIT_RANGE_EMPTY:-0}" = 1 ] && exit 0
    printf '3\t1\tranged.txt\n5\t0\tshared.txt\n'
    ;;
  # A merge: the record set names a file, which under the old two-invocation
  # split was reported by --numstat and missed entirely by --name-only.
  "show --numstat --no-renames --first-parent --format= mergehash --")
    printf '\n1\t0\tmerged.txt\n'
    ;;
  # A rename under --no-renames: two real paths, never "old.txt => new.txt".
  "show --numstat --no-renames --first-parent --format= renamehash --")
    printf '\n4\t0\tnew.txt\n0\t3\told.txt\n'
    ;;
  "show --numstat --no-renames --first-parent --format= "*)
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

# Write a scope declaration and echo its path. What to review is one JSON
# object, so a test states it the same way a skill does.
decl() {
  local path="${BATS_TEST_TMPDIR}/declaration-${BATS_SUITE_TEST_NUMBER}.json"
  printf '%s' "$1" >"$path"
  printf '%s' "$path"
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
diff --staged --numstat --no-renames
diff --numstat --no-renames"
}

@test "cog review-scope unions a commit selector into the changed files" {
  run cog review-scope --declaration "$(decl '{"shas":["abc123"]}')" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.commit_files == ["shown.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '.changed_files == ["new.txt","shown.txt","staged.txt","unstaged.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '.diff_stats.commits == {mode: "range", files: [{path: "shown.txt", added: 4, deleted: 2}]}' >/dev/null
  printf '%s\n' "$output" | jq -e '.commits == [{sha: "abc123def", short: "abc123d", subject: "subject line"}]' >/dev/null
}

@test "cog review-scope unions a range selector into the changed files" {
  run cog review-scope --declaration "$(decl '{"ranges":["aaa..bbb"]}')" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.commit_files == ["ranged.txt","shared.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '.changed_files == ["new.txt","ranged.txt","shared.txt","staged.txt","unstaged.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '[.diff_stats.commits.files[] | .added + .deleted] | add == 9' >/dev/null
}

@test "cog review-scope sums a path touched by more than one selector" {
  run cog review-scope --declaration "$(decl '{"ranges":["aaa..bbb","ccc..ddd"]}')" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.commit_files == ["ranged.txt","shared.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '.diff_stats.commits.files == [{path: "ranged.txt", added: 6, deleted: 2}, {path: "shared.txt", added: 10, deleted: 0}]' >/dev/null
}

@test "cog review-scope unions an explicit file list into the changed files" {
  local list="${BATS_TEST_TMPDIR}/files.txt"
  printf '%s\n' "lib/a.sh" "unstaged.txt" >"$list"

  run cog review-scope --declaration "$(decl '{"files":["lib/a.sh","unstaged.txt"]}')" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.requested_files == ["lib/a.sh","unstaged.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '.changed_files == ["lib/a.sh","new.txt","staged.txt","unstaged.txt"]' >/dev/null
}

@test "cog review-scope drops the working tree under --no-worktree" {
  run cog review-scope --declaration "$(decl '{"worktree":false,"shas":["abc123"]}')" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.staged_files == [] and .unstaged_files == [] and .status_files == []' >/dev/null
  printf '%s\n' "$output" | jq -e '.changed_files == .commit_files' >/dev/null
  printf '%s\n' "$output" | jq -e '.diff_stats.staged.files == [] and .diff_stats.unstaged.files == []' >/dev/null
}

@test "cog review-scope refuses a declaration that names no source" {
  run --separate-stderr cog review-scope --declaration "$(decl '{"worktree":false}')" --json

  assert_failure
  [[ $stderr == *"scope declaration failed schema validation"* ]]
}

@test "cog review-scope fails naming a commit selector that does not resolve" {
  export GIT_RANGE_FAIL=1

  run --separate-stderr cog review-scope --declaration "$(decl '{"shas":["nope"]}')" --json

  assert_failure
  [[ $stderr == *"could not resolve git commit selector"* ]]
  [[ $stderr == *"nope"* ]]
}

@test "cog review-scope rejects --declaration with no value" {
  run --separate-stderr cog review-scope --declaration

  assert_failure
  [[ $stderr == *"missing scope declaration path"* ]]
}

@test "cog review-scope rejects a second --declaration" {
  run --separate-stderr cog review-scope \
    --declaration "$(decl '{"shas":["abc123"]}')" \
    --declaration "$(decl '{"shas":["abc123"]}')" --json

  assert_failure
  [[ $stderr == *"duplicate scope declaration"* ]]
}

@test "cog review-scope rejects a declaration with an unknown key" {
  run --separate-stderr cog review-scope --declaration "$(decl '{"nope":true}')" --json

  assert_failure
  [[ $stderr == *"scope declaration failed schema validation"* ]]
}

@test "cog review-scope rejects a declaration naming an absolute path" {
  run --separate-stderr cog review-scope --declaration "$(decl '{"files":["/etc/passwd"]}')" --json

  assert_failure
  [[ $stderr == *"scope declaration failed schema validation"* ]]
}

@test "cog review-scope rejects a declaration that is not JSON" {
  run --separate-stderr cog review-scope --declaration "$(decl 'not json')" --json

  assert_failure
  [[ $stderr == *"scope declaration is not valid JSON"* ]]
}

@test "cog review-scope rejects a missing declaration file" {
  run --separate-stderr cog review-scope --declaration "${BATS_TEST_TMPDIR}/absent.json" --json

  assert_failure
  [[ $stderr == *"err.kind: InputNotFound"* ]]
}

@test "cog review-scope echoes the normalized declaration it resolved" {
  run cog review-scope --declaration "$(decl '{"ranges":["aaa..bbb"],"shas":["abc123"],"files":["lib/a.sh"]}')" --json

  assert_success
  # Every optional field is filled in, so what comes back can be fed straight
  # back in as a declaration.
  printf '%s\n' "$output" | jq -e '.declaration == {worktree: true, ranges: ["aaa..bbb"], shas: ["abc123"], files: ["lib/a.sh"]}' >/dev/null
}

@test "cog review-scope round-trips its own declaration" {
  run cog review-scope --declaration "$(decl '{"worktree":false,"shas":["abc123"]}')" --json
  assert_success
  local first="$output"

  printf '%s' "$first" | jq -c '.declaration' >"${BATS_TEST_TMPDIR}/round-trip.json"
  run cog review-scope --declaration "${BATS_TEST_TMPDIR}/round-trip.json" --json

  assert_success
  # worktree:false in particular: jq's `//` treats false as absent, so a
  # round trip is what catches the declared value being quietly replaced.
  printf '%s\n' "$output" | jq -e '.declaration.worktree == false' >/dev/null
  printf '%s\n' "$output" | jq --argjson first "$(printf '%s' "$first" | jq -c '.declaration')" -e '.declaration == $first' >/dev/null
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

  run --separate-stderr cog review-scope --declaration "$(decl '{"worktree":false,"ranges":["HEAD..HEAD"]}')" --json

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
  run cog review-scope --declaration "$(decl '{"ranges":["aaa..bbb","ccc..ddd"]}')" --json

  assert_success
  run grep -c '^log -z --format=' "$GIT_FAKE_LOG"
  assert_output "2"
}

@test "cog review-scope rejects a selector that names a non-commit object" {
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export GIT_PEEL_FAIL=1

  run --separate-stderr cog review-scope --declaration "$(decl '{"shas":["HEAD:AGENTS.md"]}')" --json

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

  run --separate-stderr cog review-scope --declaration "$(decl '{"ranges":["HEAD..HEAD"]}')" --json

  assert_failure
  [[ $stderr == *"resolved to an empty scope"* ]]
}

@test "cog review-scope resolves each sha once and reuses the resolved hash" {
  # A movable ref must not be re-resolved per collector: commit_files,
  # diff_stats.commits, and commits[] would otherwise be able to describe
  # different commits within one scope artifact.
  run cog review-scope --declaration "$(decl '{"worktree":false,"shas":["topic"]}')" --json

  assert_success
  # The movable name is resolved exactly once...
  run grep -c '^rev-parse --verify --quiet topic\^{commit}$' "$GIT_FAKE_LOG"
  assert_output "1"
  # ...and every collector afterwards is handed the hash it resolved to. The
  # numstat call appears once, not twice: the file list and the line stats are
  # two readings of one record set, not two questions asked of git.
  run grep -c '^show --numstat --no-renames --first-parent --format= topichash --$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^show --name-only' "$GIT_FAKE_LOG"
  assert_output "0"
  run grep -c '^log -z --no-walk --format=.* topichash$' "$GIT_FAKE_LOG"
  assert_output "1"
  # The original selector is still what the echoed declaration reports back.
  run cog review-scope --declaration "$(decl '{"worktree":false,"shas":["topic"]}')" --json
  printf '%s\n' "$output" | jq -e '.declaration.shas == ["topic"]' >/dev/null
}

@test "cog review-scope resolves each range endpoint once and reuses the hashes" {
  # The range analogue of resolve-once: `A..B` names whatever A and B point at
  # when git is called, and the collectors are separate calls.
  run cog review-scope --declaration "$(decl '{"worktree":false,"ranges":["base..topic"]}')" --json

  assert_success
  run grep -c '^rev-parse --verify --quiet base\^{commit}$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^rev-parse --verify --quiet topic\^{commit}$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^diff --numstat --no-renames --first-parent basehash..topichash --$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^diff --name-only' "$GIT_FAKE_LOG"
  assert_output "0"
  run grep -c '^log -z --format=.* basehash..topichash$' "$GIT_FAKE_LOG"
  assert_output "1"
}

@test "cog review-scope preserves the three-dot form when resolving a range" {
  # `A...B` is merge-base semantics; rewriting it to `A..B` would silently
  # change which commits the review covers.
  run cog review-scope --declaration "$(decl '{"worktree":false,"ranges":["base...topic"]}')" --json

  assert_success
  run grep -c '^diff --numstat --no-renames --first-parent basehash\.\.\.topichash --$' "$GIT_FAKE_LOG"
  assert_output "1"
}

@test "cog review-scope walks a three-dot range as a two-dot history" {
  # `git diff A...B` shows B's side only, while `git log A...B` is the symmetric
  # difference and would put A's unique commits into commits[] — commits whose
  # files commit_files never counted.
  run cog review-scope --declaration "$(decl '{"worktree":false,"ranges":["base...topic"]}')" --json

  assert_success
  run grep -c '^log -z --format=.* basehash\.\.topichash$' "$GIT_FAKE_LOG"
  assert_output "1"
  run grep -c '^log -z --format=.* basehash\.\.\.topichash$' "$GIT_FAKE_LOG"
  assert_output "0"
}

@test "cog review-scope reports the original range the caller passed" {
  run cog review-scope --declaration "$(decl '{"worktree":false,"ranges":["base..topic"]}')" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.declaration.ranges == ["base..topic"]' >/dev/null
}

@test "cog review-scope rejects a --range with no separator" {
  # `git diff HEAD` compares against the working tree, so a bare commit would
  # pull the live tree back into a scope that just declared it out.
  run --separate-stderr cog review-scope --declaration "$(decl '{"worktree":false,"ranges":["HEAD"]}')" --json

  assert_failure
  [[ $stderr == *"needs a .. or ... separator"* ]]
}

@test "cog review-scope rejects a --range with more than one separator" {
  run --separate-stderr cog review-scope --declaration "$(decl '{"worktree":false,"ranges":["aaa..bbb..ccc"]}')" --json

  assert_failure
  [[ $stderr == *"more than one separator"* ]]
}

@test "cog review-scope reports a merge in both the file list and the line stats" {
  run cog review-scope --declaration "$(decl '{"worktree":false,"shas":["mergehash"]}')" --json

  assert_success
  # The defect this replaced: commit_files was empty while diff_stats.commits
  # named a file, so the reviewer never opened a file the budget was charged for.
  printf '%s\n' "$output" | jq -e '.commit_files == ["merged.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '[.diff_stats.commits.files[].path] == ["merged.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '.changed_files == [.diff_stats.commits.files[].path] | not | not' >/dev/null
}

@test "cog review-scope reports real paths for a renamed file" {
  run cog review-scope --declaration "$(decl '{"worktree":false,"shas":["renamehash"]}')" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.commit_files == ["new.txt","old.txt"]' >/dev/null
  printf '%s\n' "$output" | jq -e '[.commit_files[], (.diff_stats.commits.files[].path)] | any(test(" => ")) | not' >/dev/null
}
