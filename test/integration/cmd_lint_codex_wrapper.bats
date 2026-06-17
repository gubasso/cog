setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog lint-codex-wrapper scans live claude skill tree cleanly" {
  run bin/cog lint-codex-wrapper

  assert_success
}
