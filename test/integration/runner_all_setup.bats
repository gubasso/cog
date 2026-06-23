setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin" "${BATS_TEST_TMPDIR}/repo"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --show-toplevel") printf '%s\n' "${BATS_TEST_TMPDIR}/repo" ;;
  *) printf 'unexpected git args: %s\n' "\$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
  cat >"${BATS_TEST_TMPDIR}/repo/queue-plans.yaml" <<'EOF'
plans:
  - item: main
    status: todo
    depends_on: []
    prompt: /runner-plan -ar @.implementation-plans/plans/main/
    notes: note
EOF
}

@test "cog runner-all-setup writes ctx and preserves selected prompt verbatim" {
  run cog runner-all-setup --json "--dry-run --max=3 queue-plans.yaml"

  assert_success
  printf '%s\n' "$output" | jq -e '.dry_run == true and .max_plans == "3" and .queue_schema == "plans" and (.queue_path | endswith("/repo/queue-plans.yaml"))' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "QUEUE_SCHEMA=plans"
  assert_file_contains "${run_dir}/ctx.env" "MAIN_QUEUE_PATH="
  assert_file_contains "${run_dir}/ctx.env" "MAX_PLANS=3"
  jq -e '.schema == "plans" and .selected.item == "main" and .selected.prompt == "/runner-plan -ar @.implementation-plans/plans/main/"' "${run_dir}/main-select.json" >/dev/null
}

@test "cog runner-all-setup persists satellite repos from main queue" {
  mkdir -p "${BATS_TEST_TMPDIR}/satellite"
  cat >"${BATS_TEST_TMPDIR}/repo/queue-plans.yaml" <<EOF
repos:
  - ${BATS_TEST_TMPDIR}/satellite
plans:
  - item: main
    status: todo
    depends_on: []
    prompt: /runner-plan -ar @.implementation-plans/plans/main/
    notes: note
EOF

  run cog runner-all-setup --json "queue-plans.yaml"

  assert_success
  printf '%s\n' "$output" | jq -e --arg sat "${BATS_TEST_TMPDIR}/satellite" '.repos == [$sat]' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "REPOS="
  assert_file_contains "${run_dir}/ctx.env" "${BATS_TEST_TMPDIR}/satellite"
}

@test "cog runner-all-setup rejects rounds and ambiguous schemas" {
  cat >"${BATS_TEST_TMPDIR}/repo/rounds.yaml" <<'EOF'
rounds: []
EOF
  run --separate-stderr cog runner-all-setup --json "rounds.yaml"
  assert_failure
  [[ $stderr == *"main queue must have plans schema only"* ]]

  cat >"${BATS_TEST_TMPDIR}/repo/both.yaml" <<'EOF'
plans: []
rounds: []
EOF
  run --separate-stderr cog runner-all-setup --json "both.yaml"
  assert_failure
  [[ $stderr == *"main queue must have plans schema only"* ]]
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
