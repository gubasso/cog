setup() {
  bats_require_minimum_version 1.5.0
  load "${BATS_TEST_DIRNAME}/../test_helper/bats-support/load"
  load "${BATS_TEST_DIRNAME}/../test_helper/bats-assert/load"
  load "${BATS_TEST_DIRNAME}/../test_helper/bats-file/load"

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export REPO_ROOT
  export HOME="$BATS_TEST_TMPDIR/home"
  export PREFIX="$HOME/.local"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_STATE_HOME="$HOME/.local/state"
  mkdir -p "$HOME"
  PATH="$PREFIX/bin:$PATH"
  export PATH
}

teardown() {
  rm -rf "${BATS_TEST_TMPDIR:?}/home"
}

@test "install and invoke from PATH" {
  run "$REPO_ROOT/install.sh"
  assert_success

  [ -L "$PREFIX/bin/cog" ]
  [ -x "$PREFIX/bin/cog" ]
  assert_file_exists "$PREFIX/lib/cog/lib/helpers.sh"
  assert_file_exists "$PREFIX/lib/cog/VERSION"
  assert_dir_exists "$PREFIX/lib/cog/templates/pre-commit"

  run cog --version
  assert_success
  assert_output "0.1.0"

  run cog doctor
  assert_success
}

@test "agents and skills deployed" {
  run "$REPO_ROOT/install.sh"
  assert_success

  assert_file_exists "$HOME/.claude/agents/claude-delegate.md"
  run find "$HOME/.claude/skills" -type f -print -quit
  assert_success
  [ -n "$output" ]
  run find "$HOME/.agents/skills" -type f -print -quit
  assert_success
  [ -n "$output" ]
}

@test "uninstall preserves user-authored files" {
  run "$REPO_ROOT/install.sh"
  assert_success

  mkdir -p "$HOME/.claude/skills/user-skill"
  printf '%s\n' "user claude skill" >"$HOME/.claude/skills/user-skill/SKILL.md"
  mkdir -p "$HOME/.agents/skills/user-skill"
  printf '%s\n' "user codex skill" >"$HOME/.agents/skills/user-skill/SKILL.md"
  printf '%s\n' "user agent" >"$HOME/.claude/agents/user-agent.md"

  run "$REPO_ROOT/uninstall.sh"
  assert_success

  assert_file_not_exists "$PREFIX/bin/cog"
  assert_file_not_exists "$HOME/.claude/agents/claude-delegate.md"
  assert_file_exists "$HOME/.claude/skills/user-skill/SKILL.md"
  assert_file_exists "$HOME/.agents/skills/user-skill/SKILL.md"
  assert_file_exists "$HOME/.claude/agents/user-agent.md"
}

@test "manifest authority" {
  local manifest="$XDG_STATE_HOME/cog/install-manifest"
  local manifest_copy="$BATS_TEST_TMPDIR/install-manifest.copy"
  local path

  run "$REPO_ROOT/install.sh"
  assert_success

  assert_file_exists "$manifest"
  grep -Fqx "$PREFIX/bin/cog" "$manifest"
  grep -Fqx "$PREFIX/lib/cog/lib/helpers.sh" "$manifest"
  grep -Fqx "$XDG_DATA_HOME/bash-completion/completions/cog" "$manifest"
  grep -Fqx "$HOME/.claude/agents/claude-delegate.md" "$manifest"
  grep -Eq "^$HOME/\.claude/skills/[^/]+/SKILL\.md$" "$manifest"

  mkdir -p "$HOME/.claude/skills/user-skill"
  printf '%s\n' "user claude skill" >"$HOME/.claude/skills/user-skill/SKILL.md"
  mkdir -p "$HOME/.agents/skills/user-skill"
  printf '%s\n' "user codex skill" >"$HOME/.agents/skills/user-skill/SKILL.md"
  printf '%s\n' "user agent" >"$HOME/.claude/agents/user-agent.md"
  cp "$manifest" "$manifest_copy"

  run "$REPO_ROOT/uninstall.sh"
  assert_success

  assert_file_not_exists "$manifest"
  while IFS= read -r path; do
    [ ! -e "$path" ]
  done <"$manifest_copy"
  assert_file_exists "$HOME/.claude/skills/user-skill/SKILL.md"
  assert_file_exists "$HOME/.agents/skills/user-skill/SKILL.md"
  assert_file_exists "$HOME/.claude/agents/user-agent.md"
}
