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
    plan-queue-runner
    plan-reviewer
    plan-writer
    plan-writer-multi
    pre-commit
    prex
    refactor-migration-plan
    review-code-deep
    review-findings
    review-loop
    suckless-patcher
    test-review
    tsk-impl
    tsk-new
  )
  local skill

  for skill in "${skills[@]}"; do
    assert_markdown_frontmatter "$repo_root/skills/claude/$skill/SKILL.md"
  done
}

@test "project-local skill-builder has valid frontmatter" {
  assert_markdown_frontmatter "$repo_root/.claude/skills/skill-builder/SKILL.md"
}

@test "all Codex skills have valid frontmatter" {
  local skills=(
    ask
    ast-grep
    gc
    implementation-reviewer
    plan-writer
    refactor-migration-plan
    review-code-deep
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

@test "plan queue runner documents delegate multi-repo commit flow" {
  local file="$repo_root/skills/claude/plan-queue-runner/SKILL.md"

  assert_file_contains "$file" "claude-delegate"
  assert_file_contains "$file" "cog queue-select"
  assert_file_contains "$file" "repo"
  assert_file_contains "$file" "repos:"
  assert_file_contains "$file" "COMMIT_SHA=<sha> repo=<root>"
  assert_file_contains "$file" "commits"
}

@test "plan writer multi documents satellite repos" {
  local file="$repo_root/skills/claude/plan-writer-multi/SKILL.md"

  assert_file_contains "$file" "repos:"
  assert_file_contains "$file" "/gc -a --repo <sat>"
}
