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
  export REPO_ROOT="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO_ROOT"
}

@test "plan command global store and resolution smoke" {
  run "$COG_BIN" plan store init --global --json
  assert_success
  assert_equal "$(jq -r '.schema' <<<"$output")" "cog.plan.store.v1"
  assert_file_exists "${XDG_DATA_HOME}/cog/plans/config.sh"
  assert_dir_exists "${XDG_DATA_HOME}/cog/plans/projects"
  assert_dir_exists "${XDG_DATA_HOME}/cog/plans/aliases"
  [[ ! -e ${REPO_ROOT}/.implementation-plans ]]

  run "$COG_BIN" plan project resolve --project-root "$REPO_ROOT" --store global --json
  assert_success
  assert_equal "$(jq -r '.schema' <<<"$output")" "cog.plan.resolve.v1"
  assert_equal "$(jq -r '.store' <<<"$output")" "global"
  jq -e '.project_key | test("^repo-[0-9a-f]{16}$")' <<<"$output"
}

@test "plan command auto fallback and trust transitions" {
  mkdir -p "${REPO_ROOT}/.cog/plans"

  run "$COG_BIN" plan project resolve --project-root "$REPO_ROOT" --json
  assert_success
  assert_equal "$(jq -r '.store' <<<"$output")" "global"
  assert_equal "$(jq -r '.trust.status' <<<"$output")" "local-untrusted-fell-back"

  run --separate-stderr "$COG_BIN" plan project resolve --project-root "$REPO_ROOT" --store local --json
  assert_failure 65
  [[ $stderr == *"local plan root is not trusted"* ]]

  run "$COG_BIN" plan trust --project-root "$REPO_ROOT" --json
  assert_success
  assert_equal "$(jq -r '.status' <<<"$output")" "trusted"

  run "$COG_BIN" plan trust-status --project-root "$REPO_ROOT" --json
  assert_success
  assert_equal "$(jq -r '.status' <<<"$output")" "trusted"

  run "$COG_BIN" plan project resolve --project-root "$REPO_ROOT" --store local --json
  assert_success
  assert_equal "$(jq -r '.store' <<<"$output")" "local"
  assert_file_exists "${REPO_ROOT}/.cog/plans/queue-plans.yaml"

  run "$COG_BIN" plan distrust --project-root "$REPO_ROOT" --json
  assert_success
  assert_equal "$(jq -r '.status' <<<"$output")" "absent"
}

@test "plan new, list, and path manage plan items under the resolved root" {
  run "$COG_BIN" plan new --title "Refactor Auth Module" --global --project-root "$REPO_ROOT" --json
  assert_success
  assert_equal "$(jq -r '.schema' <<<"$output")" "cog.plan.item.v1"
  assert_equal "$(jq -r '.plan_slug' <<<"$output")" "refactor-auth-module"
  local plan_dir
  plan_dir="$(jq -r '.plan_dir' <<<"$output")"
  assert_dir_exists "$plan_dir"
  assert_dir_exists "${plan_dir}/rounds"
  assert_file_exists "${plan_dir}/README.md"
  assert_file_exists "${plan_dir}/queue-rounds.yaml"

  run "$COG_BIN" plan new --title "Add Caching Layer" --global --project-root "$REPO_ROOT" --json
  assert_success

  run "$COG_BIN" plan list --global --project-root "$REPO_ROOT" --json
  assert_success
  assert_equal "$(jq -r '.schema' <<<"$output")" "cog.plan.item-list.v1"
  assert_equal "$(jq -r '.plans | length' <<<"$output")" "2"
  jq -e '.plans | index("refactor-auth-module")' <<<"$output"
  jq -e '.plans | index("add-caching-layer")' <<<"$output"

  run "$COG_BIN" plan path refactor-auth-module --global --project-root "$REPO_ROOT" --json
  assert_success
  assert_equal "$(jq -r '.schema' <<<"$output")" "cog.plan.item-path.v1"
  assert_equal "$(jq -r '.plan_dir' <<<"$output")" "$plan_dir"

  run --separate-stderr "$COG_BIN" plan path nonexistent --global --project-root "$REPO_ROOT" --json
  assert_failure
  [[ $stderr == *"plan not found"* ]]

  run --separate-stderr "$COG_BIN" plan new --global --project-root "$REPO_ROOT" --json
  assert_failure
  [[ $stderr == *"missing plan title"* ]]
}

@test "plan trust honors project-configured local dir" {
  mkdir -p "${REPO_ROOT}/.cog"
  printf '%s\n' "COG_PLAN_LOCAL_DIR='alt/plans'" >"${REPO_ROOT}/.cog/config.sh"

  run "$COG_BIN" plan trust --project-root "$REPO_ROOT" --json
  assert_success
  assert_equal "$(jq -r '.status' <<<"$output")" "trusted"
  assert_file_exists "${REPO_ROOT}/alt/plans/project.sh"
  [[ ! -e ${REPO_ROOT}/.cog/plans ]]

  run "$COG_BIN" plan project resolve --project-root "$REPO_ROOT" --store local --json
  assert_success
  assert_equal "$(jq -r '.store' <<<"$output")" "local"
  assert_equal "$(jq -r '.plan_root' <<<"$output")" "${REPO_ROOT}/alt/plans"

  run "$COG_BIN" plan distrust --project-root "$REPO_ROOT" --json
  assert_success
  assert_equal "$(jq -r '.status' <<<"$output")" "absent"
}
