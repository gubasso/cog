setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_parse_globals.sh"
}

@test "verbosity maps to log levels" {
  local -A ctx
  local -a argv

  cog::fn::parse_globals ctx argv -v noop
  [ "${ctx[log_level]}" = "info" ]

  cog::fn::parse_globals ctx argv -vv noop
  [ "${ctx[log_level]}" = "debug" ]

  cog::fn::parse_globals ctx argv -vvv noop
  [ "${ctx[log_level]}" = "trace" ]
}

@test "repeated verbosity flags accumulate" {
  local -A ctx
  local -a argv

  cog::fn::parse_globals ctx argv -v -v noop

  [ "${ctx[verbosity]}" = "2" ]
  [ "${ctx[log_level]}" = "debug" ]
}

@test "standard global flags set context" {
  local -A ctx
  local -a argv

  cog::fn::parse_globals ctx argv --json --dry-run --print-config --help --version noop

  [ "${ctx[json]}" = "true" ]
  [ "${ctx[dry_run]}" = "true" ]
  [ "${ctx[print_config]}" = "true" ]
  [ "${ctx[help]}" = "true" ]
  [ "${ctx[version]}" = "true" ]
  [ "${ctx[cli_set_json]}" = "true" ]
  [ "${ctx[cli_set_dry_run]}" = "true" ]
}

@test "parser stops at subcommand and preserves trailing args" {
  local -A ctx
  local -a argv

  cog::fn::parse_globals ctx argv --json noop --flag value positional

  [ "${ctx[subcommand]}" = "noop" ]
  [ "${#argv[@]}" -eq 3 ]
  [ "${argv[0]}" = "--flag" ]
  [ "${argv[1]}" = "value" ]
  [ "${argv[2]}" = "positional" ]
}

@test "double dash ends global option parsing" {
  local -A ctx
  local -a argv

  cog::fn::parse_globals ctx argv -- --literal --flag

  [ "${ctx[subcommand]}" = "--literal" ]
  [ "${#argv[@]}" -eq 1 ]
  [ "${argv[0]}" = "--flag" ]
}

@test "unknown global flag fails with usage" {
  # shellcheck disable=SC2016 # The single-quoted body is a deferred bash -c script; positional args expand inside it, not here.
  run --separate-stderr bash -c '
    source "$1"
    source "$2"
    declare -A ctx
    declare -a argv
    cog::fn::parse_globals ctx argv --wat noop
  ' _ "${LIB_DIR}/helpers.sh" "${LIB_DIR}/functions/fn_parse_globals.sh"

  assert_failure 64
  [[ $stderr == *"err.kind: UnknownGlobalFlag"* ]]
}
