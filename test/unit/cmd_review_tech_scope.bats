setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  mkdir -p "$HOME" "${XDG_DATA_HOME}/cog/skill-refs/code-review/languages/bash" "${XDG_DATA_HOME}/cog/skill-refs/cli-design"
  printf '%s\n' "core" >"${XDG_DATA_HOME}/cog/skill-refs/code-review/AGENTS.md"
  printf '%s\n' "bash" >"${XDG_DATA_HOME}/cog/skill-refs/code-review/languages/bash/code-review-guide.md"
  printf '%s\n' "cli" >"${XDG_DATA_HOME}/cog/skill-refs/cli-design/AGENTS.md"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_skill_refs.sh"
  source "${LIB_DIR}/commands/cmd_review_tech_scope.sh"
}

write_scope() {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo/bin"
  printf '%s\n' '#!/usr/bin/env bash' 'echo ok' >"$repo/bin/tool.sh"
  chmod +x "$repo/bin/tool.sh"
  jq -n --arg repo "$repo" '{repo_root: $repo, changed_files: ["bin/tool.sh"], status_files: []}' >"${BATS_TEST_TMPDIR}/scope.json"
}

@test "review-tech-scope detects bash cli and bundled refs" {
  write_scope

  run __cog_review_tech_scope_build_json "${BATS_TEST_TMPDIR}/scope.json" ""

  assert_success
  printf '%s\n' "$output" | jq -e '
    .is_cli == true
    and (.detected_technologies[] | select(.kind == "language" and .name == "bash"))
    and (.available_refs | index("code-review/languages/bash/code-review-guide.md"))
    and (.available_refs | index("cli-design/AGENTS.md"))
  ' >/dev/null
}

@test "review-tech-scope requires scope" {
  run --separate-stderr cog::cmd::review_tech_scope --json

  assert_failure 64
  [[ $stderr == *"MissingArgument"* ]]
}
