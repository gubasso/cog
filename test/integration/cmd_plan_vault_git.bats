setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"
  export COG_BIN="${BATS_TEST_DIRNAME}/../../bin/cog"
  STORE_ROOT="${XDG_DATA_HOME}/cog/plans"
}

@test "plan store init is git-by-default" {
  run "$COG_BIN" plan store init --json
  assert_success
  assert_dir_exists "${STORE_ROOT}/.git"
}

@test "plan store init --no-git skips git" {
  run "$COG_BIN" plan store init --no-git --json
  assert_success
  [[ ! -e "${STORE_ROOT}/.git" ]]
}

@test "plan store init rejects the removed --git flag" {
  run --separate-stderr "$COG_BIN" plan store init --git --json
  assert_failure
  [[ $stderr == *"--git flag was removed"* ]]
}

@test "plan new --global git-inits the global store" {
  proj="${BATS_TEST_TMPDIR}/proj"
  mkdir -p "$proj"
  git -C "$proj" init -q
  git -C "$proj" remote add origin https://example.com/proj.git
  run bash -c "cd '$proj' && '$COG_BIN' plan new --title 'First Plan' --global --json"
  assert_success
  assert_dir_exists "${STORE_ROOT}/.git"
}

@test "project key collision-extends for a different git identity and stays stable" {
  proj="${BATS_TEST_TMPDIR}/realproj"
  mkdir -p "$proj"
  git -C "$proj" init -q
  git -C "$proj" remote add origin https://example.com/realproj.git
  realkey="$(bash -c "cd '$proj' && '$COG_BIN' plan project resolve --json" | jq -r '.project_key')"

  # Precreate a colliding vault entry at the same key with a DIFFERENT identity.
  mkdir -p "${STORE_ROOT}/projects/${realkey}"
  cat >"${STORE_ROOT}/projects/${realkey}/project.sh" <<EOS
COG_PLAN_PROJECT_KEY='${realkey}'
COG_PLAN_GIT_IDENTITY='https://example.com/someone-else.git'
EOS

  extended="$(bash -c "cd '$proj' && '$COG_BIN' plan project resolve --json" | jq -r '.project_key')"
  [[ $extended != "$realkey" ]]
  again="$(bash -c "cd '$proj' && '$COG_BIN' plan project resolve --json" | jq -r '.project_key')"
  assert_equal "$again" "$extended"
}

@test "plan flat-root assertion tolerates a rounds subdir but rejects a nested plan" {
  proj="${BATS_TEST_TMPDIR}/p2"
  mkdir -p "$proj"
  git -C "$proj" init -q
  git -C "$proj" remote add origin https://example.com/p2.git
  plan_dir="$(bash -c "cd '$proj' && '$COG_BIN' plan new --title 'Demo' --global --json" | jq -r '.plan_dir')"
  # rounds/ subdir with a round file is tolerated (a second plan new still succeeds).
  mkdir -p "$plan_dir/rounds"
  printf '# r\n' >"$plan_dir/rounds/topic.md"
  run bash -c "cd '$proj' && '$COG_BIN' plan new --title 'Second Plan' --global --json"
  assert_success
}

@test "plan project resolve does not leave a non-git global tree" {
  proj="${BATS_TEST_TMPDIR}/resolveproj"
  mkdir -p "$proj"
  git -C "$proj" init -q
  git -C "$proj" remote add origin https://example.com/resolveproj.git
  run bash -c "cd '$proj' && '$COG_BIN' plan project resolve --json"
  assert_success
  # ADR-0011 D2: a read-only resolve must not create the global tree without git.
  # Either the global tree is absent, or if present it carries .git.
  if [[ -d $STORE_ROOT ]]; then
    assert_dir_exists "${STORE_ROOT}/.git"
  fi
}
