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
    prompt: /executor-prex -ar @.implementation-plans/plans/alpha/
    notes: note
EOF
  cat >"$root/.implementation-plans/plans/alpha/queue-rounds.yaml" <<'EOF'
rounds:
  - item: extra
    status: done
    depends_on: []
    prompt: /executor-prex -ar extra.md
    notes: note
  - item: first
    status: done
    depends_on: []
    prompt: /executor-prex -ar first.md
    notes: note
  - item: active
    status: doing
    depends_on:
      - first
    prompt: /executor-prex -ar active.md
    notes: note
  - item: second
    status: todo
    depends_on:
      - first
    prompt: /executor-prex -ar second.md
    notes: note
EOF
  printf '%s\n' '# Alpha' >"$root/.implementation-plans/plans/alpha/README.md"
  printf '%s\n' 'source' >"$root/source.txt"
}

scan_fixture() {
  local root="$1" out="$2"
  cog review-implementation-plans-scan --repo-root "$root" --main-queue "$root/.implementation-plans/queue-plans.yaml" "$out" >/dev/null
}

verify_fixture() {
  local before="$1" after="$2"
  cog review-implementation-plans-verify --before "$before" --after "$after" --json
}

@test "review-implementation-plans-verify passes no-op" {
  local root="${BATS_TEST_TMPDIR}/repo"
  local before="${BATS_TEST_TMPDIR}/before.json"
  local after="${BATS_TEST_TMPDIR}/after.json"
  write_verify_fixture "$root"
  scan_fixture "$root" "$before"
  scan_fixture "$root" "$after"

  run verify_fixture "$before" "$after"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .changed == false and
    .completed_history_preserved == true and
    .graph_valid == true and
    (.new_items | length) == 0 and
    (.status_changes | length) == 0 and
    (.deps_changes | length) == 0 and
    (.reordered | length) == 0
  ' >/dev/null
}

@test "review-implementation-plans-verify reports status changes" {
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

@test "review-implementation-plans-verify reports new items" {
  local root="${BATS_TEST_TMPDIR}/repo"
  local before="${BATS_TEST_TMPDIR}/before.json"
  local after="${BATS_TEST_TMPDIR}/after.json"
  write_verify_fixture "$root"
  scan_fixture "$root" "$before"
  cog queue-append --schema rounds --queue "$root/.implementation-plans/plans/alpha/queue-rounds.yaml" --item third --status todo --prompt "/executor-prex -ar third.md" --json >/dev/null
  scan_fixture "$root" "$after"

  run verify_fixture "$before" "$after"

  assert_success
  printf '%s\n' "$output" | jq -e '.changed == true and (.new_items[] | select(.item == "third" and .status == "todo"))' >/dev/null
}

@test "review-implementation-plans-verify fails on completed-history rewrites" {
  local field root before after queue
  for field in prompt depends_on notes status; do
    root="${BATS_TEST_TMPDIR}/repo-${field}"
    before="${BATS_TEST_TMPDIR}/before-${field}.json"
    after="${BATS_TEST_TMPDIR}/after-${field}.json"
    write_verify_fixture "$root"
    queue="$root/.implementation-plans/plans/alpha/queue-rounds.yaml"
    scan_fixture "$root" "$before"
    case "$field" in
      prompt) yq e -i '(.rounds[] | select(.item == "first") | .prompt) = "/executor-prex -ar changed.md"' "$queue" ;;
      depends_on) yq e -i '(.rounds[] | select(.item == "first") | .depends_on) = ["extra"]' "$queue" ;;
      notes) yq e -i '(.rounds[] | select(.item == "first") | .notes) = "changed"' "$queue" ;;
      status) yq e -i '(.rounds[] | select(.item == "first") | .status) = "todo"' "$queue" ;;
    esac
    scan_fixture "$root" "$after"

    run verify_fixture "$before" "$after"

    assert_failure
    [[ $output == *"completed history was modified"* ]]
  done
}

@test "review-implementation-plans-verify fails on doing-history rewrites" {
  local field root before after queue
  for field in prompt depends_on notes status; do
    root="${BATS_TEST_TMPDIR}/repo-doing-${field}"
    before="${BATS_TEST_TMPDIR}/before-doing-${field}.json"
    after="${BATS_TEST_TMPDIR}/after-doing-${field}.json"
    write_verify_fixture "$root"
    queue="$root/.implementation-plans/plans/alpha/queue-rounds.yaml"
    scan_fixture "$root" "$before"
    case "$field" in
      prompt) yq e -i '(.rounds[] | select(.item == "active") | .prompt) = "/executor-prex -ar changed.md"' "$queue" ;;
      depends_on) yq e -i '(.rounds[] | select(.item == "active") | .depends_on) = []' "$queue" ;;
      notes) yq e -i '(.rounds[] | select(.item == "active") | .notes) = "changed"' "$queue" ;;
      status) yq e -i '(.rounds[] | select(.item == "active") | .status) = "todo"' "$queue" ;;
    esac
    scan_fixture "$root" "$after"

    run verify_fixture "$before" "$after"

    assert_failure
    [[ $output == *"completed history was modified"* ]]
  done
}

