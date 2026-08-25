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
