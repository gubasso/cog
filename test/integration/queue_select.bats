setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

write_queue() {
  local queue="$1"
  cat >"$queue" <<'EOF'
rounds:
  - item: first
    status: done
    depends_on: []
    prompt: /prex -ar first.md
    notes: note
  - item: second
    status: todo
    depends_on: [first]
    prompt: /prex -ar second.md
    notes: note
EOF
}

write_plans_queue() {
  local queue="$1"
  cat >"$queue" <<'EOF'
plans:
  - item: first-plan
    status: done
    depends_on: []
    prompt: /prex -ar @plans/first-plan/
    notes: note
  - item: second-plan
    status: todo
    depends_on: [first-plan]
    prompt: /prex -ar @plans/second-plan/
    notes: note
EOF
}

@test "cog queue-select selects next runnable round" {
  local queue="${BATS_TEST_TMPDIR}/queue-rounds.yaml"
  write_queue "$queue"

  run cog queue-select --queue "$queue" --no-clean-check --json

  assert_success
  printf '%s\n' "$output" | jq -e '.schema == "rounds" and .state == "selected" and .selected.item == "second"' >/dev/null
}

@test "cog queue-select selects next runnable plan with schema flag" {
  local queue="${BATS_TEST_TMPDIR}/queue-plans.yaml"
  write_plans_queue "$queue"

  run cog queue-select --queue "$queue" --schema plans --no-clean-check --json

  assert_success
  printf '%s\n' "$output" | jq -e '.schema == "plans" and .state == "selected" and .selected.item == "second-plan"' >/dev/null
}

@test "cog queue-select default rounds output is unchanged except schema" {
  local queue="${BATS_TEST_TMPDIR}/queue-rounds.yaml"
  local repo_root
  repo_root="$(pwd -P)"
  write_queue "$queue"

  run cog queue-select --queue "$queue" --no-clean-check --json

  assert_success
  printf '%s\n' "$output" | jq -e --arg queue "$queue" --arg repo_root "$repo_root" '
    .schema == "rounds" and
    (del(.schema) == {
      ok: true,
      queue_path: $queue,
      repo_root: $repo_root,
      clean_check: false,
      state: "selected",
      selected: {
        item: "second",
        status: "todo",
        depends_on: ["first"],
        prompt: "/prex -ar second.md",
        notes: "note"
      },
      todo_remaining: ["second"],
      blocked: [],
      reason: null
    })
  ' >/dev/null
}

@test "cog queue-select reports complete blocked and doing states" {
  local queue="${BATS_TEST_TMPDIR}/queue-rounds.yaml"
  cat >"$queue" <<'EOF'
rounds:
  - item: first
    status: done
    depends_on: []
    prompt: /prex -ar first.md
    notes: note
EOF
  run cog queue-select --queue "$queue" --no-clean-check --json
  assert_success
  printf '%s\n' "$output" | jq -e '.schema == "rounds" and .state == "complete"' >/dev/null

  cat >"$queue" <<'EOF'
rounds:
  - item: blocked
    status: todo
    depends_on: [missing]
    prompt: /prex -ar blocked.md
    notes: note
EOF
  run cog queue-select --queue "$queue" --no-clean-check --json
  assert_failure
  printf '%s\n' "$output" | jq -e '.schema == "rounds" and .state == "blocked" and .ok == false' >/dev/null

  cat >"$queue" <<'EOF'
rounds:
  - item: active
    status: doing
    depends_on: []
    prompt: /prex -ar active.md
    notes: note
EOF
  run --separate-stderr cog queue-select --queue "$queue" --no-clean-check --json
  assert_failure
  [[ $stderr == *"rounds already doing"* ]]
}

