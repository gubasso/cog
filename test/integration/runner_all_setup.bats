setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"
  REPO_ROOT="${BATS_TEST_TMPDIR}/repo"
  export REPO_ROOT
  mkdir -p "$REPO_ROOT"
  git -C "$REPO_ROOT" init -q
  git -C "$REPO_ROOT" config user.email a@b.c
  git -C "$REPO_ROOT" config user.name tester
  git -C "$REPO_ROOT" remote add origin https://example.com/repo.git
  cd "$REPO_ROOT" || return 1
}

# Build a vault plan in the given store with one main-queue plan item; echo
# PLAN_DIR/PLAN_ROOT lines. A repos_yaml fragment is prepended to the main queue.
_new_plan() {
  local store="$1" title="$2" repos_yaml="${3:-}" newjson plan_dir plan_root
  newjson="$(cog plan new --title "$title" --"$store" --project-root "$REPO_ROOT" --json)"
  plan_dir="$(jq -r '.plan_dir' <<<"$newjson")"
  plan_root="$(jq -r '.plan_root' <<<"$newjson")"
  mkdir -p "$plan_dir/rounds"
  printf '# next round\n' >"$plan_dir/rounds/next.md"
  cog queue-append --schema rounds --queue "$plan_dir/queue-rounds.yaml" \
    --item next --status todo --prompt "/executor-prex -ar next.md" --json >/dev/null
  {
    printf '%s' "$repos_yaml"
    cat <<EOF
plans:
  - item: main
    status: todo
    depends_on: []
    prompt: /runner-plan -ar @${plan_dir}/
    notes: note
EOF
  } >"$plan_root/queue-plans.yaml"
  printf 'PLAN_DIR=%s\n' "$plan_dir"
  printf 'PLAN_ROOT=%s\n' "$plan_root"
}

@test "cog runner-all-setup writes ctx and preserves selected prompt verbatim (global store)" {
  built="$(_new_plan global 'Main')"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"

  run cog runner-all-setup --json "--dry-run --max=3 ${plan_root}/queue-plans.yaml"
  assert_success
  printf '%s\n' "$output" | jq -e '.dry_run == true and .max_plans == "3" and .queue_schema == "plans" and .store == "global" and (.queue_path | endswith("/queue-plans.yaml"))' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "QUEUE_SCHEMA=plans"
  assert_file_contains "${run_dir}/ctx.env" "PLAN_ROOT="
  assert_file_contains "${run_dir}/ctx.env" "MAIN_QUEUE_PATH="
  assert_file_contains "${run_dir}/ctx.env" "PLAN_STORE=global"
  assert_file_contains "${run_dir}/ctx.env" "PROJECT_KEY="
  assert_file_contains "${run_dir}/ctx.env" "MAX_PLANS=3"
  jq -e --arg p "/runner-plan -ar @${plan_dir}/" '.schema == "plans" and .selected.item == "main" and .selected.prompt == $p' "${run_dir}/main-select.json" >/dev/null
}

@test "cog runner-all-setup resolves a trusted local-store main queue" {
  cog plan trust --project-root "$REPO_ROOT" --json >/dev/null
  built="$(_new_plan local 'Local')"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"

  run cog runner-all-setup --json ".cog/plans/queue-plans.yaml"
  assert_success
  printf '%s\n' "$output" | jq -e '.store == "local" and (.plan_root | endswith("/.cog/plans"))' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "PLAN_STORE=local"
}

@test "cog runner-all-setup persists satellite repos from main queue" {
  mkdir -p "${BATS_TEST_TMPDIR}/satellite"
  built="$(_new_plan global 'Main' "repos:
  - ${BATS_TEST_TMPDIR}/satellite
")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"

  run cog runner-all-setup --json "${plan_root}/queue-plans.yaml"
  assert_success
  printf '%s\n' "$output" | jq -e --arg sat "${BATS_TEST_TMPDIR}/satellite" '.repos == [$sat]' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "REPOS="
  assert_file_contains "${run_dir}/ctx.env" "${BATS_TEST_TMPDIR}/satellite"
}

@test "cog runner-all-setup rejects a plan-dir target" {
  built="$(_new_plan global 'Main')"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"

  run --separate-stderr cog runner-all-setup --json "$plan_dir"
  assert_failure
  [[ $stderr == *"runner-all target must be queue-plans.yaml"* ]]
}

@test "cog runner-all-setup rejects invalid max and missing target" {
  run --separate-stderr cog runner-all-setup --json "--max 0 queue-plans.yaml"
  assert_failure 2
  [[ $stderr == *"invalid max plans"* ]]

  run --separate-stderr cog runner-all-setup --json "--dry-run"
  assert_failure 2
  [[ $stderr == *"missing main queue target"* ]]
}

@test "cog runner-all-setup --help dispatches" {
  run cog runner-all-setup --help
  assert_success
  [[ $output == *"Parse runner-all"* ]]
}
