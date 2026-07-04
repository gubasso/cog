setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"
}

# Build a fresh repo + global vault holding the alpha plan; echo REPO/PLAN_DIR/
# PLAN_ROOT/QUEUE lines. Each fixture repo has a distinct git identity so its
# global project vault is isolated.
write_verify_fixture() {
  local repo="$1" newjson plan_dir plan_root
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email a@b.c
  git -C "$repo" config user.name tester
  git -C "$repo" remote add origin "https://example.com/$(basename "$repo").git"
  printf 'source\n' >"$repo/source.txt"
  newjson="$(cog plan new --title Alpha --global --project-root "$repo" --json)"
  plan_dir="$(jq -r '.plan_dir' <<<"$newjson")"
  plan_root="$(jq -r '.plan_root' <<<"$newjson")"
  mkdir -p "$plan_dir/rounds"
  cat >"$plan_dir/queue-rounds.yaml" <<'EOF'
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
  cat >"$plan_root/queue-plans.yaml" <<EOF
plans:
  - item: alpha
    status: todo
    depends_on: []
    prompt: /runner-plan -ar @${plan_dir}/
    notes: note
EOF
  printf 'REPO=%s\n' "$repo"
  printf 'PLAN_DIR=%s\n' "$plan_dir"
  printf 'PLAN_ROOT=%s\n' "$plan_root"
  printf 'QUEUE=%s\n' "$plan_dir/queue-rounds.yaml"
}

scan_fixture() {
  local repo="$1" plan_root="$2" out="$3"
  cog review-queue-rounds-scan --repo-root "$repo" --main-queue "$plan_root/queue-plans.yaml" "$out" >/dev/null
}

verify_fixture() {
  local before="$1" after="$2"
  cog review-queue-rounds-verify --before "$before" --after "$after" --json
}

@test "review-queue-rounds-verify passes no-op" {
  built="$(write_verify_fixture "${BATS_TEST_TMPDIR}/repo")"
  repo="$(sed -n 's/^REPO=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  before="${BATS_TEST_TMPDIR}/before.json"
  after="${BATS_TEST_TMPDIR}/after.json"
  scan_fixture "$repo" "$plan_root" "$before"
  scan_fixture "$repo" "$plan_root" "$after"

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

@test "review-queue-rounds-verify reports status changes" {
  built="$(write_verify_fixture "${BATS_TEST_TMPDIR}/repo")"
  repo="$(sed -n 's/^REPO=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  queue="$(sed -n 's/^QUEUE=//p' <<<"$built")"
  before="${BATS_TEST_TMPDIR}/before.json"
  after="${BATS_TEST_TMPDIR}/after.json"
  scan_fixture "$repo" "$plan_root" "$before"
  cog queue-status-set --queue "$queue" --schema rounds --item second --from todo --to "done" --json >/dev/null
  scan_fixture "$repo" "$plan_root" "$after"

  run verify_fixture "$before" "$after"
  assert_success
  printf '%s\n' "$output" | jq -e '.changed == true and (.status_changes[] | select(.item == "second" and .from == "todo" and .to == "done"))' >/dev/null
}

@test "review-queue-rounds-verify reports new items" {
  built="$(write_verify_fixture "${BATS_TEST_TMPDIR}/repo")"
  repo="$(sed -n 's/^REPO=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  queue="$(sed -n 's/^QUEUE=//p' <<<"$built")"
  before="${BATS_TEST_TMPDIR}/before.json"
  after="${BATS_TEST_TMPDIR}/after.json"
  scan_fixture "$repo" "$plan_root" "$before"
  cog queue-append --schema rounds --queue "$queue" --item third --status todo --prompt "/executor-prex -ar third.md" --json >/dev/null
  scan_fixture "$repo" "$plan_root" "$after"

  run verify_fixture "$before" "$after"
  assert_success
  printf '%s\n' "$output" | jq -e '.changed == true and (.new_items[] | select(.item == "third" and .status == "todo"))' >/dev/null
}

@test "review-queue-rounds-verify fails on completed-history rewrites" {
  local field
  for field in prompt depends_on notes status; do
    built="$(write_verify_fixture "${BATS_TEST_TMPDIR}/repo-${field}")"
    repo="$(sed -n 's/^REPO=//p' <<<"$built")"
    plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
    queue="$(sed -n 's/^QUEUE=//p' <<<"$built")"
    before="${BATS_TEST_TMPDIR}/before-${field}.json"
    after="${BATS_TEST_TMPDIR}/after-${field}.json"
    scan_fixture "$repo" "$plan_root" "$before"
    case "$field" in
      prompt) yq e -i '(.rounds[] | select(.item == "first") | .prompt) = "/executor-prex -ar changed.md"' "$queue" ;;
      depends_on) yq e -i '(.rounds[] | select(.item == "first") | .depends_on) = ["extra"]' "$queue" ;;
      notes) yq e -i '(.rounds[] | select(.item == "first") | .notes) = "changed"' "$queue" ;;
      status) yq e -i '(.rounds[] | select(.item == "first") | .status) = "todo"' "$queue" ;;
    esac
    scan_fixture "$repo" "$plan_root" "$after"

    run verify_fixture "$before" "$after"
    assert_failure
    [[ $output == *"completed history was modified"* ]]
  done
}

