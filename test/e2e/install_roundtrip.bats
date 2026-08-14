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
  assert_dir_exists "$XDG_DATA_HOME/cog/skill-refs/templates/pre-commit"
  assert_dir_exists "$XDG_DATA_HOME/cog/skill-refs/templates/editorconfig"
  assert_file_exists "$XDG_DATA_HOME/cog/skill-refs/docs-design/AGENTS.md"
  assert_file_exists "$XDG_DATA_HOME/cog/data/power-grade/matrix/model-cells.yaml"
  assert_file_exists "$XDG_DATA_HOME/cog/data/model-effort/claude/tiers.yaml"
  assert_file_exists "$XDG_DATA_HOME/cog/data/maintenance-tracking.yaml"

  run cog --version
  assert_success
  assert_output "0.1.0"

  # shellcheck disable=SC2016 # $1 is intentionally expanded inside the child shell.
  run "$BASH" -c 'cd "$1" && cog power-grade cell --model claude-opus-4-8 --effort high --json | jq -e ".ok == true" >/dev/null' bash "$BATS_TEST_TMPDIR"
  assert_success

  # shellcheck disable=SC2016 # $1 is intentionally expanded inside the child shell.
  run "$BASH" -c 'cd "$1" && cog tracking-scan --now 2026-06-29 --json | jq -e ".registry_path | contains(\"/cog/data/maintenance-tracking.yaml\")" >/dev/null' bash "$BATS_TEST_TMPDIR"
  assert_success

  run cog doctor
  assert_success
}

@test "install stdout is stable and stderr shows progress phases" {
  run --separate-stderr "$REPO_ROOT/install.sh"
  assert_success
  assert_output "installed cog to $PREFIX/lib/cog (PATH: $PREFIX/bin/cog)"
  [[ $stderr == *"Preflight"* ]]
  [[ $stderr == *"Copy application payload"* ]]
  [[ $stderr == *"Link executable"* ]]
  [[ $stderr == *"Sync Claude and Codex skills"* ]]
  [[ $stderr == *"Finalize manifest"* ]]
}

@test "install honors NO_COLOR on stderr" {
  run --separate-stderr env NO_COLOR=1 "$REPO_ROOT/install.sh"
  assert_success
  assert_output "installed cog to $PREFIX/lib/cog (PATH: $PREFIX/bin/cog)"
  [[ $stderr != *$'\033['* ]]
}

@test "install quiet mode keeps stdout stable and suppresses normal steps" {
  run --separate-stderr env COG_INSTALL_QUIET=1 "$REPO_ROOT/install.sh"
  assert_success
  assert_output "installed cog to $PREFIX/lib/cog (PATH: $PREFIX/bin/cog)"
  [[ $stderr != *"Preflight"* ]]
  [[ $stderr != *"Copy application payload"* ]]
}

@test "install preflight names missing required tools" {
  local bash_path="${BASH:-}"
  local empty_path="$BATS_TEST_TMPDIR/empty-path"

  if [[ -z $bash_path || ! -x $bash_path ]]; then
    if [[ -x /usr/bin/bash ]]; then
      bash_path="/usr/bin/bash"
    elif [[ -x /bin/bash ]]; then
      bash_path="/bin/bash"
    else
      skip "absolute bash path is unavailable"
    fi
  fi

  mkdir -p "$empty_path"
  run --separate-stderr env PATH="$empty_path" "$bash_path" "$REPO_ROOT/install.sh"
  assert_failure
  [[ $stderr == *"missing required command 'install'"* ]]
}