@test "review-implementation-plans-verify judges the after scan, not the live queue (no TOCTOU)" {
  # The gate must verify the captured after-scan contents, not re-read live queue
  # files. Mutating the live file after the scan must NOT change the verdict.
  local root="${BATS_TEST_TMPDIR}/repo"
  local before="${BATS_TEST_TMPDIR}/before.json"
  local after="${BATS_TEST_TMPDIR}/after.json"
  local queue
  write_verify_fixture "$root"
  queue="$root/.implementation-plans/plans/alpha/queue-rounds.yaml"
  scan_fixture "$root" "$before"
  scan_fixture "$root" "$after"
  # Introduce a dangling dependency in the live file AFTER the after scan was taken.
  yq e -i '(.rounds[] | select(.item == "second") | .depends_on) = ["missing"]' "$queue"

  run verify_fixture "$before" "$after"

  # Scan-based gate: the captured after scan is clean, so verify passes despite the
  # drifted live file.
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .graph_valid == true' >/dev/null
}

@test "review-implementation-plans-verify reports changed plan files" {
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

@test "review-implementation-plans-verify reports dependency changes" {
  local root="${BATS_TEST_TMPDIR}/repo"
  local before="${BATS_TEST_TMPDIR}/before.json"
  local after="${BATS_TEST_TMPDIR}/after.json"
  local queue
  write_verify_fixture "$root"
  queue="$root/.implementation-plans/plans/alpha/queue-rounds.yaml"
  scan_fixture "$root" "$before"
  cog queue-deps-set --queue "$queue" --schema rounds --item second --depends-on first,active --expect first --json >/dev/null
  scan_fixture "$root" "$after"

  run verify_fixture "$before" "$after"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .changed == true and
    (.deps_changes[] | select(.item == "second" and .before == ["first"] and .after == ["first","active"]))
  ' >/dev/null
}

@test "review-implementation-plans-verify reports reordered queues" {
  local root="${BATS_TEST_TMPDIR}/repo"
  local before="${BATS_TEST_TMPDIR}/before.json"
  local after="${BATS_TEST_TMPDIR}/after.json"
  local queue
  write_verify_fixture "$root"
  queue="$root/.implementation-plans/plans/alpha/queue-rounds.yaml"
  cog queue-append --schema rounds --queue "$queue" --item third --status todo --prompt "/executor-prex -ar third.md" --depends-on second --json >/dev/null
  scan_fixture "$root" "$before"
  yq e -i '.rounds = [.rounds[0], .rounds[1], .rounds[2], .rounds[4], .rounds[3]]' "$queue"
  scan_fixture "$root" "$after"

  run verify_fixture "$before" "$after"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .changed == true and
    (.reordered[] | select(.before_order == ["extra","first","active","second","third"] and .after_order == ["extra","first","active","third","second"]))
  ' >/dev/null
}

@test "review-implementation-plans-verify fails closed on dangling dependency" {
  local root="${BATS_TEST_TMPDIR}/repo"
  local before="${BATS_TEST_TMPDIR}/before.json"
  local after="${BATS_TEST_TMPDIR}/after.json"
  local queue
  write_verify_fixture "$root"
  queue="$root/.implementation-plans/plans/alpha/queue-rounds.yaml"
  scan_fixture "$root" "$before"
  yq e -i '(.rounds[] | select(.item == "second") | .depends_on) = ["missing"]' "$queue"
  scan_fixture "$root" "$after"

  run verify_fixture "$before" "$after"

  assert_failure
  [[ $output == *"queue dependency graph is invalid"* ]]
}

@test "review-implementation-plans-verify fails closed on dependency cycle" {
  local root="${BATS_TEST_TMPDIR}/repo"
  local before="${BATS_TEST_TMPDIR}/before.json"
  local after="${BATS_TEST_TMPDIR}/after.json"
  local queue
  write_verify_fixture "$root"
  queue="$root/.implementation-plans/plans/alpha/queue-rounds.yaml"
  scan_fixture "$root" "$before"
  yq e -i '(.rounds[] | select(.item == "second") | .depends_on) = ["second"]' "$queue"
  scan_fixture "$root" "$after"

  run verify_fixture "$before" "$after"

  assert_failure
  [[ $output == *"queue dependency graph is invalid"* ]]
}