@test "review-queue-rounds-verify fails on doing-history rewrites" {
  local field
  for field in prompt depends_on notes status; do
    built="$(write_verify_fixture "${BATS_TEST_TMPDIR}/repo-doing-${field}")"
    repo="$(sed -n 's/^REPO=//p' <<<"$built")"
    plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
    queue="$(sed -n 's/^QUEUE=//p' <<<"$built")"
    before="${BATS_TEST_TMPDIR}/before-doing-${field}.json"
    after="${BATS_TEST_TMPDIR}/after-doing-${field}.json"
    scan_fixture "$repo" "$plan_root" "$before"
    case "$field" in
      prompt) yq e -i '(.rounds[] | select(.item == "active") | .prompt) = "/executor-prex -ar changed.md"' "$queue" ;;
      depends_on) yq e -i '(.rounds[] | select(.item == "active") | .depends_on) = []' "$queue" ;;
      notes) yq e -i '(.rounds[] | select(.item == "active") | .notes) = "changed"' "$queue" ;;
      status) yq e -i '(.rounds[] | select(.item == "active") | .status) = "todo"' "$queue" ;;
    esac
    scan_fixture "$repo" "$plan_root" "$after"

    run verify_fixture "$before" "$after"
    assert_failure
    [[ $output == *"completed history was modified"* ]]
  done
}

@test "review-queue-rounds-verify judges the after scan, not the live queue (no TOCTOU)" {
  built="$(write_verify_fixture "${BATS_TEST_TMPDIR}/repo")"
  repo="$(sed -n 's/^REPO=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  queue="$(sed -n 's/^QUEUE=//p' <<<"$built")"
  before="${BATS_TEST_TMPDIR}/before.json"
  after="${BATS_TEST_TMPDIR}/after.json"
  scan_fixture "$repo" "$plan_root" "$before"
  scan_fixture "$repo" "$plan_root" "$after"
  yq e -i '(.rounds[] | select(.item == "second") | .depends_on) = ["missing"]' "$queue"

  run verify_fixture "$before" "$after"
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .graph_valid == true' >/dev/null
}

@test "review-queue-rounds-verify reports changed plan files" {
  built="$(write_verify_fixture "${BATS_TEST_TMPDIR}/repo")"
  repo="$(sed -n 's/^REPO=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  plan_dir="$(sed -n 's/^PLAN_DIR=//p' <<<"$built")"
  before="${BATS_TEST_TMPDIR}/before.json"
  after="${BATS_TEST_TMPDIR}/after.json"
  scan_fixture "$repo" "$plan_root" "$before"
  printf '%s\n' 'more plan text' >>"$plan_dir/README.md"
  scan_fixture "$repo" "$plan_root" "$after"

  run verify_fixture "$before" "$after"
  assert_success
  printf '%s\n' "$output" | jq -e '.changed == true and (.changed_queues | length) == 0' >/dev/null
}

