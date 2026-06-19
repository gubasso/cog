setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_verify_fixture() {
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
rounds:
  - item: first
    status: done
    depends_on: []
    prompt: /prex -ar first.md
    notes: note
  - item: second
    status: todo
    depends_on:
      - first
    prompt: /prex -ar second.md
    notes: note
EOF
  printf '%s\n' '# Alpha' >"$root/.implementation-plans/plans/alpha/README.md"
  printf '%s\n' 'source' >"$root/source.txt"
}

scan_fixture() {
  local root="$1" out="$2"
  cog plans-revision-scan --repo-root "$root" --main-queue "$root/.implementation-plans/queue-plans.yaml" "$out" >/dev/null
}

verify_fixture() {
  local before="$1" after="$2"
  cog plans-revision-verify --before "$before" --after "$after" --json
}

@test "plans-revision-verify passes no-op" {
  local root="${BATS_TEST_TMPDIR}/repo"
  local before="${BATS_TEST_TMPDIR}/before.json"
  local after="${BATS_TEST_TMPDIR}/after.json"
  write_verify_fixture "$root"
  scan_fixture "$root" "$before"
  scan_fixture "$root" "$after"

  run verify_fixture "$before" "$after"

  assert_success
  printf '%s\n' "$output" | jq -e '.changed == false and .completed_history_preserved == true and (.new_items | length) == 0 and (.status_changes | length) == 0' >/dev/null
}

@test "plans-revision-verify reports status changes" {
  local root="${BATS_TEST_TMPDIR}/repo"
  local before="${BATS_TEST_TMPDIR}/before.json"
  local after="${BATS_TEST_TMPDIR}/after.json"
  write_verify_fixture "$root"
  scan_fixture "$root" "$before"
  cog queue-status-set --queue "$root/.implementation-plans/plans/alpha/queue-rounds.yaml" --schema rounds --item second --from todo --to "done" --json >/dev/null
  scan_fixture "$root" "$after"

  run verify_fixture "$before" "$after"

  assert_success
  printf '%s\n' "$output" | jq -e '.changed == true and (.status_changes[] | select(.item == "second" and .from == "todo" and .to == "done"))' >/dev/null
}

@test "plans-revision-verify reports new items" {
  local root="${BATS_TEST_TMPDIR}/repo"
  local before="${BATS_TEST_TMPDIR}/before.json"
  local after="${BATS_TEST_TMPDIR}/after.json"
  write_verify_fixture "$root"
  scan_fixture "$root" "$before"
  cog queue-append --schema rounds --queue "$root/.implementation-plans/plans/alpha/queue-rounds.yaml" --item third --status todo --prompt "/prex -ar third.md" --json >/dev/null
  scan_fixture "$root" "$after"

  run verify_fixture "$before" "$after"

  assert_success
  printf '%s\n' "$output" | jq -e '.changed == true and (.new_items[] | select(.item == "third" and .status == "todo"))' >/dev/null
}

@test "plans-revision-verify fails on completed-history rewrites" {
  local field root before after queue
  for field in prompt depends_on notes status; do
    root="${BATS_TEST_TMPDIR}/repo-${field}"
    before="${BATS_TEST_TMPDIR}/before-${field}.json"
    after="${BATS_TEST_TMPDIR}/after-${field}.json"
    write_verify_fixture "$root"
    queue="$root/.implementation-plans/plans/alpha/queue-rounds.yaml"
    scan_fixture "$root" "$before"
    case "$field" in
      prompt) yq e -i '(.rounds[] | select(.item == "first") | .prompt) = "/prex -ar changed.md"' "$queue" ;;
      depends_on) yq e -i '(.rounds[] | select(.item == "first") | .depends_on) = ["other"]' "$queue" ;;
      notes) yq e -i '(.rounds[] | select(.item == "first") | .notes) = "changed"' "$queue" ;;
      status) yq e -i '(.rounds[] | select(.item == "first") | .status) = "todo"' "$queue" ;;
    esac
    scan_fixture "$root" "$after"

    run verify_fixture "$before" "$after"

    assert_failure
    [[ $output == *"completed history was modified"* ]]
  done
}

@test "plans-revision-verify fails on invalid after queue" {
  local root="${BATS_TEST_TMPDIR}/repo"
  local before="${BATS_TEST_TMPDIR}/before.json"
  local after="${BATS_TEST_TMPDIR}/after.json"
  local queue
  write_verify_fixture "$root"
  queue="$root/.implementation-plans/plans/alpha/queue-rounds.yaml"
  scan_fixture "$root" "$before"
  scan_fixture "$root" "$after"
  yq e -i 'del(.rounds[0].prompt)' "$queue"

  run verify_fixture "$before" "$after"

  assert_failure
  [[ $output == *"invalid queue entries"* ]]
}

@test "plans-revision-verify reports changed plan files" {
  local root="${BATS_TEST_TMPDIR}/repo"
  local before="${BATS_TEST_TMPDIR}/before.json"
  local after="${BATS_TEST_TMPDIR}/after.json"
  write_verify_fixture "$root"
  scan_fixture "$root" "$before"
  printf '%s\n' 'more plan text' >>"$root/.implementation-plans/plans/alpha/README.md"
  scan_fixture "$root" "$after"

  run verify_fixture "$before" "$after"

  assert_success
  printf '%s\n' "$output" | jq -e '.changed == true and (.changed_queues | length) == 0' >/dev/null
}
