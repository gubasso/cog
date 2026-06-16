# Config/source/line/ctx/argv arrays are populated by namerefs inside
# cog::fn::config_load and cog::fn::parse_globals, so shellcheck cannot see
# their use and reports false SC2034 "appears unused" for every test.
# shellcheck disable=SC2034

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/xdg-config"
  export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME/cog/conf.d" "$PROJECT_DIR/.cog"
  cd "$PROJECT_DIR" || return 1
  unset COG_JSON COG_DRY_RUN COG_LOG_LEVEL
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_parse_globals.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_config_load.sh"
}

@test "defaults load with default provenance" {
  local -A ctx config source line

  ctx=()
  cog::fn::config_load ctx config source line

  [ "${config[json]}" = "false" ]
  [ "${config[dry_run]}" = "false" ]
  [ "${config[log_level]}" = "warn" ]
  [ "${source[json]}" = "default" ]
}

@test "precedence is defaults user overlay project env cli" {
  local -A ctx config source line
  local -a argv

  printf '%s\n' 'json=false' 'dry_run=false' 'log_level=info' >"${XDG_CONFIG_HOME}/cog/config.sh"
  printf '%s\n' 'json=true' 'log_level=debug' >"${XDG_CONFIG_HOME}/cog/conf.d/10-overlay.sh"
  printf '%s\n' 'dry_run=true' 'log_level=trace' >"${PROJECT_DIR}/.cog/config.sh"
  # shellcheck disable=SC2030 # Each bats @test runs in its own subshell; exporting the env layer here is intentional.
  export COG_JSON=false
  cog::fn::parse_globals ctx argv --json -vv noop

  cog::fn::config_load ctx config source line

  [ "${config[json]}" = "true" ]
  [ "${source[json]}" = "cli:--json" ]
  [ "${config[dry_run]}" = "true" ]
  [ "${source[dry_run]}" = "project:${PROJECT_DIR}/.cog/config.sh" ]
  [ "${config[log_level]}" = "debug" ]
  [ "${source[log_level]}" = "cli:-vv" ]
}

@test "records env user project and overlay provenance" {
  local -A ctx config source line

  printf '%s\n' 'json=true' >"${XDG_CONFIG_HOME}/cog/config.sh"
  printf '%s\n' 'dry_run=true' >"${XDG_CONFIG_HOME}/cog/conf.d/20-dry-run.sh"
  printf '%s\n' 'log_level=info' >"${PROJECT_DIR}/.cog/config.sh"
  # shellcheck disable=SC2031 # Each bats @test runs in its own subshell; exporting the env layer here is intentional.
  export COG_JSON=false
  ctx=()

  cog::fn::config_load ctx config source line

  [ "${source[json]}" = "env:COG_JSON" ]
  [ "${source[dry_run]}" = "user-overlay:${XDG_CONFIG_HOME}/cog/conf.d/20-dry-run.sh" ]
  [ "${source[log_level]}" = "project:${PROJECT_DIR}/.cog/config.sh" ]
}

@test "unknown file key fails loudly" {
  printf '%s\n' 'typo=true' >"${XDG_CONFIG_HOME}/cog/config.sh"

  # shellcheck disable=SC2016 # The single-quoted body is a deferred bash -c script; positional args expand inside it, not here.
  run --separate-stderr bash -c '
    cd "$1"
    export HOME="$2"
    export XDG_CONFIG_HOME="$3"
    source "$4"
    source "$5"
    declare -A ctx config source line
    cog::fn::config_load ctx config source line
  ' _ "$PROJECT_DIR" "$HOME" "$XDG_CONFIG_HOME" \
    "${LIB_DIR}/helpers.sh" "${LIB_DIR}/functions/fn_config_load.sh"

  assert_failure 78
  [[ $stderr == *"err.kind: UnknownConfigKey"* ]]
}

@test "invalid boolean fails loudly" {
  printf '%s\n' 'json=maybe' >"${XDG_CONFIG_HOME}/cog/config.sh"

  # shellcheck disable=SC2016 # The single-quoted body is a deferred bash -c script; positional args expand inside it, not here.
  run --separate-stderr bash -c '
    cd "$1"
    export HOME="$2"
    export XDG_CONFIG_HOME="$3"
    source "$4"
    source "$5"
    declare -A ctx config source line
    cog::fn::config_load ctx config source line
  ' _ "$PROJECT_DIR" "$HOME" "$XDG_CONFIG_HOME" \
    "${LIB_DIR}/helpers.sh" "${LIB_DIR}/functions/fn_config_load.sh"

  assert_failure 78
  [[ $stderr == *"err.kind: InvalidConfigValue"* ]]
}

@test "invalid log level fails loudly" {
  printf '%s\n' 'log_level=loud' >"${PROJECT_DIR}/.cog/config.sh"

  # shellcheck disable=SC2016 # The single-quoted body is a deferred bash -c script; positional args expand inside it, not here.
  run --separate-stderr bash -c '
    cd "$1"
    export HOME="$2"
    export XDG_CONFIG_HOME="$3"
    source "$4"
    source "$5"
    declare -A ctx config source line
    cog::fn::config_load ctx config source line
  ' _ "$PROJECT_DIR" "$HOME" "$XDG_CONFIG_HOME" \
    "${LIB_DIR}/helpers.sh" "${LIB_DIR}/functions/fn_config_load.sh"

  assert_failure 78
  [[ $stderr == *"err.kind: InvalidConfigValue"* ]]
}

