setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_scan_fixture() {
  local root="$1"
  mkdir -p "$root/.implementation-plans/plans/alpha"
  cat >"$root/.implementation-plans/queue-plans.yaml" <<'EOF'
plans:
  - item: alpha
    status: todo
    depends_on: []
    prompt: /prex -ar @.implementation-plans/plans/alpha/
    notes: note
EOF
  cat >"$root/.implementation-plans/plans/alpha/queue-rounds.yaml" <<'EOF'
repos:
  - /tmp/satellite
rounds:
  - item: first
    status: done
    depends_on: []
    prompt: /prex -ar first.md
    notes: note
  - item: second
    status: doing
    depends_on:
      - first
    prompt: /prex -ar second.md
    notes: note
  - item: third
    status: todo
    depends_on:
      - first
    prompt: /prex -ar third.md
    notes: note
  - item: fourth
    status: backlog
    depends_on: []
    prompt: /prex -ar fourth.md
    notes: note
EOF
  printf '%s\n' '# Alpha' >"$root/.implementation-plans/plans/alpha/README.md"
  printf '%s\n' 'source' >"$root/source.txt"
}

@test "review-implementation-plans-scan inventories queues mutable flags and repos co-key" {
  local root="${BATS_TEST_TMPDIR}/repo"
  write_scan_fixture "$root"

  run cog review-implementation-plans-scan --repo-root "$root" --main-queue "$root/.implementation-plans/queue-plans.yaml" --json

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

@test "review-implementation-plans-scan fails on both item-array schemas" {
  local root="${BATS_TEST_TMPDIR}/repo"
  write_scan_fixture "$root"
  cat >>"$root/.implementation-plans/plans/alpha/queue-rounds.yaml" <<'EOF'
plans: []
EOF

  run --separate-stderr cog review-implementation-plans-scan --repo-root "$root" --main-queue "$root/.implementation-plans/queue-plans.yaml" --json

  assert_failure
  [[ $stderr == *"ambiguous schema"* ]]
}

@test "review-implementation-plans-scan fails on neither item-array schema" {
  local root="${BATS_TEST_TMPDIR}/repo"
  write_scan_fixture "$root"
  cat >"$root/.implementation-plans/plans/alpha/queue-rounds.yaml" <<'EOF'
repos:
  - /tmp/satellite
EOF

  run --separate-stderr cog review-implementation-plans-scan --repo-root "$root" --main-queue "$root/.implementation-plans/queue-plans.yaml" --json

  assert_failure
  [[ $stderr == *"no supported schema"* ]]
}

@test "review-implementation-plans-scan emits stable fingerprints" {
  local root="${BATS_TEST_TMPDIR}/repo"
  local first second
  write_scan_fixture "$root"

  first="$(cog review-implementation-plans-scan --repo-root "$root" --main-queue "$root/.implementation-plans/queue-plans.yaml" --json)"
  second="$(cog review-implementation-plans-scan --repo-root "$root" --main-queue "$root/.implementation-plans/queue-plans.yaml" --json)"

  assert_equal "$(jq -r '.repo_fingerprint' <<<"$first")" "$(jq -r '.repo_fingerprint' <<<"$second")"
  assert_equal "$(jq -r '.plans_fingerprint' <<<"$first")" "$(jq -r '.plans_fingerprint' <<<"$second")"
}

@test "review-implementation-plans-scan fails closed on a nested plan directory" {
  local root="${BATS_TEST_TMPDIR}/repo"
  write_scan_fixture "$root"
  mkdir -p "$root/.implementation-plans/plans/alpha/nested"
  printf 'rounds: []\n' >"$root/.implementation-plans/plans/alpha/nested/queue-rounds.yaml"

  run --separate-stderr cog review-implementation-plans-scan --repo-root "$root" --main-queue "$root/.implementation-plans/queue-plans.yaml" --json

  assert_failure
  [[ $stderr == *"nested plan directory detected"* ]]
  [[ $stderr == *"plans/alpha/nested/queue-rounds.yaml"* ]]
}

@test "review-implementation-plans-scan --help dispatches" {
  run cog review-implementation-plans-scan --help

  assert_success
  [[ $output == *"Inventory all implementation-plan queues"* ]]
}
