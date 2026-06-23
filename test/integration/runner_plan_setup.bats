setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  REPO_ROOT="${BATS_TEST_TMPDIR}/repo"
  export REPO_ROOT
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin" "$REPO_ROOT/.implementation-plans/plans/main"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --show-toplevel") printf '%s\n' "$REPO_ROOT" ;;
  *) printf 'unexpected git args: %s\n' "\$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
  cat >"$REPO_ROOT/.implementation-plans/plans/main/queue-rounds.yaml" <<'EOF'
rounds:
  - item: next
    status: todo
    depends_on: []
    prompt: /executor-prex -ar next.md
    notes: note
EOF
}

@test "cog runner-plan-setup writes ctx and initial round selection" {
  run cog runner-plan-setup --json "--dry-run --max=2 -ar @.implementation-plans/plans/main/"

  assert_success
  printf '%s\n' "$output" | jq -e '.dry_run == true and .max_rounds == "2" and .queue_schema == "rounds" and (.plan_dir | endswith("/.implementation-plans/plans/main"))' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "QUEUE_SCHEMA=rounds"
  assert_file_contains "${run_dir}/ctx.env" "INNER_QUEUE_PATH="
  assert_file_not_contains "${run_dir}/ctx.env" "MAIN_QUEUE_PATH="
  jq -e '.schema == "rounds" and .selected.item == "next" and .selected.prompt == "/executor-prex -ar next.md"' "${run_dir}/round-select.json" >/dev/null
}

@test "cog runner-plan-setup persists satellite repos from inner queue" {
  mkdir -p "${BATS_TEST_TMPDIR}/satellite"
  cat >"$REPO_ROOT/.implementation-plans/plans/main/queue-rounds.yaml" <<EOF
repos:
  - ${BATS_TEST_TMPDIR}/satellite
rounds:
  - item: next
    status: todo
    depends_on: []
    prompt: /executor-prex -ar next.md
    notes: note
EOF

  run cog runner-plan-setup --json "-ar @.implementation-plans/plans/main/"

  assert_success
  printf '%s\n' "$output" | jq -e --arg sat "${BATS_TEST_TMPDIR}/satellite" '.repos == [$sat]' >/dev/null
  local run_dir
  run_dir="$(printf '%s\n' "$output" | jq -r '.run_dir')"
  assert_file_contains "${run_dir}/ctx.env" "${BATS_TEST_TMPDIR}/satellite"
}

@test "cog runner-plan-setup fails closed for bad targets" {
  printf 'file target\n' >"$REPO_ROOT/file-target.md"
  run --separate-stderr cog runner-plan-setup --json "-ar @file-target.md"
  assert_failure
  [[ $stderr == *"plan target is not a directory"* ]]

  mkdir -p "$REPO_ROOT/.implementation-plans/plans/no-queue"
  run --separate-stderr cog runner-plan-setup --json "-ar @.implementation-plans/plans/no-queue"
  assert_failure
  [[ $stderr == *"plan target has no queue-rounds.yaml"* ]]

  run --separate-stderr cog runner-plan-setup --json "-ar @.implementation-plans/plans/missing"
  assert_failure
  [[ $stderr == *"plan target not found"* ]]
}

@test "cog runner-plan-setup fails closed on nested and non-canonical plan directories" {
  mkdir -p "$REPO_ROOT/.implementation-plans/plans/parent/child"
  printf 'rounds: []\n' >"$REPO_ROOT/.implementation-plans/plans/parent/child/queue-rounds.yaml"

  run --separate-stderr cog runner-plan-setup --json "-ar @.implementation-plans/plans/main"
  assert_failure
  [[ $stderr == *"nested plan directory detected"* ]]

  rm -f "$REPO_ROOT/.implementation-plans/plans/parent/child/queue-rounds.yaml"
  mkdir -p "$REPO_ROOT/other"
  printf 'rounds: []\n' >"$REPO_ROOT/other/queue-rounds.yaml"
  run --separate-stderr cog runner-plan-setup --json "-ar @other"
  assert_failure
  [[ $stderr == *"plan target must be a direct child"* ]]
}

@test "cog runner-plan-setup rejects invalid max and missing -ar target" {
  run --separate-stderr cog runner-plan-setup --json "--max 0 -ar @.implementation-plans/plans/main"
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
