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
    skill-builder
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

@test "claude-delegate agent has valid frontmatter" {
  assert_markdown_frontmatter "$repo_root/agents/claude/claude-delegate.md"
}

@test "Claude skills and agents do not reference dotfiles helper source" {
  run forbidden_scan

  [[ $status -eq 1 ]]
  [[ -z $output ]]
}
