setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  source "${LIB_DIR}/functions/fn_review.sh"
}

@test "finding_key normalizes headline whitespace" {
  run cog::fn::review::finding_key "lib/a.sh" 12 "  Bad   thing  "
  assert_success
  local first="$output"

  run cog::fn::review::finding_key "lib/a.sh" 12 "Bad thing"
  assert_success
  assert_output "$first"
}

@test "severity_rank orders blocking above praise" {
  run cog::fn::review::severity_rank blocking
  assert_success
  assert_output "50"

  run cog::fn::review::severity_rank praise
  assert_success
  assert_output "0"
}
