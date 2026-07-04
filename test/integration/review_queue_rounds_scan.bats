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
  export REPO
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email a@b.c
  git -C "$REPO" config user.name tester
  git -C "$REPO" remote add origin https://example.com/repo.git
  printf 'source\n' >"$REPO/source.txt"
}

# Build an alpha plan in the given store with a mixed-status rounds queue and
# round bodies under plans/alpha/rounds/. Echoes PLAN_DIR and PLAN_ROOT lines.
_build_vault() {
  local store="$1" newjson plan_dir plan_root
  [[ $store == local ]] && "$COG_BIN" plan trust --project-root "$REPO" --json >/dev/null
  newjson="$("$COG_BIN" plan new --title Alpha --"$store" --project-root "$REPO" --json)"
  plan_dir="$(jq -r '.plan_dir' <<<"$newjson")"
  plan_root="$(jq -r '.plan_root' <<<"$newjson")"
  mkdir -p "$plan_dir/rounds"
  printf '# first\n' >"$plan_dir/rounds/first.md"
  printf '# second\n' >"$plan_dir/rounds/second.md"
  printf '# third\n' >"$plan_dir/rounds/third.md"
  printf '# fourth\n' >"$plan_dir/rounds/fourth.md"
  cat >"$plan_dir/queue-rounds.yaml" <<EOF
repos:
  - /tmp/satellite
rounds:
  - item: first
    status: done
    depends_on: []
    prompt: /executor-prex -ar ${plan_dir}/rounds/first.md
    notes: note
  - item: second
    status: doing
    depends_on:
      - first
    prompt: /executor-prex -ar ${plan_dir}/rounds/second.md
    notes: note
  - item: third
    status: todo
    depends_on:
      - first
    prompt: /executor-prex -ar ${plan_dir}/rounds/third.md
    notes: note
  - item: fourth
    status: backlog
    depends_on: []
    prompt: /executor-prex -ar ${plan_dir}/rounds/fourth.md
    notes: note
EOF
  cat >"$plan_root/queue-plans.yaml" <<EOF
plans:
  - item: alpha
    status: todo
    depends_on: []
    prompt: /runner-plan -ar @${plan_dir}/
    notes: note
EOF
  printf 'PLAN_DIR=%s\n' "$plan_dir"
  printf 'PLAN_ROOT=%s\n' "$plan_root"
}

@test "review-queue-rounds-scan inventories a global vault: mutable flags and queue co-key" {
  built="$(_build_vault global)"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"

  run "$COG_BIN" review-queue-rounds-scan --repo-root "$REPO" --main-queue "$plan_root/queue-plans.yaml" --json
  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true and
    (.queues | length) == 2 and
    ([.queues[].schema] | sort) == ["plans","rounds"] and
    ([.queues[].path | startswith("/")] | all) and
    ([.queues[].items[] | select(.item == "first" or .item == "second") | .mutable] | all(. == false)) and
    ([.queues[].items[] | select(.item == "alpha" or .item == "third" or .item == "fourth") | .mutable] | all(. == true)) and
    (.queues[] | select(.schema == "rounds") | .items[0].queue_path == .path) and
    (.repo_fingerprint | test("^[0-9a-f]{64}$")) and
    (.plans_fingerprint | test("^[0-9a-f]{64}$"))
  ' >/dev/null
}

@test "review-queue-rounds-scan inventories a local vault and honors --plan-root" {
  built="$(_build_vault local)"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"

  run "$COG_BIN" review-queue-rounds-scan --repo-root "$REPO" --main-queue "$plan_root/queue-plans.yaml" --plan-root "$plan_root" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.ok and ([.queues[].schema] | sort) == ["plans","rounds"]' >/dev/null
}

@test "review-queue-rounds-scan rejects a --plan-root that mismatches the resolved vault" {
  # Regression: a --plan-root belonging to a different vault than --main-queue must
  # fail closed rather than mix one vault's queue with another's fingerprints.
  built="$(_build_vault global)"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  mkdir -p "$BATS_TEST_TMPDIR/other-vault/plans"

  run --separate-stderr "$COG_BIN" review-queue-rounds-scan --repo-root "$REPO" --main-queue "$plan_root/queue-plans.yaml" --plan-root "$BATS_TEST_TMPDIR/other-vault" --json
  assert_failure
  [[ $stderr == *"does not match the resolved plan vault"* ]]
}

@test "review-queue-rounds-scan fails on both item-array schemas" {
  built="$(_build_vault global)"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  printf 'plans: []\n' >>"$plan_dir/queue-rounds.yaml"

  run --separate-stderr "$COG_BIN" review-queue-rounds-scan --repo-root "$REPO" --main-queue "$plan_root/queue-plans.yaml" --json
  assert_failure
  [[ $stderr == *"ambiguous schema"* ]]
}

@test "review-queue-rounds-scan fails on neither item-array schema" {
  built="$(_build_vault global)"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  printf 'repos:\n  - /tmp/satellite\n' >"$plan_dir/queue-rounds.yaml"

  run --separate-stderr "$COG_BIN" review-queue-rounds-scan --repo-root "$REPO" --main-queue "$plan_root/queue-plans.yaml" --json
  assert_failure
  [[ $stderr == *"no supported schema"* ]]
}

@test "review-queue-rounds-scan emits stable fingerprints" {
  built="$(_build_vault global)"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  first="$("$COG_BIN" review-queue-rounds-scan --repo-root "$REPO" --main-queue "$plan_root/queue-plans.yaml" --json)"
  second="$("$COG_BIN" review-queue-rounds-scan --repo-root "$REPO" --main-queue "$plan_root/queue-plans.yaml" --json)"
  assert_equal "$(jq -r '.repo_fingerprint' <<<"$first")" "$(jq -r '.repo_fingerprint' <<<"$second")"
  assert_equal "$(jq -r '.plans_fingerprint' <<<"$first")" "$(jq -r '.plans_fingerprint' <<<"$second")"
}

@test "review-queue-rounds-scan repo fingerprint is stable under a local .cog/plans edit; plan fingerprint tracks round-body edits" {
  built="$(_build_vault local)"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  before="$("$COG_BIN" review-queue-rounds-scan --repo-root "$REPO" --main-queue "$plan_root/queue-plans.yaml" --json)"

  # Edit a round body inside the local vault.
  printf '# first (edited)\n' >"$plan_dir/rounds/first.md"
  after="$("$COG_BIN" review-queue-rounds-scan --repo-root "$REPO" --main-queue "$plan_root/queue-plans.yaml" --json)"

  # The repo source fingerprint ignores the in-repo .cog/plans vault.
  assert_equal "$(jq -r '.repo_fingerprint' <<<"$before")" "$(jq -r '.repo_fingerprint' <<<"$after")"
  # The plan fingerprint changes when a round body changes.
  [[ "$(jq -r '.plans_fingerprint' <<<"$before")" != "$(jq -r '.plans_fingerprint' <<<"$after")" ]]
}

@test "review-queue-rounds-scan fails closed on a nested plan directory" {
  built="$(_build_vault global)"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  mkdir -p "$plan_dir/nested"
  printf 'rounds: []\n' >"$plan_dir/nested/queue-rounds.yaml"

  run --separate-stderr "$COG_BIN" review-queue-rounds-scan --repo-root "$REPO" --main-queue "$plan_root/queue-plans.yaml" --json
  assert_failure
  [[ $stderr == *"nested plan directory detected"* ]]
}

@test "review-queue-rounds-scan --help dispatches" {
  run "$COG_BIN" review-queue-rounds-scan --help
  assert_success
  [[ $output == *"Inventory all plan-vault queues"* ]]
}
