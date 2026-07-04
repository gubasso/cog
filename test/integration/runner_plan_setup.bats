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

# Build a vault plan in the given store; echo PLAN_DIR and PLAN_ROOT lines.
# When a repos_yaml fragment is passed it is prepended to the inner queue.
_new_plan() {
  local store="$1" title="$2" repos_yaml="${3:-}" newjson plan_dir plan_root
  newjson="$(cog plan new --title "$title" --"$store" --project-root "$REPO_ROOT" --json)"
  plan_dir="$(jq -r '.plan_dir' <<<"$newjson")"
  plan_root="$(jq -r '.plan_root' <<<"$newjson")"
  mkdir -p "$plan_dir/rounds"
  printf '# next round\n' >"$plan_dir/rounds/next.md"
  cog queue-append --schema plans --queue "$plan_root/queue-plans.yaml" \
    --item "$(basename "$plan_dir")" --status todo --prompt "/runner-plan -ar @$plan_dir/" --json >/dev/null
  {
    printf '%s' "$repos_yaml"
    cat <<'EOF'
rounds:
  - item: next
    status: todo
    depends_on: []
    prompt: /executor-prex -ar next.md
    notes: note
EOF
  } >"$plan_dir/queue-rounds.yaml"
  printf 'PLAN_DIR=%s\n' "$plan_dir"
  printf 'PLAN_ROOT=%s\n' "$plan_root"
}

@test "cog runner-plan-setup writes ctx and initial round selection (global store)" {
  built="$(_new_plan global 'Main')"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"

  run cog runner-plan-setup --json "--dry-run --max=2 -ar @${plan_dir}/"
  assert_success
  printf '%s\n' "$output" | jq -e '.dry_run == true and .max_rounds == "2" and .queue_schema == "rounds" and .store == "global" and (.plan_dir | endswith("/plans/main"))' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "QUEUE_SCHEMA=rounds"
  assert_file_contains "${run_dir}/ctx.env" "INNER_QUEUE_PATH="
  assert_file_contains "${run_dir}/ctx.env" "PLAN_ROOT="
  assert_file_contains "${run_dir}/ctx.env" "MAIN_QUEUE_PATH="
  assert_file_contains "${run_dir}/ctx.env" "PLAN_STORE=global"
  assert_file_contains "${run_dir}/ctx.env" "PROJECT_KEY="
  jq -e '.schema == "rounds" and .selected.item == "next" and .selected.prompt == "/executor-prex -ar next.md"' "${run_dir}/round-select.json" >/dev/null
}

@test "cog runner-plan-setup resolves a trusted local-store plan directory" {
  cog plan trust --project-root "$REPO_ROOT" --json >/dev/null
  built="$(_new_plan local 'Local')"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"

  run cog runner-plan-setup --json "-ar @${plan_dir}/"
  assert_success
  printf '%s\n' "$output" | jq -e '.store == "local" and (.plan_root | endswith("/.cog/plans"))' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "PLAN_STORE=local"
}

@test "cog runner-plan-setup persists satellite repos from inner queue" {
  mkdir -p "${BATS_TEST_TMPDIR}/satellite"
  built="$(_new_plan global 'Main' "repos:
  - ${BATS_TEST_TMPDIR}/satellite
")"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"

  run cog runner-plan-setup --json "-ar @${plan_dir}/"
  assert_success
  printf '%s\n' "$output" | jq -e --arg sat "${BATS_TEST_TMPDIR}/satellite" '.repos == [$sat]' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "${BATS_TEST_TMPDIR}/satellite"
}

@test "cog runner-plan-setup fails closed for bad targets" {
  built="$(_new_plan global 'Main')"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"

  printf 'file target\n' >"$REPO_ROOT/file-target.md"
  run --separate-stderr cog runner-plan-setup --json "-ar @file-target.md"
  assert_failure
  [[ $stderr == *"plan target is not a directory"* ]]

  mkdir -p "$plan_root/plans/no-queue"
  run --separate-stderr cog runner-plan-setup --json "-ar @$plan_root/plans/no-queue"
  assert_failure
  [[ $stderr == *"plan directory has no queue-rounds.yaml"* ]]

  run --separate-stderr cog runner-plan-setup --json "-ar @$plan_root/plans/missing"
  assert_failure
  [[ $stderr == *"plan target not found"* ]]
}

@test "cog runner-plan-setup rejects a plan directory outside the resolved vault" {
  rogue="${BATS_TEST_TMPDIR}/rogue"
  mkdir -p "$rogue/plans/x"
  printf 'rounds: []\n' >"$rogue/plans/x/queue-rounds.yaml"

  run --separate-stderr cog runner-plan-setup --json "-ar @$rogue/plans/x"
  assert_failure
  [[ $stderr == *"not a member of the resolved plan vault"* ]]
}

@test "cog runner-plan-setup rejects invalid max and missing -ar target" {
  run --separate-stderr cog runner-plan-setup --json "--max 0 -ar @foo"
  assert_failure 2
  [[ $stderr == *"invalid max rounds"* ]]

  run --separate-stderr cog runner-plan-setup --json "--dry-run"
  assert_failure 2
  [[ $stderr == *"missing runner-plan target"* ]]
}

@test "cog runner-plan-setup --help dispatches" {
  run cog runner-plan-setup --help
  assert_success
  [[ $output == *"Parse runner-plan"* ]]
}
