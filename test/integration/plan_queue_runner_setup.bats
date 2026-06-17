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
  cat >"${BATS_TEST_TMPDIR}/repo/plan/QUEUE.yaml" <<'EOF'
rounds:
  - item: next
    status: todo
    depends_on: []
    prompt: /prex -ar next.md
    notes: note
EOF
}

@test "cog plan-queue-runner-setup writes ctx and initial queue selection" {
  run cog plan-queue-runner-setup --json "--dry-run --max=3 plan"

  assert_success
  printf '%s\n' "$output" | jq -e '.dry_run == true and .max_rounds == "3" and (.queue_path | endswith("/plan/QUEUE.yaml"))' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "DRY_RUN=1"
  jq -e '.selected.item == "next"' "${run_dir}/queue-select.json" >/dev/null
}

@test "cog plan-queue-runner-setup persists satellite repos from queue" {
  mkdir -p "${BATS_TEST_TMPDIR}/satellite"
  cat >"${BATS_TEST_TMPDIR}/repo/plan/QUEUE.yaml" <<EOF
repos:
  - ${BATS_TEST_TMPDIR}/satellite
rounds:
  - item: next
    status: todo
    depends_on: []
    prompt: /prex -ar next.md
    notes: note
EOF

  run cog plan-queue-runner-setup --json "plan"

  assert_success
  printf '%s\n' "$output" | jq -e --arg sat "${BATS_TEST_TMPDIR}/satellite" '.repos == [$sat]' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "REPOS="
  assert_file_contains "${run_dir}/ctx.env" "${BATS_TEST_TMPDIR}/satellite"
}

@test "cog plan-queue-runner-setup rejects invalid max and missing target" {
  run --separate-stderr cog plan-queue-runner-setup --json "--max 0 plan"
  assert_failure 2
  [[ $stderr == *"invalid max rounds"* ]]

  run --separate-stderr cog plan-queue-runner-setup --json "--dry-run"
  assert_failure 2
  [[ $stderr == *"missing plan queue target"* ]]
}

@test "cog plan-queue-runner-setup --help dispatches" {
  run cog plan-queue-runner-setup --help

  assert_success
  [[ $output == *"Parse plan-queue-runner"* ]]
}
