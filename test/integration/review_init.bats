setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
}

@test "cog review-init emits paths and writes paths.env" {
  run cog review-init review

  assert_success
  assert_line --regexp '^REVIEW_RUN_DIR='
  assert_line --regexp '^REVIEW_SCOPE_JSON='
  assert_line --regexp '^REVIEW_TECH_SCOPE_JSON='
  refute_line --regexp '^CLASSIFICATION_JSON='
  refute_line --regexp '^CLI_JSON='
  refute_line --regexp '^REFS_JSON='
  local run_dir
  run_dir="$(printf '%s\n' "$output" | sed -n 's/^REVIEW_RUN_DIR=//p')"
  [ -f "${run_dir}/paths.env" ]
  grep -q '^REVIEW_TECH_SCOPE_JSON=' "${run_dir}/paths.env"
  refute grep -q '^CLASSIFICATION_JSON=' "${run_dir}/paths.env"
  refute grep -q '^CLI_JSON=' "${run_dir}/paths.env"
  refute grep -q '^REFS_JSON=' "${run_dir}/paths.env"
}

@test "cog review-init emits JSON paths" {
  run cog review-init review --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .paths.scope and .paths.tech_scope and .paths.findings and .paths_env
    and (.paths.classification | not)
    and (.paths.cli_signals | not)
    and (.paths.refs | not)
  ' >/dev/null
}

@test "cog review-init rejects duplicate prefixes" {
  run --separate-stderr cog review-init one two

  assert_failure
  [[ $stderr == *"err.kind: TooManyArguments"* ]]
}

@test "cog review-init --help dispatches" {
  run cog review-init --help

  assert_success
  [[ $output == *"Create a review run"* ]]
}

@test "sourcing paths.env leaves the caller's own RUN_DIR alone" {
  local run_dir
  run_dir="$(cog review-init sourcing-check | sed -n 's/^REVIEW_RUN_DIR=//p')"

  # The defect this replaced: paths.env bound a bare RUN_DIR, so a skill that
  # sourced it silently lost its own run directory and every later artifact path
  # resolved against the review directory instead.
  RUN_DIR="/caller/owns/this"
  # shellcheck source=/dev/null
  . "${run_dir}/paths.env"

  [ "$RUN_DIR" = "/caller/owns/this" ]
  [ "$REVIEW_RUN_DIR" = "$run_dir" ]
  [ "$REVIEW_SCOPE_JSON" = "${run_dir}/scope.json" ]
}