@test "install preserves installed research shelf on upgrade" {
  local shelf="$XDG_DATA_HOME/cog/data/research-shelf/index.jsonl"

  run "$REPO_ROOT/install.sh"
  assert_success
  printf '%s\n' '{"id":"local-record"}' >>"$shelf"

  run "$REPO_ROOT/install.sh"
  assert_success

  grep -Fqx '{"id":"local-record"}' "$shelf"
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

@test "no-manifest uninstall is successful and informative" {
  local manifest="$XDG_STATE_HOME/cog/install-manifest"

  run --separate-stderr "$REPO_ROOT/uninstall.sh"
  assert_success
  assert_output ""
  [[ $stderr == *"nothing to uninstall"* ]]
  [[ $stderr == *"$manifest"* ]]
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
  grep -Fqx "$XDG_DATA_HOME/cog/data/power-grade/matrix/model-cells.yaml" "$manifest"
  grep -Fqx "$XDG_DATA_HOME/cog/data/research-shelf/index.jsonl" "$manifest"
  grep -Fqx "$XDG_DATA_HOME/cog/skill-refs/docs-design/AGENTS.md" "$manifest"
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

@test "uninstall fails closed when manifest contains outside path" {
  local manifest="$XDG_STATE_HOME/cog/install-manifest"

  run "$REPO_ROOT/install.sh"
  assert_success
  printf '%s\n' "/tmp/cog-outside-root-test" >>"$manifest"

  run --separate-stderr "$REPO_ROOT/uninstall.sh"
  assert_failure
  [[ $stderr == *"outside the current PREFIX/XDG roots"* ]]
  assert_file_exists "$manifest"
}

# The two tests below cover upgrading and uninstalling over an installation made
# before the workflow layer was removed. Such a manifest names files under
# $data_dir/workflow and $data_dir/data/workflow-engines, which this cog no
# longer ships. Both destinations must stay admissible in valid_manifest_path:
# dropping them makes the installer's stale-prune skip those entries and makes
# uninstall count them as unsafe and refuse the whole manifest.

# Recreates what an installation from before the workflow removal left behind:
# the retired trees on disk and their manifest entries.
seed_legacy_workflow_layer() {
  local manifest="$XDG_STATE_HOME/cog/install-manifest"

  mkdir -p "$XDG_DATA_HOME/cog/workflow/workflows" "$XDG_DATA_HOME/cog/data/workflow-engines"
  printf '%s\n' "legacy stub" >"$XDG_DATA_HOME/cog/workflow/workflows/linear-stub.yaml"
  printf '%s\n' "legacy stub" >"$XDG_DATA_HOME/cog/workflow/meta.yaml"
  printf '%s\n' "legacy registry" >"$XDG_DATA_HOME/cog/data/workflow-engines/engines.yaml"
  printf '%s\n' \
    "$XDG_DATA_HOME/cog/workflow/workflows/linear-stub.yaml" \
    "$XDG_DATA_HOME/cog/workflow/meta.yaml" \
    "$XDG_DATA_HOME/cog/data/workflow-engines/engines.yaml" >>"$manifest"
}

@test "upgrade over a legacy install removes the retired workflow layer" {
  local manifest="$XDG_STATE_HOME/cog/install-manifest"

  run "$REPO_ROOT/install.sh"
  assert_success
  seed_legacy_workflow_layer

  run "$REPO_ROOT/install.sh"
  assert_success

  # Files and their directories both go, so no empty tree is orphaned.
  assert_dir_not_exists "$XDG_DATA_HOME/cog/workflow"
  assert_dir_not_exists "$XDG_DATA_HOME/cog/data/workflow-engines"

  # The replacement manifest must not carry the retired entries forward.
  run grep -Fq "$XDG_DATA_HOME/cog/workflow/" "$manifest"
  assert_failure
  run grep -Fq "$XDG_DATA_HOME/cog/data/workflow-engines/" "$manifest"
  assert_failure
}

@test "uninstall over a legacy install removes the whole installation" {
  local manifest="$XDG_STATE_HOME/cog/install-manifest"
  local manifest_copy="$BATS_TEST_TMPDIR/install-manifest.legacy"
  local path

  run "$REPO_ROOT/install.sh"
  assert_success
  seed_legacy_workflow_layer
  cp "$manifest" "$manifest_copy"

  # Must not fail manifest authority: a retired-but-admissible path is not an
  # unsafe path, and refusing here would leave the entire install on disk.
  run "$REPO_ROOT/uninstall.sh"
  assert_success

  assert_file_not_exists "$manifest"
  while IFS= read -r path; do
    [ ! -e "$path" ]
  done <"$manifest_copy"
  assert_dir_not_exists "$XDG_DATA_HOME/cog/workflow"
  [ ! -L "$PREFIX/bin/cog" ]
}
