setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_CACHE_HOME="${BATS_TEST_TMPDIR}/cache"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  mkdir -p "$HOME"
}

@test "cog --json init emits JSON on stdout only" {
  run --separate-stderr cog --json init

  assert_success
  [ -z "$stderr" ]
  printf '%s\n' "$output" | jq -e '.schema=="cog.init.v1" and .ok == true' >/dev/null
}

@test "cog init creates runtime dirs and emits INIT_OK" {
  run --separate-stderr cog init

  assert_success
  [ -z "$stderr" ]
  [[ $output == *"INIT_OK" ]]
  [ -d "${XDG_CONFIG_HOME}/cog" ]
  [ -d "${XDG_STATE_HOME}/cog" ]
  [ -d "${XDG_CACHE_HOME}/cog" ]
  [ -d "${XDG_DATA_HOME}/cog" ]
}
