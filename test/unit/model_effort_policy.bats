setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_toml.sh"
}

@test "claude policy forbids sonnet and fable" {
  command -v taplo >/dev/null 2>&1 || skip "taplo not installed"

  run cog::fn::toml::json "${REPO_ROOT}/docs/reference/model-effort-claude.toml"

  assert_success
  printf '%s\n' "$output" | jq -e '
    (.forbidden_models | index("sonnet")) != null
    and (.forbidden_models | index("fable")) != null
  ' >/dev/null
}

@test "codex policy marks xhigh supported for gpt-5.5, gpt-5.4, and gpt-5.4-mini" {
  command -v taplo >/dev/null 2>&1 || skip "taplo not installed"

  run cog::fn::toml::json "${REPO_ROOT}/docs/reference/model-effort-codex.toml"

  assert_success
  # gpt-5.4-mini effort enum was verified 2026-06-24 and promoted out of the unverified table.
  printf '%s\n' "$output" | jq -e '
    (.supported_efforts["gpt-5.5"] | index("xhigh")) != null
    and (.supported_efforts["gpt-5.4"] | index("xhigh")) != null
    and (.supported_efforts["gpt-5.4-mini"] | index("xhigh")) != null
    and (has("supported_efforts_unverified") | not)
  ' >/dev/null
}

@test "codex supported_efforts use minimal (model_reasoning_effort lowest tier), not none" {
  command -v taplo >/dev/null 2>&1 || skip "taplo not installed"

  run cog::fn::toml::json "${REPO_ROOT}/docs/reference/model-effort-codex.toml"

  assert_success
  # cog drives the Codex `model_reasoning_effort` key, whose lowest tier is `minimal`, never `none`.
  printf '%s\n' "$output" | jq -e '
    (.supported_efforts["gpt-5.5"] | index("minimal")) != null
    and (.supported_efforts["gpt-5.5"] | index("none")) == null
  ' >/dev/null
}
