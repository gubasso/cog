setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/helpers.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_json_write.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_plan_slug.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_plan_store.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_queue.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_plan_resolve.sh"
}

# Initialize a git repo with a remote and one commit so worktrees can be added.
_init_git_repo() {
  local dir="$1" remote="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" remote add origin "$remote"
  : >"${dir}/seed"
  git -C "$dir" add seed
  git -C "$dir" commit -q -m seed
}

@test "plan_store_root honors XDG_DATA_HOME and COG_PLAN_HOME" {
  run cog::fn::plan_store_root
  assert_success
  assert_output "${XDG_DATA_HOME}/cog/plans"

  export COG_PLAN_HOME="${BATS_TEST_TMPDIR}/custom-plans"
  run cog::fn::plan_store_root
  assert_success
  assert_output "${COG_PLAN_HOME}"
}

@test "plan_trust_db_path honors XDG_STATE_HOME" {
  run cog::fn::plan_trust_db_path
  assert_success
  assert_output "${XDG_STATE_HOME}/cog/trust/plans.json"
}

@test "project key is slug plus 16 hex chars and stable" {
  local repo="${BATS_TEST_TMPDIR}/Example Project"
  mkdir -p "$repo"

  run cog::fn::plan_project_identity_json "$repo"
  assert_success
  local first="$output"
  jq -e '.project_key | test("^example-project-[0-9a-f]{16}$")' <<<"$first"

  run cog::fn::plan_project_identity_json "$repo"
  assert_success
  assert_equal "$(jq -r '.project_key' <<<"$first")" "$(jq -r '.project_key' <<<"$output")"
}

@test "moved repo path is appended to COG_PLAN_ROOTS" {
  local repo_a="${BATS_TEST_TMPDIR}/repo-a"
  local repo_b="${BATS_TEST_TMPDIR}/repo-b"
  local dir="${BATS_TEST_TMPDIR}/store/projects/repo"
  mkdir -p "$repo_a" "$repo_b" "$dir"

  cog::fn::plan_write_project_file "$dir" "$repo_a"
  cog::fn::plan_write_project_file "$dir" "$repo_b"

  assert_file_contains "${dir}/project.sh" "COG_PLAN_ROOTS='${repo_b}:${repo_a}'"
}

@test "project key is stable across worktrees of one git identity" {
  local repo="${BATS_TEST_TMPDIR}/main"
  local wt="${BATS_TEST_TMPDIR}/wt2"
  _init_git_repo "$repo" "https://example.com/foo.git"
  git -C "$repo" worktree add -q "$wt" -b feature

  run cog::fn::plan_project_identity_json "$repo"
  assert_success
  local key_main
  key_main="$(jq -r '.project_key' <<<"$output")"

  run cog::fn::plan_project_identity_json "$wt"
  assert_success
  local key_wt
  key_wt="$(jq -r '.project_key' <<<"$output")"

  assert_equal "$key_main" "$key_wt"
  # Keyed on git identity (remote), so the slug is the remote basename, not the
  # per-worktree directory name.
  jq -e '.project_key | test("^foo-[0-9a-f]{16}$")' <<<"$output"
}

@test "unrelated git repos get distinct project keys" {
  local repo_a="${BATS_TEST_TMPDIR}/a"
  local repo_b="${BATS_TEST_TMPDIR}/b"
  _init_git_repo "$repo_a" "https://example.com/alpha.git"
  _init_git_repo "$repo_b" "https://example.com/beta.git"

  run cog::fn::plan_project_identity_json "$repo_a"
  assert_success
  local key_a
  key_a="$(jq -r '.project_key' <<<"$output")"

  run cog::fn::plan_project_identity_json "$repo_b"
  assert_success
  local key_b
  key_b="$(jq -r '.project_key' <<<"$output")"

  [ "$key_a" != "$key_b" ]
}

@test "moved repo repairs COG_PLAN_ROOTS through plan_project_init_global" {
  # The vault resolves under the temp XDG_DATA_HOME pinned in setup; no override.
  local first="${BATS_TEST_TMPDIR}/loc-1"
  local second="${BATS_TEST_TMPDIR}/loc-2"
  _init_git_repo "$first" "https://example.com/moved.git"

  run cog::fn::plan_project_init_global "$first"
  assert_success
  local dir_first="$output"

  # Simulate a move: same git identity (remote), different checkout path.
  cp -a "$first" "$second"
  run cog::fn::plan_project_init_global "$second"
  assert_success
  local dir_second="$output"

  # Same git identity -> same vault project dir (coalesced, not forked).
  assert_equal "$dir_first" "$dir_second"
  # Both checkout paths recorded as roots (repair, not fork).
  assert_file_contains "${dir_second}/project.sh" "$first"
  assert_file_contains "${dir_second}/project.sh" "$second"
}
