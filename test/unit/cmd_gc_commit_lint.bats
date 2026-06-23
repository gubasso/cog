setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_skill_refs.sh"
  source "${LIB_DIR}/functions/fn_git.sh"
  source "${LIB_DIR}/commands/cmd_gc_commit_lint.sh"

  MSG="${BATS_TEST_TMPDIR}/message.txt"
  REPO="${BATS_TEST_TMPDIR}/repo"
  git init -q "$REPO"
}

mkmsg() {
  printf '%s\n' "$@" >"$MSG"
}

lint() {
  run cog::cmd::gc_commit_lint --message-file "$MSG" --repo-root "$REPO" --json
}

@test "accepts a scopeless conventional commit" {
  mkmsg "feat: add token refresh"
  lint
  assert_success
  jq -e '.ok == true and .deferred == false and (.violations | length) == 0' <<<"$output" >/dev/null
}

@test "accepts a hierarchical multi-level scope" {
  mkmsg "fix(core/db): handle null rows"
  lint
  assert_success
  jq -e '.ok == true and (.violations | length) == 0' <<<"$output" >/dev/null
}

@test "accepts a breaking-change marker" {
  mkmsg "feat(api)!: drop v1 endpoints"
  lint
  assert_success
  jq -e '.ok == true' <<<"$output" >/dev/null
}

@test "rejects an unknown type" {
  mkmsg "wip: poke at things"
  lint
  assert_failure
  jq -e '.ok == false and (.violations | map(.code) | index("unknown-type"))' <<<"$output" >/dev/null
}

@test "rejects a capitalized and punctuated description" {
  mkmsg "feat: Add a thing."
  lint
  assert_failure
  jq -e '(.violations | map(.code)) as $c | ($c | index("subject-capitalized")) and ($c | index("subject-punctuated"))' <<<"$output" >/dev/null
}

@test "rejects a subject with no separator" {
  mkmsg "add a thing without a type"
  lint
  assert_failure
  jq -e '.violations | map(.code) | index("missing-separator")' <<<"$output" >/dev/null
}

@test "rejects a malformed scope" {
  mkmsg "feat(a b): do the thing"
  lint
  assert_failure
  jq -e '.violations | map(.code) | index("bad-scope")' <<<"$output" >/dev/null
}

@test "rejects an over-length subject" {
  mkmsg "feat(core): aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll mmmm end"
  lint
  assert_failure
  jq -e '.violations | map(.code) | index("subject-too-long")' <<<"$output" >/dev/null
}

@test "rejects a missing blank line before the body" {
  mkmsg "feat: add a thing" "body starts immediately"
  lint
  assert_failure
  jq -e '.violations | map(.code) | index("no-blank-before-body")' <<<"$output" >/dev/null
}

@test "accepts a well-formed body after a blank line" {
  mkmsg "feat: add a thing" "" "Explain the thing in the body."
  lint
  assert_success
  jq -e '.ok == true' <<<"$output" >/dev/null
}

@test "defers to an installed commit-msg hook" {
  printf '#!/bin/sh\nexit 0\n' >"$REPO/.git/hooks/commit-msg"
  chmod +x "$REPO/.git/hooks/commit-msg"
  mkmsg "totally not conventional"
  lint
  assert_success
  jq -e '.ok == true and .deferred == true and .linter == "commit-msg-hook"' <<<"$output" >/dev/null
}

@test "defers to a pre-commit commit-message hook" {
  printf 'repos:\n  - repo: local\n    hooks:\n      - id: committed\n' >"$REPO/.pre-commit-config.yaml"
  mkmsg "totally not conventional"
  lint
  assert_success
  jq -e '.ok == true and .deferred == true and .linter == "pre-commit"' <<<"$output" >/dev/null
}

@test "uses the project's committed.toml allowed_types" {
  printf 'style = "conventional"\nallowed_types = ["wip"]\n' >"$REPO/committed.toml"
  mkmsg "wip: scratch work"
  lint
  assert_success
  jq -e '.ok == true' <<<"$output" >/dev/null

  mkmsg "feat: a normal type"
  lint
  assert_failure
  jq -e '.violations | map(.code) | index("unknown-type")' <<<"$output" >/dev/null
}
