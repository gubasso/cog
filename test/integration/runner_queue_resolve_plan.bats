setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  REPO_ROOT="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO_ROOT/plans/with-at" "$REPO_ROOT/plans/bare" "$REPO_ROOT/plans/no-repos" "$REPO_ROOT/plans/no-queue"
  export REPO_ROOT
  cat >"$REPO_ROOT/plans/with-at/queue-rounds.yaml" <<'EOF'
repos:
  - /tmp/satellite
rounds:
  - item: one
    status: todo
    depends_on: []
    prompt: /prex -ar one.md
    notes: note
EOF
  cat >"$REPO_ROOT/plans/bare/queue-rounds.yaml" <<'EOF'
rounds:
  - item: one
    status: todo
    depends_on: []
    prompt: /prex -ar one.md
    notes: note
EOF
  cat >"$REPO_ROOT/plans/no-repos/queue-rounds.yaml" <<'EOF'
rounds:
  - item: one
    status: todo
    depends_on: []
    prompt: /prex -ar one.md
    notes: note
EOF
  printf 'file target\n' >"$REPO_ROOT/file-target.md"
}

write_main_queue() {
  local queue="$1" prompt="$2"
  cat >"$queue" <<EOF
plans:
  - item: selected
    status: todo
    depends_on: []
    prompt: ${prompt}
    notes: note
EOF
}

@test "cog runner-queue-resolve-plan resolves @ directory and repos" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  write_main_queue "$queue" "/prex -ar @plans/with-at/"

  run cog runner-queue-resolve-plan --repo-root "$REPO_ROOT" --queue "$queue" --item selected --json

  assert_success
  printf '%s\n' "$output" | jq -e --arg root "$REPO_ROOT" \
    '.ok == true and .kind == "inner_queue" and .target_path == ($root + "/plans/with-at") and .inner_queue_path == ($root + "/plans/with-at/queue-rounds.yaml") and .repos == ["/tmp/satellite"]' >/dev/null
}

@test "cog runner-queue-resolve-plan resolves executor-prex @ directory and preserves prompt" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  write_main_queue "$queue" "/executor-prex -ar @plans/with-at/"

  run cog runner-queue-resolve-plan --repo-root "$REPO_ROOT" --queue "$queue" --item selected --json

  assert_success
  printf '%s\n' "$output" | jq -e --arg root "$REPO_ROOT" \
    '.target_path == ($root + "/plans/with-at") and .prompt == "/executor-prex -ar @plans/with-at/"' >/dev/null
}

@test "cog runner-queue-resolve-plan resolves bare directory and missing repos as empty array" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  write_main_queue "$queue" "/prex -ar plans/no-repos/"

  run cog runner-queue-resolve-plan --repo-root "$REPO_ROOT" --queue "$queue" --item selected --json

  assert_success
  printf '%s\n' "$output" | jq -e --arg root "$REPO_ROOT" \
    '.kind == "inner_queue" and .target_path == ($root + "/plans/no-repos") and .repos == []' >/dev/null
}

@test "cog runner-queue-resolve-plan fails closed for bad targets" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"

  write_main_queue "$queue" "/prex -ar file-target.md"
  run --separate-stderr cog runner-queue-resolve-plan --repo-root "$REPO_ROOT" --queue "$queue" --item selected --json
  assert_failure
  [[ $stderr == *"plan target is not a directory"* ]]

  write_main_queue "$queue" "/prex -ar plans/no-queue"
  run --separate-stderr cog runner-queue-resolve-plan --repo-root "$REPO_ROOT" --queue "$queue" --item selected --json
  assert_failure
  [[ $stderr == *"plan target has no queue-rounds.yaml"* ]]

  write_main_queue "$queue" "/prex -ar plans/missing"
  run --separate-stderr cog runner-queue-resolve-plan --repo-root "$REPO_ROOT" --queue "$queue" --item selected --json
  assert_failure
  [[ $stderr == *"plan target not found"* ]]
}

@test "cog runner-queue-resolve-plan fails closed on a nested plan directory" {
  local repo="${BATS_TEST_TMPDIR}/nested-repo"
  mkdir -p "$repo/.implementation-plans/plans/good" "$repo/.implementation-plans/plans/parent/child"
  printf 'rounds: []\n' >"$repo/.implementation-plans/plans/good/queue-rounds.yaml"
  printf 'rounds: []\n' >"$repo/.implementation-plans/plans/parent/child/queue-rounds.yaml"
  local queue="$repo/.implementation-plans/queue-plans.yaml"
  write_main_queue "$queue" "/prex -ar @.implementation-plans/plans/good/"

  run --separate-stderr cog runner-queue-resolve-plan --repo-root "$repo" --queue "$queue" --item selected --json

  assert_failure
  [[ $stderr == *"nested plan directory detected"* ]]
}

@test "cog runner-queue-resolve-plan resolves a flat canonical plan" {
  local repo="${BATS_TEST_TMPDIR}/flat-repo"
  mkdir -p "$repo/.implementation-plans/plans/good"
  printf 'rounds: []\n' >"$repo/.implementation-plans/plans/good/queue-rounds.yaml"
  local queue="$repo/.implementation-plans/queue-plans.yaml"
  write_main_queue "$queue" "/prex -ar @.implementation-plans/plans/good/"

  run cog runner-queue-resolve-plan --repo-root "$repo" --queue "$queue" --item selected --json

  assert_success
  printf '%s\n' "$output" | jq -e --arg root "$repo" \
    '.kind == "inner_queue" and .target_path == ($root + "/.implementation-plans/plans/good")' >/dev/null
}

@test "cog runner-queue-resolve-plan fails closed for unsupported missing and duplicate items" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"

  write_main_queue "$queue" "/other -ar plans/bare"
  run --separate-stderr cog runner-queue-resolve-plan --repo-root "$REPO_ROOT" --queue "$queue" --item selected --json
  assert_failure
  [[ $stderr == *"unsupported plan prompt"* ]]

  write_main_queue "$queue" "/prex -ar plans/bare"
  run --separate-stderr cog runner-queue-resolve-plan --repo-root "$REPO_ROOT" --queue "$queue" --item missing --json
  assert_failure
  [[ $stderr == *"main queue item not found"* ]]

  cat >"$queue" <<'EOF'
plans:
  - item: same
    status: todo
    depends_on: []
    prompt: /prex -ar plans/bare
    notes: note
  - item: same
    status: todo
    depends_on: []
    prompt: /prex -ar plans/bare
    notes: note
EOF
  run --separate-stderr cog runner-queue-resolve-plan --repo-root "$REPO_ROOT" --queue "$queue" --item same --json
  assert_failure
  [[ $stderr == *"duplicate queue items"* ]]
}