@test "non-assignment statement in config file fails before sourcing" {
  # shellcheck disable=SC2016 # The single-quoted payload is the literal config line under test; it must not expand here.
  printf '%s\n' 'json=true' 'echo PWNED > "${BATS_TEST_TMPDIR}/pwned"' \
    >"${XDG_CONFIG_HOME}/cog/config.sh"

  # shellcheck disable=SC2016 # The single-quoted body is a deferred bash -c script; positional args expand inside it, not here.
  run --separate-stderr bash -c '
    cd "$1"
    export HOME="$2"
    export XDG_CONFIG_HOME="$3"
    source "$4"
    source "$5"
    declare -A ctx config source line
    cog::fn::config_load ctx config source line
  ' _ "$PROJECT_DIR" "$HOME" "$XDG_CONFIG_HOME" \
    "${LIB_DIR}/helpers.sh" "${LIB_DIR}/functions/fn_config_load.sh"

  assert_failure 78
  [[ $stderr == *"err.kind: InvalidConfigStatement"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/pwned" ]
}

@test "assignment with command-substitution value is rejected and never executed" {
  # shellcheck disable=SC2016 # The single-quoted payload is the literal config line under test; it must not expand here.
  printf '%s\n' 'json="$(touch "${BATS_TEST_TMPDIR}/pwned"; echo true)"' \
    >"${XDG_CONFIG_HOME}/cog/config.sh"

  # shellcheck disable=SC2016 # The single-quoted body is a deferred bash -c script; positional args expand inside it, not here.
  run --separate-stderr bash -c '
    cd "$1"
    export HOME="$2"
    export XDG_CONFIG_HOME="$3"
    source "$4"
    source "$5"
    declare -A ctx config source line
    cog::fn::config_load ctx config source line
  ' _ "$PROJECT_DIR" "$HOME" "$XDG_CONFIG_HOME" \
    "${LIB_DIR}/helpers.sh" "${LIB_DIR}/functions/fn_config_load.sh"

  assert_failure 78
  [[ $stderr == *"err.kind: InvalidConfigStatement"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/pwned" ]
}

@test "allowed key followed by a command separator is rejected and never executed" {
  # shellcheck disable=SC2016 # The single-quoted payload is the literal config line under test; it must not expand here.
  printf '%s\n' 'json=true; touch "${BATS_TEST_TMPDIR}/pwned"' \
    >"${XDG_CONFIG_HOME}/cog/config.sh"

  # shellcheck disable=SC2016 # The single-quoted body is a deferred bash -c script; positional args expand inside it, not here.
  run --separate-stderr bash -c '
    cd "$1"
    export HOME="$2"
    export XDG_CONFIG_HOME="$3"
    source "$4"
    source "$5"
    declare -A ctx config source line
    cog::fn::config_load ctx config source line
  ' _ "$PROJECT_DIR" "$HOME" "$XDG_CONFIG_HOME" \
    "${LIB_DIR}/helpers.sh" "${LIB_DIR}/functions/fn_config_load.sh"

  assert_failure 78
  [[ $stderr == *"err.kind: InvalidConfigStatement"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/pwned" ]
}

@test "allowed key followed by a redirection is rejected and never executed" {
  # shellcheck disable=SC2016 # The single-quoted payload is the literal config line under test; it must not expand here.
  printf '%s\n' 'json=true > "${BATS_TEST_TMPDIR}/pwned"' \
    >"${XDG_CONFIG_HOME}/cog/config.sh"

  # shellcheck disable=SC2016 # The single-quoted body is a deferred bash -c script; positional args expand inside it, not here.
  run --separate-stderr bash -c '
    cd "$1"
    export HOME="$2"
    export XDG_CONFIG_HOME="$3"
    source "$4"
    source "$5"
    declare -A ctx config source line
    cog::fn::config_load ctx config source line
  ' _ "$PROJECT_DIR" "$HOME" "$XDG_CONFIG_HOME" \
    "${LIB_DIR}/helpers.sh" "${LIB_DIR}/functions/fn_config_load.sh"

  assert_failure 78
  [[ $stderr == *"err.kind: InvalidConfigStatement"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/pwned" ]
}

@test "double-quoted literal config values parse" {
  local -A ctx config source line

  printf '%s\n' 'json="true"' 'log_level="debug"' >"${XDG_CONFIG_HOME}/cog/config.sh"
  ctx=()

  cog::fn::config_load ctx config source line

  [ "${config[json]}" = "true" ]
  [ "${config[log_level]}" = "debug" ]
}

@test "uses xdg config home without legacy paths" {
  local -A ctx config source line

  printf '%s\n' 'json=true' >"${XDG_CONFIG_HOME}/cog/config.sh"
  mkdir -p "${HOME}/.cog"
  printf '%s\n' 'json=false' >"${HOME}/.cog/config.sh"
  ctx=()

  cog::fn::config_load ctx config source line

  [ "${config[json]}" = "true" ]
  [ "${source[json]}" = "user:${XDG_CONFIG_HOME}/cog/config.sh" ]
}
