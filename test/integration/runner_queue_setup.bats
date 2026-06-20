setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin" "${BATS_TEST_TMPDIR}/repo/plan"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --show-toplevel") printf '%s\n' "${BATS_TEST_TMPDIR}/repo" ;;
  *) printf 'unexpected git args: %s\n' "\$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
  cat >"${BATS_TEST_TMPDIR}/repo/plan/queue-rounds.yaml" <<'EOF'
rounds:
  - item: next
    status: todo
    depends_on: []
    prompt: /executor-prex -ar next.md
    notes: note
EOF
}

@test "cog runner-queue-setup writes ctx and initial queue selection" {
  run cog runner-queue-setup --json "--dry-run --max=3 plan"

  assert_success
  printf '%s\n' "$output" | jq -e '.dry_run == true and .max_rounds == "3" and .queue_schema == "rounds" and (.queue_path | endswith("/plan/queue-rounds.yaml"))' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "QUEUE_SCHEMA=rounds"
  assert_file_not_contains "${run_dir}/ctx.env" "MAIN_QUEUE_PATH="
  assert_file_contains "${run_dir}/ctx.env" "DRY_RUN=1"
  jq -e '.schema == "rounds" and .selected.item == "next"' "${run_dir}/queue-select.json" >/dev/null
}

@test "cog runner-queue-setup persists satellite repos from queue" {
  mkdir -p "${BATS_TEST_TMPDIR}/satellite"
  cat >"${BATS_TEST_TMPDIR}/repo/plan/queue-rounds.yaml" <<EOF
repos:
  - ${BATS_TEST_TMPDIR}/satellite
rounds:
  - item: next
    status: todo
    depends_on: []
    prompt: /executor-prex -ar next.md
    notes: note
EOF

  run cog runner-queue-setup --json "plan"

  assert_success
  printf '%s\n' "$output" | jq -e --arg sat "${BATS_TEST_TMPDIR}/satellite" '.repos == [$sat]' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "REPOS="
  assert_file_contains "${run_dir}/ctx.env" "${BATS_TEST_TMPDIR}/satellite"
}

@test "cog runner-queue-setup accepts plans queue file and persists main queue context" {
  mkdir -p "${BATS_TEST_TMPDIR}/repo/plans/main"
  cat >"${BATS_TEST_TMPDIR}/repo/plans/main/queue-rounds.yaml" <<'EOF'
rounds:
  - item: inner
    status: todo
    depends_on: []
    prompt: /executor-prex -ar inner.md
    notes: note
EOF
  cat >"${BATS_TEST_TMPDIR}/repo/queue-plans.yaml" <<'EOF'
plans:
  - item: main
    status: todo
    depends_on: []
    prompt: /executor-prex -ar @plans/main/
    notes: note
EOF

  run cog runner-queue-setup --json "queue-plans.yaml"

  assert_success
  printf '%s\n' "$output" | jq -e '.queue_schema == "plans" and (.queue_path | endswith("/repo/queue-plans.yaml")) and (.main_queue_path | endswith("/repo/queue-plans.yaml"))' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "QUEUE_SCHEMA=plans"
  assert_file_contains "${run_dir}/ctx.env" "MAIN_QUEUE_PATH="
  jq -e '.schema == "plans" and .selected.item == "main"' "${run_dir}/queue-select.json" >/dev/null
}

@test "cog runner-queue-setup rejects both or neither schema" {
  cat >"${BATS_TEST_TMPDIR}/repo/both.yaml" <<'EOF'
plans: []
rounds: []
EOF
  run --separate-stderr cog runner-queue-setup --json "both.yaml"
  assert_failure
  [[ $stderr == *"queue file has neither/both top-level schema"* ]]

  cat >"${BATS_TEST_TMPDIR}/repo/neither.yaml" <<'EOF'
repos: []
EOF
  run --separate-stderr cog runner-queue-setup --json "neither.yaml"
  assert_failure
  [[ $stderr == *"queue file has neither/both top-level schema"* ]]
}

@test "cog runner-queue-setup rejects invalid max and missing target" {
  run --separate-stderr cog runner-queue-setup --json "--max 0 plan"
  assert_failure 2
  [[ $stderr == *"invalid max rounds"* ]]

  run --separate-stderr cog runner-queue-setup --json "--dry-run"
  assert_failure 2
  [[ $stderr == *"missing plan queue target"* ]]
}

@test "cog runner-queue-setup --help dispatches" {
  run cog runner-queue-setup --help

  assert_success
  [[ $output == *"Parse runner-queue"* ]]
}
