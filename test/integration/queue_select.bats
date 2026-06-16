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

@test "cog queue-select selects next runnable round" {
  local queue="${BATS_TEST_TMPDIR}/QUEUE.yaml"
  write_queue "$queue"

  run cog queue-select --queue "$queue" --no-clean-check --json

  assert_success
  printf '%s\n' "$output" | jq -e '.state == "selected" and .selected.item == "second"' >/dev/null
}

@test "cog queue-select reports complete blocked and doing states" {
  local queue="${BATS_TEST_TMPDIR}/QUEUE.yaml"
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
  printf '%s\n' "$output" | jq -e '.state == "complete"' >/dev/null

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
  printf '%s\n' "$output" | jq -e '.state == "blocked" and .ok == false' >/dev/null

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
  local queue="${BATS_TEST_TMPDIR}/clean-QUEUE.yaml"
  write_queue "$queue"

  # Caller's cwd: a *different*, dirty repo. If the clean check ran against cwd
  # instead of --repo-root it would wrongly report a dirty worktree.
  local dirty_cwd="${BATS_TEST_TMPDIR}/dirty"
  mkdir -p "$dirty_cwd"
  git -C "$dirty_cwd" init -q
  printf 'unstaged\n' >"${dirty_cwd}/scratch.txt"

  run bash -c "cd '$dirty_cwd' && cog queue-select --queue '$queue' --repo-root '$target' --json"

  assert_success
  printf '%s\n' "$output" | jq -e '.clean_check == true and .state == "selected" and .selected.item == "second"' >/dev/null
}

@test "cog queue-select clean check rejects a dirty --repo-root" {
  local target="${BATS_TEST_TMPDIR}/dirtytarget"
  mkdir -p "$target"
  git -C "$target" init -q
  printf 'unstaged\n' >"${target}/scratch.txt"
  local queue="${target}/QUEUE.yaml"
  write_queue "$queue"

  run cog queue-select --queue "$queue" --repo-root "$target" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "dirty worktree"' >/dev/null
}

@test "cog queue-select --help dispatches" {
  run cog queue-select --help

  assert_success
  [[ $output == *"Select the next runnable"* ]]
}