@test "review-queue-rounds-verify reports dependency changes" {
  built="$(write_verify_fixture "${BATS_TEST_TMPDIR}/repo")"
  repo="$(sed -n 's/^REPO=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  queue="$(sed -n 's/^QUEUE=//p' <<<"$built")"
  before="${BATS_TEST_TMPDIR}/before.json"
  after="${BATS_TEST_TMPDIR}/after.json"
  scan_fixture "$repo" "$plan_root" "$before"
  cog queue-deps-set --queue "$queue" --schema rounds --item second --depends-on first,active --expect first --json >/dev/null
  scan_fixture "$repo" "$plan_root" "$after"

  run verify_fixture "$before" "$after"
  assert_success
  printf '%s\n' "$output" | jq -e '
    .changed == true and
    (.deps_changes[] | select(.item == "second" and .before == ["first"] and .after == ["first","active"]))
  ' >/dev/null
}

@test "review-queue-rounds-verify reports reordered queues" {
  built="$(write_verify_fixture "${BATS_TEST_TMPDIR}/repo")"
  repo="$(sed -n 's/^REPO=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  queue="$(sed -n 's/^QUEUE=//p' <<<"$built")"
  before="${BATS_TEST_TMPDIR}/before.json"
  after="${BATS_TEST_TMPDIR}/after.json"
  cog queue-append --schema rounds --queue "$queue" --item third --status todo --prompt "/executor-prex -ar third.md" --depends-on second --json >/dev/null
  scan_fixture "$repo" "$plan_root" "$before"
  yq e -i '.rounds = [.rounds[0], .rounds[1], .rounds[2], .rounds[4], .rounds[3]]' "$queue"
  scan_fixture "$repo" "$plan_root" "$after"

  run verify_fixture "$before" "$after"
  assert_success
  printf '%s\n' "$output" | jq -e '
    .changed == true and
    (.reordered[] | select(.before_order == ["extra","first","active","second","third"] and .after_order == ["extra","first","active","third","second"]))
  ' >/dev/null
}

@test "review-queue-rounds-verify fails closed on dangling dependency" {
  built="$(write_verify_fixture "${BATS_TEST_TMPDIR}/repo")"
  repo="$(sed -n 's/^REPO=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  queue="$(sed -n 's/^QUEUE=//p' <<<"$built")"
  before="${BATS_TEST_TMPDIR}/before.json"
  after="${BATS_TEST_TMPDIR}/after.json"
  scan_fixture "$repo" "$plan_root" "$before"
  yq e -i '(.rounds[] | select(.item == "second") | .depends_on) = ["missing"]' "$queue"
  scan_fixture "$repo" "$plan_root" "$after"

  run verify_fixture "$before" "$after"
  assert_failure
  [[ $output == *"queue dependency graph is invalid"* ]]
}

@test "review-queue-rounds-verify fails closed on dependency cycle" {
  built="$(write_verify_fixture "${BATS_TEST_TMPDIR}/repo")"
  repo="$(sed -n 's/^REPO=//p' <<<"$built")"
  plan_root="$(sed -n 's/^PLAN_ROOT=//p' <<<"$built")"
  queue="$(sed -n 's/^QUEUE=//p' <<<"$built")"
  before="${BATS_TEST_TMPDIR}/before.json"
  after="${BATS_TEST_TMPDIR}/after.json"
  scan_fixture "$repo" "$plan_root" "$before"
  yq e -i '(.rounds[] | select(.item == "second") | .depends_on) = ["second"]' "$queue"
  scan_fixture "$repo" "$plan_root" "$after"

  run verify_fixture "$before" "$after"
  assert_failure
  [[ $output == *"queue dependency graph is invalid"* ]]
}