@test "cog queue-select clean check binds to --repo-root not cwd" {
  # Target repo: clean worktree with a queue that has a selectable round.
  local target="${BATS_TEST_TMPDIR}/target"
  mkdir -p "$target"
  git -C "$target" init -q
  git -C "$target" config user.email t@e.st
  git -C "$target" config user.name tester
  git -C "$target" commit -q --allow-empty -m init
  # Queue file lives outside the target repo so it does not dirty the worktree.
  local queue="${BATS_TEST_TMPDIR}/clean-queue-rounds.yaml"
  write_queue "$queue"

  # Caller's cwd: a *different*, dirty repo. If the clean check ran against cwd
  # instead of --repo-root it would wrongly report a dirty worktree.
  local dirty_cwd="${BATS_TEST_TMPDIR}/dirty"
  mkdir -p "$dirty_cwd"
  git -C "$dirty_cwd" init -q
  printf 'unstaged\n' >"${dirty_cwd}/scratch.txt"

  run bash -c "cd '$dirty_cwd' && cog queue-select --queue '$queue' --repo-root '$target' --json"

  assert_success
  printf '%s\n' "$output" | jq -e '.schema == "rounds" and .clean_check == true and .state == "selected" and .selected.item == "second"' >/dev/null
}

@test "cog queue-select clean check rejects a dirty --repo-root" {
  local target="${BATS_TEST_TMPDIR}/dirtytarget"
  mkdir -p "$target"
  git -C "$target" init -q
  printf 'unstaged\n' >"${target}/scratch.txt"
  local queue="${target}/queue-rounds.yaml"
  write_queue "$queue"

  run cog queue-select --queue "$queue" --repo-root "$target" --json

  assert_failure
  printf '%s\n' "$output" | jq -e --arg target "$target" '.ok == false and .reason == ("dirty worktree: " + $target)' >/dev/null
}

@test "cog queue-select accepts absolute repos block and rejects relative entries" {
  local queue="${BATS_TEST_TMPDIR}/queue-rounds.yaml"
  cat >"$queue" <<EOF
repos:
  - ${BATS_TEST_TMPDIR}/satellite
rounds:
  - item: first
    status: todo
    depends_on: []
    prompt: /prex -ar first.md
    notes: note
EOF

  run cog queue-select --queue "$queue" --no-clean-check --json

  assert_success
  printf '%s\n' "$output" | jq -e '.schema == "rounds" and .state == "selected" and .selected.item == "first"' >/dev/null

  cat >"$queue" <<'EOF'
repos:
  - relative/repo
rounds:
  - item: first
    status: todo
    depends_on: []
    prompt: /prex -ar first.md
    notes: note
EOF

  run --separate-stderr cog queue-select --queue "$queue" --no-clean-check --json

  assert_failure
  [[ $stderr == *"repos: entries must be non-empty absolute paths"* ]]
}

@test "cog queue-select clean check includes satellite repos" {
  local primary="${BATS_TEST_TMPDIR}/primary"
  local satellite="${BATS_TEST_TMPDIR}/satellite"
  mkdir -p "$primary" "$satellite"
  git -C "$primary" init -q
  git -C "$satellite" init -q
  git -C "$primary" config user.email t@e.st
  git -C "$primary" config user.name tester
  git -C "$satellite" config user.email t@e.st
  git -C "$satellite" config user.name tester
  git -C "$primary" commit -q --allow-empty -m init
  git -C "$satellite" commit -q --allow-empty -m init
  printf 'dirty\n' >"${satellite}/dirty.txt"
  local queue="${BATS_TEST_TMPDIR}/satellite-queue-rounds.yaml"
  write_queue "$queue"

  run cog queue-select --queue "$queue" --repo-root "$primary" --repo "$satellite" --json

  assert_failure
  printf '%s\n' "$output" | jq -e --arg satellite "$satellite" '.ok == false and .reason == ("dirty worktree: " + $satellite)' >/dev/null

  run cog queue-select --queue "$queue" --repo-root "$primary" --repo "$satellite" --no-clean-check --json

  assert_success
  printf '%s\n' "$output" | jq -e '.schema == "rounds" and .state == "selected"' >/dev/null
}

@test "cog queue-select --help dispatches" {
  run cog queue-select --help

  assert_success
  [[ $output == *"Select the next runnable"* ]]
}
