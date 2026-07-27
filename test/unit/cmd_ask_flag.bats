setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  # Resolve the ask-flags data table from the repo, not an installed copy.
  export XDG_DATA_HOME="${BATS_TEST_DIRNAME}/../../nonexistent-xdg"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_json_write.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_data.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ask_flag.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_ask_flag.sh"
}

@test "render web-search emits the canonical paragraph" {
  run --separate-stderr cog::cmd::ask_flag render --flag web-search

  assert_success
  assert_line --partial "LATEST OFFICIAL"
  [ -z "$stderr" ]
}

@test "render real-world emits the canonical paragraph" {
  run --separate-stderr cog::cmd::ask_flag render --flag real-world

  assert_success
  assert_line --partial "real-world reference implementations"
  [ -z "$stderr" ]
}

@test "render unknown flag is an input error" {
  run --separate-stderr cog::cmd::ask_flag render --flag bogus

  assert_failure "$EX_DATAERR"
  [ -z "$output" ]
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "render without --flag is a usage error" {
  run --separate-stderr cog::cmd::ask_flag render

  assert_failure "$EX_USAGE"
  [ -z "$output" ]
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}

@test "list shows both flag ids" {
  run --separate-stderr cog::cmd::ask_flag list

  assert_success
  assert_line --partial "web-search"
  assert_line --partial "real-world"
  [ -z "$stderr" ]
}

@test "list --json emits a validated array" {
  run --separate-stderr cog::cmd::ask_flag list --json

  assert_success
  [ "$(jq -r 'length' <<<"$output")" -eq 2 ]
  [ "$(jq -r 'map(.flag) | sort | join(",")' <<<"$output")" = "real-world,web-search" ]
  [ -z "$stderr" ]
}

@test "no verb prints usage" {
  run --separate-stderr cog::cmd::ask_flag

  assert_success
  assert_line --partial "Usage: cog ask-flag render"
  [ -z "$stderr" ]
}

@test "unknown verb is an input error" {
  run --separate-stderr cog::cmd::ask_flag frobnicate

  assert_failure "$EX_DATAERR"
  [ -z "$output" ]
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}
