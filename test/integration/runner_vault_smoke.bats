setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"
  REPO="${BATS_TEST_TMPDIR}/repo"
  export REPO
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email a@b.c
  git -C "$REPO" config user.name tester
  git -C "$REPO" remote add origin https://example.com/repo.git
  cd "$REPO" || return 1
}

# Build a store-scoped vault with one queued plan and one queued round.
# Echoes PLAN_DIR/PLAN_ROOT/ROUND_BODY lines.
_seed_vault() {
  local store="$1" newjson plan_dir plan_root
  [[ $store == local ]] && cog plan trust --project-root "$REPO" --json >/dev/null
  newjson="$(cog plan new --title Smoke --"$store" --project-root "$REPO" --json)"
  plan_dir="$(jq -r '.plan_dir' <<<"$newjson")"
  plan_root="$(jq -r '.plan_root' <<<"$newjson")"
  mkdir -p "$plan_dir/rounds"
  printf '# smoke round\n' >"$plan_dir/rounds/smoke.md"
  cat >"$plan_dir/queue-rounds.yaml" <<EOF
rounds:
  - item: smoke
    status: todo
    depends_on: []
    prompt: /executor-prex -ar ${plan_dir}/rounds/smoke.md
    notes: note
EOF
  cat >"$plan_root/queue-plans.yaml" <<EOF
plans:
  - item: smoke
    status: todo
    depends_on: []
    prompt: /runner-plan -ar @${plan_dir}/
    notes: note
EOF
  printf 'PLAN_DIR=%s\n' "$plan_dir"
  printf 'PLAN_ROOT=%s\n' "$plan_root"
}

@test "local-store runner smoke path resolves, selects, and scans verbatim" {
  built="$(_seed_vault local)"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"

  run cog plan runner-resolve --target "$plan_dir" --json
  assert_success
  echo "$output" | jq -e '.store == "local" and (.plan_root | endswith("/.cog/plans"))'

  # runner-all selects the plan item, prompt preserved verbatim.
  all_out="$(cog runner-all-setup --json "$plan_root/queue-plans.yaml")"
  echo "$all_out" | jq -e '.store == "local"' >/dev/null
  all_rd="$(jq -r '.run_dir' <<<"$all_out")"
  assert_file_contains "$all_rd/ctx.env" "PLAN_ROOT="
  jq -e --arg p "/runner-plan -ar @${plan_dir}/" '.selected.item == "smoke" and .selected.prompt == $p' "$all_rd/main-select.json" >/dev/null

  # runner-plan selects the round item, prompt preserved verbatim, ctx role-named.
  plan_out="$(cog runner-plan-setup --json "-ar @$plan_dir/")"
  plan_rd="$(jq -r '.run_dir' <<<"$plan_out")"
  assert_file_contains "$plan_rd/ctx.env" "PLAN_ROOT="
  assert_file_contains "$plan_rd/ctx.env" "MAIN_QUEUE_PATH="
  assert_file_contains "$plan_rd/ctx.env" "PLAN_STORE=local"
  assert_file_contains "$plan_rd/ctx.env" "PROJECT_KEY="
  jq -e --arg p "/executor-prex -ar ${plan_dir}/rounds/smoke.md" '.selected.item == "smoke" and .selected.prompt == $p' "$plan_rd/round-select.json" >/dev/null

  # boundary scan inventories both queues.
  run cog review-queue-rounds-scan --repo-root "$REPO" --main-queue "$plan_root/queue-plans.yaml" --json
  assert_success
  echo "$output" | jq -e '([.queues[].schema] | sort) == ["plans","rounds"]'
}

@test "global-store runner smoke path accepts an out-of-repo vault" {
  built="$(_seed_vault global)"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"

  run cog plan runner-resolve --target "$plan_dir" --json
  assert_success
  echo "$output" | jq -e '.store == "global" and (.plan_root | startswith("'"$XDG_DATA_HOME"'/cog/plans/projects/")) and (.project_key | test("-[0-9a-f]{16}$"))'

  # runner-plan-setup accepts an out-of-repo plan dir (previously rejected).
  plan_out="$(cog runner-plan-setup --json "-ar @$plan_dir/")"
  echo "$plan_out" | jq -e '.store == "global"' >/dev/null
  plan_rd="$(jq -r '.run_dir' <<<"$plan_out")"
  jq -e --arg p "/executor-prex -ar ${plan_dir}/rounds/smoke.md" '.selected.prompt == $p' "$plan_rd/round-select.json" >/dev/null

  all_out="$(cog runner-all-setup --json "$plan_root/queue-plans.yaml")"
  echo "$all_out" | jq -e '.store == "global"' >/dev/null

  # boundary scan succeeds (previously died in plans_fingerprint on a fresh vault).
  run cog review-queue-rounds-scan --repo-root "$REPO" --main-queue "$plan_root/queue-plans.yaml" --json
  assert_success
  echo "$output" | jq -e '.ok and ([.queues[].schema] | sort) == ["plans","rounds"]'
}
