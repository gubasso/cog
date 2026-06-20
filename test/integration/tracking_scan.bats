setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_registry() {
  local registry="$1"
  cat >"$registry" <<'EOF'
schema_version: 1
entries:
  - id: overdue-entry
    path: docs/reference/overdue.md
    last_checked: 2026-01-01
    cadence_days: 30
    owner: tests
    why: "Overdue fixture."
    revalidate_how: "Refresh the overdue fixture."
    references:
      - docs/reference/downstream.md
  - id: current-entry
    path: docs/reference/current.md
    last_checked: 2026-01-15
    cadence_days: 30
    owner: tests
    why: "Current fixture."
    revalidate_how: "Refresh the current fixture."
    references: []
EOF
}

@test "tracking-scan default output reports only overdue entries" {
  local registry="${BATS_TEST_TMPDIR}/maintenance-tracking.yaml"
  write_registry "$registry"

  run cog tracking-scan --registry "$registry" --now 2026-02-01

  assert_failure 65
  [[ $output == *"OVERDUE	id=\"overdue-entry\""* ]]
  [[ $output != *"current-entry"* ]]
}

@test "tracking-scan json output reports overdue count" {
  local registry="${BATS_TEST_TMPDIR}/maintenance-tracking.yaml"
  write_registry "$registry"

  run cog tracking-scan --registry "$registry" --now 2026-02-01 --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e '
    .schema == "cog.tracking-scan.v1" and
    .entry_count == 2 and
    .overdue_count == 1 and
    .overdue[0].id == "overdue-entry" and
    .overdue[0].due_date == "2026-01-31" and
    .overdue[0].days_overdue == 1
  ' >/dev/null
}

@test "tracking-scan succeeds when no entries are overdue" {
  local registry="${BATS_TEST_TMPDIR}/maintenance-tracking.yaml"
  write_registry "$registry"

  run cog tracking-scan --registry "$registry" --now 2026-01-20 --json

  assert_success
  printf '%s\n' "$output" | jq -e '.overdue_count == 0 and .overdue == []' >/dev/null
}

@test "tracking-scan uses COG_TRACKING_SCAN_NOW when --now is absent" {
  local registry="${BATS_TEST_TMPDIR}/maintenance-tracking.yaml"
  write_registry "$registry"

  run env COG_TRACKING_SCAN_NOW=2026-02-01 cog tracking-scan --registry "$registry" --json

  assert_failure 65
  printf '%s\n' "$output" | jq -e '.now == "2026-02-01" and .overdue_count == 1' >/dev/null
}
