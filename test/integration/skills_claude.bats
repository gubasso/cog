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
    assess-input
    ast-grep
    claudemd
    gc
    osc-obs
    plan-multi
    plan-vetted
    bootstrap
    bootstrap-lint
    bootstrap-nix
    bootstrap-repo
    bootstrap-ci
    bootstrap-taskrunner
    bootstrap-rust
    bootstrap-governance
    bootstrap-installer
    bootstrap-knowledge-base
    review-oneshot
    review-findings
    review-loop
    review-plan-multi
    suckless-patcher
    test-review
  )
  local skill

  for skill in "${skills[@]}"; do
    assert_markdown_frontmatter "$repo_root/skills/claude/$skill/SKILL.md"
  done
}

@test "shipped cog-skill-creator has valid frontmatter" {
  assert_markdown_frontmatter "$repo_root/skills/claude/cog-skill-creator/SKILL.md"
}

@test "cog-skill-creator is no longer a repo-local skill" {
  [ ! -e "$repo_root/.claude/skills/cog-skill-creator/SKILL.md" ]
}

@test "all Codex skills have valid frontmatter" {
  local skills=(
    ask
    assess-input
    ast-grep
    implementation-reviewer
    review-oneshot
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
  # The gc coordinator documents the aggregation view and result-line contract; the
  # gc-repo worker emits the per-repo status lines.
  local coordinator="$repo_root/skills/claude/gc/SKILL.md"
  assert_file_contains "$coordinator" "cog gc-commit-parse"
  assert_file_contains "$coordinator" "COMMIT_OK <sha>"
  assert_file_contains "$coordinator" "COMMIT_PUSH_OK <sha> repo=<root>"
  assert_file_contains "$coordinator" "COMMIT_FAILED"
  assert_file_contains "$coordinator" "COMMIT_PUSH_FAILED"
  assert_file_contains "$coordinator" "nothing after it"
  assert_file_contains "$coordinator" "repo-root"
  assert_file_contains "$coordinator" "repo-set"

  local worker="$repo_root/skills/claude/gc-repo/SKILL.md"
  assert_file_contains "$worker" "cog msg ok commit"
  assert_file_contains "$worker" "COMMIT_OK <sha>"
  assert_file_contains "$worker" "COMMIT_PUSH_OK <sha> repo=<root>"
  assert_file_contains "$worker" "COMMIT_FAILED"
  assert_file_contains "$worker" "COMMIT_PUSH_FAILED"
  assert_file_contains "$worker" "nothing after it"
  assert_file_contains "$worker" "result-file"
  assert_file_contains "$worker" "repo-root"
}

@test "gc skills document the change-provenance and destructive-recovery guards" {
  # Provenance/safety gates stay in the coordinator; the diffstat materiality,
  # whole-file staging, and destructive-git guards live in the shared commit
  # routine both the inline path and the per-repo worker follow.
  local coordinator="$repo_root/skills/claude/gc/SKILL.md"
  assert_file_contains "$coordinator" "foreign-dirty"
  assert_file_contains "$coordinator" "git reset --hard"
  assert_file_contains "$coordinator" "git stash list"

  local routine="$repo_root/skill-refs/gc/commit-routine.md"
  assert_file_exists "$routine"
  assert_file_contains "$routine" "git reset --hard"
  assert_file_contains "$routine" "git diff --cached --stat"
  assert_file_contains "$routine" "path-granular"
}

@test "gc commits a single repo inline and shares one commit routine" {
  # The default path runs in the caller's own context: no fan-out, no worker.
  # Every commit path resolves the same routine, so the prose cannot drift.
  local coordinator="$repo_root/skills/claude/gc/SKILL.md"
  assert_file_contains "$coordinator" "gc/commit-routine.md"
  assert_file_contains "$coordinator" "in this context"
  assert_file_not_contains "$coordinator" "never stage or commit inline"

  local file
  for file in \
    "$repo_root/skills/claude/gc-repo/SKILL.md" \
    "$repo_root/skills/claude/gc-hook-fix/SKILL.md"; do
    assert_file_contains "$file" "gc/commit-routine.md"
  done
}

@test "plan multi documents satellite repos" {
  local file="$repo_root/skills/claude/plan-multi/SKILL.md"

  assert_file_contains "$file" "codex-runner"
}

@test "retired vault, queue, round, and spec-pipeline skills no longer exist" {
  local skill
  for skill in plan-builder-to-queue plan-builder-to-queue-vetted-multi runner-all runner-plan \
    review-queue-rounds plan-split review-plan-complexity plan-capability-spec plan-solution-spec \
    executor-greenfield-from-spec review-plan-capability-spec review-plan-solution-spec; do
    [ ! -e "$repo_root/skills/claude/$skill" ]
    [ ! -e "$repo_root/skills/codex/$skill" ]
  done
  run grep -qE 'runner-all|runner-plan|plan-builder-to-queue' "$repo_root/data/model-effort/claude/tiers.yaml"
  assert_failure
}

@test "deleted authoring surfaces no longer exist (DP6 regression)" {
  [ ! -e "$repo_root/skills/claude/plan-writer-multi/SKILL.md" ]
  [ ! -e "$repo_root/skills/claude/plan-writer/SKILL.md" ]
  [ ! -e "$repo_root/skills/codex/plan-writer/SKILL.md" ]
  [ ! -e "$repo_root/lib/commands/cmd_plan_writer_multi_setup.sh" ]
  run grep -q "plan-writer-multi" "$repo_root/data/model-effort/claude/tiers.yaml"
  assert_failure
  run grep -q "plan-writer" "$repo_root/data/model-effort/codex/tiers.yaml"
  assert_failure
}
