setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export COG_UI_JSON=false
  mkdir -p "$HOME"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_json_write.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_prereq.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_init.sh"
}

@test "init creates all runtime dirs" {
  run --separate-stderr cog::cmd::init

  assert_success
  [ -z "$stderr" ]
  [[ $output == *"created config ${XDG_CONFIG_HOME}/cog"* ]]
  [[ $output == *"created state ${XDG_STATE_HOME}/cog"* ]]
  [[ $output == *"created cache ${XDG_CACHE_HOME}/cog"* ]]
  [[ $output == *"created data ${XDG_DATA_HOME}/cog"* ]]
  [[ $output == *"INIT_OK" ]]
  [ -d "${XDG_CONFIG_HOME}/cog" ]
  [ -d "${XDG_STATE_HOME}/cog" ]
  [ -d "${XDG_CACHE_HOME}/cog" ]
  [ -d "${XDG_DATA_HOME}/cog" ]
}

@test "init re-run reports existing dirs" {
  mkdir -p "${XDG_CONFIG_HOME}/cog" "${XDG_STATE_HOME}/cog" "${XDG_CACHE_HOME}/cog" "${XDG_DATA_HOME}/cog"

  run --separate-stderr cog::cmd::init

  assert_success
  [ -z "$stderr" ]
  [[ $output == *"existing config ${XDG_CONFIG_HOME}/cog"* ]]
  [[ $output == *"existing state ${XDG_STATE_HOME}/cog"* ]]
  [[ $output == *"existing cache ${XDG_CACHE_HOME}/cog"* ]]
  [[ $output == *"existing data ${XDG_DATA_HOME}/cog"* ]]
  [[ $output == *"INIT_OK" ]]
}

@test "init dry-run creates nothing" {
  run --separate-stderr cog::cmd::init --dry-run

  assert_success
  [ -z "$stderr" ]
  [[ $output == *"would-create config ${XDG_CONFIG_HOME}/cog"* ]]
  [[ $output == *"would-create state ${XDG_STATE_HOME}/cog"* ]]
  [[ $output == *"would-create cache ${XDG_CACHE_HOME}/cog"* ]]
  [[ $output == *"would-create data ${XDG_DATA_HOME}/cog"* ]]
  [[ $output == *"INIT_OK" ]]
  [ ! -e "${XDG_CONFIG_HOME}/cog" ]
  [ ! -e "${XDG_STATE_HOME}/cog" ]
  [ ! -e "${XDG_CACHE_HOME}/cog" ]
  [ ! -e "${XDG_DATA_HOME}/cog" ]
}

@test "init dry-run reports provably uncreatable dirs as failed" {
  # XDG_CACHE_HOME is a regular file, so ${XDG_CACHE_HOME}/cog can never be
  # created. Dry-run must surface this as a failure (not a false INIT_OK)
  # without mutating the filesystem, so it stays a reliable preflight.
  printf '%s\n' "not a directory" >"$XDG_CACHE_HOME"

  run --separate-stderr cog::cmd::init --dry-run

  assert_failure "$EX_CONFIG"
  [ -z "$stderr" ]
  [[ $output == *"would-create config ${XDG_CONFIG_HOME}/cog"* ]]
  [[ $output == *"failed cache ${XDG_CACHE_HOME}/cog"* ]]
  [[ $output == *"INIT_FAILED config"* ]]
  [ ! -e "${XDG_CONFIG_HOME}/cog" ]
}

@test "init emits JSON with schema and arrays" {
  COG_UI_JSON=true

  run --separate-stderr cog::cmd::init

  assert_success
  [ -z "$stderr" ]
  printf '%s\n' "$output" | jq -e \
    '.schema=="cog.init.v1" and (.created|type=="array") and (.existing|type=="array")' >/dev/null
}

@test "init local --json emits JSON" {
  run --separate-stderr cog::cmd::init --json

  assert_success
  [ -z "$stderr" ]
  printf '%s\n' "$output" | jq -e '.schema=="cog.init.v1" and .ok == true' >/dev/null
}

@test "init failure exits EX_CONFIG" {
  printf '%s\n' "not a directory" >"$XDG_CACHE_HOME"

  run --separate-stderr cog::cmd::init

  assert_failure "$EX_CONFIG"
  [ -z "$stderr" ]
  [[ $output == *"failed cache ${XDG_CACHE_HOME}/cog"* ]]
  [[ $output == *"INIT_FAILED config"* ]]
}
