setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  QUEUE="${BATS_TEST_TMPDIR}/queue-rounds.yaml"
  cat >"$QUEUE" <<'YAML'
rounds:
  - item: round-a
    status: done
    depends_on: []
    prompt: /executor-prex -ar round-a.md
    notes: ""
    artifacts:
      - type: stow
        path: /home/u/.local/overlay
  - item: round-b
    status: done
    depends_on: []
    prompt: /executor-prex -ar round-b.md
    notes: ""
  - item: round-c
    status: todo
    depends_on: []
    prompt: /executor-prex -ar round-c.md
    notes: ""
    idempotency_check:
      - type: stow
        path: /home/u/.local/overlay
  - item: round-d
    status: todo
    depends_on: []
    prompt: /executor-prex -ar round-d.md
    notes: ""
    artifacts:
      - type: stow
        path: /brand/new
YAML
}

@test "idempotency flags an artifact an earlier round already deployed" {
  run cog review-queue-rounds-check-idempotency --queue "$QUEUE" --round round-c --json
  assert_success
  printf '%s\n' "$output" | jq -e '
    .clean == false
    and (.already_deployed | length == 1)
    and (.already_deployed[0].type == "stow")
    and (.already_deployed[0].path == "/home/u/.local/overlay")
    and (.already_deployed[0].first_deployed_by == "round-a")
  ' >/dev/null
}

@test "idempotency reports a fresh artifact as clean" {
  run cog review-queue-rounds-check-idempotency --queue "$QUEUE" --round round-d --json
  assert_success
  printf '%s\n' "$output" | jq -e '.clean == true and (.already_deployed == [])' >/dev/null
}

@test "idempotency on the first round is clean (nothing earlier)" {
  run cog review-queue-rounds-check-idempotency --queue "$QUEUE" --round round-a --json
  assert_success
  printf '%s\n' "$output" | jq -e '.clean == true' >/dev/null
}

@test "idempotency fails on an unknown round" {
  run --separate-stderr cog review-queue-rounds-check-idempotency --queue "$QUEUE" --round nope --json
  assert_failure
  [[ $stderr == *"round not found"* ]]
}
