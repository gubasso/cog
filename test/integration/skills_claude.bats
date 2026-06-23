setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  repo_root="${BATS_TEST_DIRNAME}/../.."
}

assert_markdown_frontmatter() {
  local file="$1"

  [[ -f $file ]]
  [[ $(sed -n '1p' "$file") == "---" ]]
  awk 'NR > 1 && $0 == "---" { found = 1; exit } END { exit found ? 0 : 1 }' "$file"
  awk '
    NR == 1 && $0 == "---" { frontmatter = 1; next }
    frontmatter && $0 == "---" { exit }
    frontmatter && /^name:[[:space:]]*/ { has_name = 1 }
    frontmatter && /^description:[[:space:]]*/ { has_description = 1 }
    END { exit (has_name && has_description) ? 0 : 1 }
  ' "$file"
}

forbidden_scan() {
  local pattern='agent-helper|AGENT_HELPER|/workspaces/\.dotfiles'

  if command -v rg >/dev/null 2>&1; then
    rg -n "$pattern" "$repo_root/skills/claude" "$repo_root/agents/claude"
  else
    grep -rE -n "$pattern" "$repo_root/skills/claude" "$repo_root/agents/claude"
  fi
}

forbidden_scan_codex() {
  local pattern='agent-helper|AGENT_HELPER|/workspaces/\.dotfiles'

  if command -v rg >/dev/null 2>&1; then
    rg -n "$pattern" "$repo_root/skills/codex"
  else
    grep -rE -n "$pattern" "$repo_root/skills/codex"
  fi
}

@test "all Claude skills have valid frontmatter" {
  local skills=(
    ask
    ast-grep
    claudemd
    gc
    osc-obs
    plan-writer
    plan-writer-multi
    pre-commit
    plan-refactor-migration
    review-lean
    review-findings
    review-loop
    runner-all
    runner-plan
    suckless-patcher
    test-review
  )
  local skill

  for skill in "${skills[@]}"; do
    assert_markdown_frontmatter "$repo_root/skills/claude/$skill/SKILL.md"
  done
}

@test "project-local cog-skill-creator has valid frontmatter" {
  assert_markdown_frontmatter "$repo_root/.claude/skills/cog-skill-creator/SKILL.md"
}

@test "all Codex skills have valid frontmatter" {
  local skills=(
    ask
    ast-grep
    gc
    implementation-reviewer
    plan-writer
    plan-refactor-migration
    review-lean
    suckless-patcher
    test-review
  )
  local skill

  for skill in "${skills[@]}"; do
    assert_markdown_frontmatter "$repo_root/skills/codex/$skill/SKILL.md"
  done
}

@test "claude-delegate agent has valid frontmatter" {
  assert_markdown_frontmatter "$repo_root/agents/claude/claude-delegate.md"
}

@test "Claude skills and agents do not reference dotfiles helper source" {
  run forbidden_scan

  [[ $status -eq 1 ]]
  [[ -z $output ]]
}

@test "Codex skills do not reference dotfiles helper source" {
  run forbidden_scan_codex

  [[ $status -eq 1 ]]
  [[ -z $output ]]
}

@test "gc skills document canonical multi-repo status contract" {
  local file
  for file in "$repo_root/skills/claude/gc/SKILL.md" "$repo_root/skills/codex/gc/SKILL.md"; do
    assert_file_contains "$file" "cog msg ok commit"
    assert_file_contains "$file" "COMMIT_OK <sha>"
    assert_file_contains "$file" "COMMIT_PUSH_OK <sha> repo=<root>"
    assert_file_contains "$file" "COMMIT_FAILED"
    assert_file_contains "$file" "COMMIT_PUSH_FAILED"
    assert_file_contains "$file" "nothing after it"
    assert_file_contains "$file" "repo-root"
    assert_file_contains "$file" "repo-set"
  done
}

@test "runner skills document delegate multi-repo commit flow" {
  local file
  for file in "$repo_root/skills/claude/runner-all/SKILL.md" "$repo_root/skills/claude/runner-plan/SKILL.md"; do
    assert_file_contains "$file" "claude-delegate"
    assert_file_contains "$file" "cog queue-select"
    assert_file_contains "$file" "review-plan-implementation"
    assert_file_contains "$file" "cog runner-commit-parse"
    assert_file_contains "$file" "COMMIT_SHA=<sha> repo=<root>"
    assert_file_contains "$file" "commits"
    assert_file_contains "$file" "verbatim"
  done
}

@test "runner-all documents main reconcile and runner-plan documents round verify" {
  assert_file_contains "$repo_root/skills/claude/runner-all/SKILL.md" "cog queue-status-set"
  assert_file_contains "$repo_root/skills/claude/runner-all/SKILL.md" $'Main-plan `done`'
  assert_file_contains "$repo_root/skills/claude/runner-plan/SKILL.md" "ROUND_STATUS"
  assert_file_contains "$repo_root/skills/claude/runner-plan/SKILL.md" "repos:"
}

@test "plan writer multi documents satellite repos" {
  local file="$repo_root/skills/claude/plan-writer-multi/SKILL.md"

  assert_file_contains "$file" "repos:"
  assert_file_contains "$file" "/gc -a --repo <sat>"
}
