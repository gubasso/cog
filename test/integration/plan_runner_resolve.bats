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
  REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email a@b.c
  git -C "$REPO" config user.name tester
  git -C "$REPO" remote add origin https://example.com/repo.git
}

# Build a vault plan in the given store and queue one plan + one round item.
# Echoes PLAN_DIR and PLAN_ROOT lines.
_build_plan() {
  local store="$1" title="$2" newjson plan_dir plan_root
  newjson="$("$COG_BIN" plan new --title "$title" --"$store" --project-root "$REPO" --json)"
  plan_dir="$(jq -r '.plan_dir' <<<"$newjson")"
  plan_root="$(jq -r '.plan_root' <<<"$newjson")"
  "$COG_BIN" queue-append --schema plans --queue "$plan_root/queue-plans.yaml" \
    --item "the-plan" --status todo --prompt "/runner-plan -ar @$plan_dir/" --json >/dev/null
  "$COG_BIN" queue-append --schema rounds --queue "$plan_dir/queue-rounds.yaml" \
    --item "setup" --status todo --prompt "/executor-prex -ar $plan_dir/rounds/setup.md" --json >/dev/null
  printf 'PLAN_DIR=%s\n' "$plan_dir"
  printf 'PLAN_ROOT=%s\n' "$plan_root"
}

@test "resolves a global-store plan directory" {
  built="$(_build_plan global 'Global Plan')"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  run "$COG_BIN" plan runner-resolve --target "$plan_dir" --project-root "$REPO" --json
  assert_success
  echo "$output" | jq -e '.ok and .store=="global" and .target_type=="plan-dir"'
  echo "$output" | jq -e '.plan_root | startswith("'"$XDG_DATA_HOME"'/cog/plans/projects/")'
  echo "$output" | jq -e '.main_queue == (.plan_root + "/queue-plans.yaml")'
  echo "$output" | jq -e '.inner_queue_path == (.plan_dir + "/queue-rounds.yaml")'
  echo "$output" | jq -e '.project_key | test("-[0-9a-f]{16}$")'
}

@test "resolves a global-store main queue target" {
  built="$(_build_plan global 'Global Plan')"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  run "$COG_BIN" plan runner-resolve --target "$plan_root/queue-plans.yaml" --project-root "$REPO" --json
  assert_success
  echo "$output" | jq -e '.ok and .target_type=="main-queue" and .plan_dir==null and .inner_queue_path==null'
  echo "$output" | jq -e '.main_queue == "'"$plan_root"'/queue-plans.yaml"'
}

@test "resolves a trusted local-store plan directory" {
  "$COG_BIN" plan trust --project-root "$REPO" --json >/dev/null
  built="$(_build_plan local 'Local Plan')"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  run "$COG_BIN" plan runner-resolve --target "$plan_dir" --project-root "$REPO" --json
  assert_success
  echo "$output" | jq -e '.ok and .store=="local"'
  echo "$output" | jq -e '.plan_root == "'"$REPO"'/.cog/plans"'
}

@test "auto default resolves a global target as global with no trusted local root" {
  built="$(_build_plan global 'Global Plan')"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  run "$COG_BIN" plan runner-resolve --target "$plan_dir" --project-root "$REPO" --json
  assert_success
  echo "$output" | jq -e '.store=="global"'
}

@test "auto default resolves a local target as local when the local root is trusted" {
  "$COG_BIN" plan trust --project-root "$REPO" --json >/dev/null
  built="$(_build_plan local 'Local Plan')"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  run "$COG_BIN" plan runner-resolve --target "$plan_dir" --project-root "$REPO" --json
  assert_success
  echo "$output" | jq -e '.store=="local"'
}

@test "resolves a global target as global despite a local-store config with no trusted local vault" {
  # Regression: a project config of COG_PLAN_STORE=local (untrusted or missing local
  # vault) must not fail-close the resolver before it can honor an explicit global target.
  built="$(_build_plan global 'Global Plan')"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  mkdir -p "$REPO/.cog"
  printf '%s\n' "COG_PLAN_STORE='local'" >"$REPO/.cog/config.sh"
  run "$COG_BIN" plan runner-resolve --target "$plan_dir" --project-root "$REPO" --json
  assert_success
  echo "$output" | jq -e '.store=="global"'
}

@test "resolves an explicit global target as global even when COG_PLAN_ROOT (custom) is configured" {
  # Regression: the global candidate must be the real project vault, not the configured
  # custom root, so a valid global target still matches and resolves as global.
  built="$(_build_plan global 'Global Plan')"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  mkdir -p "$REPO/.cog" "$BATS_TEST_TMPDIR/custom-vault/plans"
  printf '%s\n' "COG_PLAN_ROOT='$BATS_TEST_TMPDIR/custom-vault'" >"$REPO/.cog/config.sh"
  run "$COG_BIN" plan runner-resolve --target "$plan_dir" --project-root "$REPO" --json
  assert_success
  echo "$output" | jq -e '.store=="global"'
}

@test "rejects an untrusted local target" {
  mkdir -p "$REPO/.cog/plans/plans/untrusted"
  printf 'plans: []\n' >"$REPO/.cog/plans/queue-plans.yaml"
  printf 'rounds: []\n' >"$REPO/.cog/plans/plans/untrusted/queue-rounds.yaml"
  run --separate-stderr "$COG_BIN" plan runner-resolve --target "$REPO/.cog/plans/plans/untrusted" --project-root "$REPO" --json
  assert_failure
  [[ $stderr == *"local plan root is not trusted"* ]]
}

@test "rejects a nested plan layout" {
  built="$(_build_plan global 'Global Plan')"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  mkdir -p "$plan_dir/nested"
  printf 'rounds: []\n' >"$plan_dir/nested/queue-rounds.yaml"
  run --separate-stderr "$COG_BIN" plan runner-resolve --target "$plan_root/queue-plans.yaml" --project-root "$REPO" --json
  assert_failure
  [[ $stderr == *"nested plan directory detected"* ]]
}

@test "rejects a plan directory that is not a direct child of plans/" {
  built="$(_build_plan global 'Global Plan')"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  mkdir -p "$plan_root/other"
  printf 'rounds: []\n' >"$plan_root/other/queue-rounds.yaml"
  run --separate-stderr "$COG_BIN" plan runner-resolve --target "$plan_root/other" --project-root "$REPO" --json
  assert_failure
  [[ $stderr == *"direct child of plans/"* ]]
}

@test "rejects a target outside the resolved vault" {
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  printf 'plans: []\n' >"$BATS_TEST_TMPDIR/outside/queue-plans.yaml"
  run --separate-stderr "$COG_BIN" plan runner-resolve --target "$BATS_TEST_TMPDIR/outside/queue-plans.yaml" --project-root "$REPO" --json
  assert_failure
  [[ $stderr == *"not a member of the resolved plan vault"* ]]
}

@test "resolves an absolute out-of-repo global plan dir and queue without rewriting" {
  built="$(_build_plan global 'Global Plan')"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  run "$COG_BIN" plan runner-resolve --target "$plan_dir" --project-root "$REPO" --json
  assert_success
  echo "$output" | jq -e '.plan_dir == "'"$plan_dir"'"'
  run "$COG_BIN" plan runner-resolve --target "$plan_root/queue-plans.yaml" --project-root "$REPO" --json
  assert_success
  echo "$output" | jq -e '.main_queue == "'"$plan_root"'/queue-plans.yaml"'
}
