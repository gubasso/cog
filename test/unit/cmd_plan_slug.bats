setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/commands/cmd_plan_slug.sh"
}

@test "plan-slug derives normalized slug" {
  run __cog_plan_slug_derive "Hello, World + Again"

  assert_success
  assert_output "hello-world-again"
}

@test "plan-slug JSON marks reserved names" {
  run __cog_plan_slug_build_json Strategy

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == false and .reserved == true and .slug == null' >/dev/null
}

@test "plan-slug enforces 60 char boundary" {
  run __cog_plan_slug_derive "aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll mmmm"

  assert_success
  [ "${#output}" -le 60 ]
}
