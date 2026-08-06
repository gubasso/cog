setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog round-prompt --help dispatches" {
  run cog round-prompt --help
  assert_success
  [[ $output == *"round-prompt build"* ]]
}

@test "cog round-prompt build assembles a known-executor stamp" {
  run cog round-prompt build --executor executor-vetted --round-path /p/r.md --json
  assert_success
  [[ "$(jq -r '.prompt' <<<"$output")" == "/executor-vetted -ar /p/r.md" ]]
  [[ "$(jq -r '.executor' <<<"$output")" == "executor-vetted" ]]
}

@test "cog round-prompt build accepts custom flags via --args" {
  run cog round-prompt build --executor executor-prex --round-path /p/r.md --args "-a" --json
  assert_success
  [[ "$(jq -r '.prompt' <<<"$output")" == "/executor-prex -a /p/r.md" ]]
}

@test "cog round-prompt build fails closed on an unknown executor" {
  run cog round-prompt build --executor bogus --round-path /p/r.md --json
  assert_failure
  [[ $output == *"unknown executor"* ]]
}

@test "cog round-prompt build fails closed on a reserved/null executor" {
  run cog round-prompt build --executor null --round-path /p/r.md --json
  assert_failure
  [[ $output == *"reserved"* ]]
}

@test "cog round-prompt build fails closed on a missing round path" {
  run cog round-prompt build --executor executor-prex --json
  assert_failure
  [[ $output == *"missing round path"* ]]
}

@test "cog round-prompt validate accepts a legacy executor-prex stamp" {
  run cog round-prompt validate --prompt "/executor-prex -ar /plan/round.md" --json
  assert_success
  [[ "$(jq -r '.ok' <<<"$output")" == "true" ]]
  [[ "$(jq -r '.executor' <<<"$output")" == "executor-prex" ]]
}

@test "cog round-prompt validate fails an unknown executor stamp" {
  run cog round-prompt validate --prompt "/executor-bogus -ar /p.md" --json
  assert_failure
  [[ "$(jq -r '.known' <<<"$output")" == "false" ]]
}

@test "cog round-prompt validate fails a prompt missing the flag/path pair" {
  run cog round-prompt validate --prompt "/executor-prex /p.md" --json
  assert_failure
  [[ "$(jq -r '.well_formed' <<<"$output")" == "false" ]]
}

@test "cog round-prompt validate-queue passes a clean rounds queue" {
  cat >"${BATS_TEST_TMPDIR}/queue-rounds.yaml" <<'EOF'
# Rounds for this plan, in execution order. status: backlog | todo | doing | done
rounds:
  - item: setup-foo
    status: todo
    depends_on: []
    prompt: /executor-vetted -ar /plan/rounds/setup-foo.md
    notes: ""
EOF
  run cog round-prompt validate-queue --queue "${BATS_TEST_TMPDIR}/queue-rounds.yaml" --schema rounds --json
  assert_success
  [[ "$(jq -r '.ok' <<<"$output")" == "true" ]]
}

@test "cog round-prompt validate-queue fails a rounds queue with a bad executor stamp" {
  cat >"${BATS_TEST_TMPDIR}/queue-bad.yaml" <<'EOF'
# Rounds for this plan, in execution order. status: backlog | todo | doing | done
rounds:
  - item: setup-foo
    status: todo
    depends_on: []
    prompt: /executor-bogus -ar /plan/rounds/setup-foo.md
    notes: ""
EOF
  run cog round-prompt validate-queue --queue "${BATS_TEST_TMPDIR}/queue-bad.yaml" --schema rounds --json
  assert_failure
  [[ "$(jq -r '.invalid[0].reason' <<<"$output")" == *"unknown executor"* ]]
}

@test "cog round-prompt validate-queue passes a plans queue with runner-plan dispatch" {
  cat >"${BATS_TEST_TMPDIR}/queue-plans.yaml" <<'EOF'
# Source of truth for the plan-vault queue. Status & order live HERE, not in paths.
# status: backlog | todo | doing | done
plans:
  - item: my-plan
    status: todo
    depends_on: []
    prompt: /runner-plan -ar @/vault/plans/my-plan/
    notes: ""
EOF
  run cog round-prompt validate-queue --queue "${BATS_TEST_TMPDIR}/queue-plans.yaml" --schema plans --json
  assert_success
  [[ "$(jq -r '.ok' <<<"$output")" == "true" ]]
}

# ADR-0015: the plans ledger prompt must be the exact `/runner-plan -ar @<plan-dir>/`
# dispatch; malformed variants must fail the producer-side gate closed.
_write_plans_queue() {
  cat >"${BATS_TEST_TMPDIR}/queue-plans-bad.yaml" <<EOF
# Source of truth for the plan-vault queue. Status & order live HERE, not in paths.
plans:
  - item: my-plan
    status: todo
    depends_on: []
    prompt: ${1}
    notes: ""
EOF
}

@test "cog round-prompt validate-queue fails a plans prompt missing the -ar flag" {
  _write_plans_queue "/runner-plan @/vault/plans/my-plan/"
  run cog round-prompt validate-queue --queue "${BATS_TEST_TMPDIR}/queue-plans-bad.yaml" --schema plans --json
  assert_failure
  [[ "$(jq -r '.invalid[0].reason' <<<"$output")" == *"/runner-plan -ar @<plan-dir>/"* ]]
}

@test "cog round-prompt validate-queue fails a plans prompt with a wrong flag" {
  _write_plans_queue "/runner-plan --bad @/vault/plans/my-plan/"
  run cog round-prompt validate-queue --queue "${BATS_TEST_TMPDIR}/queue-plans-bad.yaml" --schema plans --json
  assert_failure
  [[ "$(jq -r '.invalid[0].reason' <<<"$output")" == *"/runner-plan -ar @<plan-dir>/"* ]]
}

@test "cog round-prompt validate-queue fails a plans prompt with an empty @ target" {
  _write_plans_queue "/runner-plan -ar @"
  run cog round-prompt validate-queue --queue "${BATS_TEST_TMPDIR}/queue-plans-bad.yaml" --schema plans --json
  assert_failure
  [[ "$(jq -r '.invalid[0].reason' <<<"$output")" == *"/runner-plan -ar @<plan-dir>/"* ]]
}
