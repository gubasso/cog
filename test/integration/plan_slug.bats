setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog plan-slug derives normalized slug" {
  run cog plan-slug --text "Plan artifacts + Queue!" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.slug == "plan-artifacts-queue" and .reserved == false' >/dev/null
}

@test "cog plan-slug rejects reserved names" {
  run cog plan-slug --text "QUEUE" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .slug == null and .reserved == true' >/dev/null
}

@test "cog plan-slug enforces charset and max length" {
  run cog plan-slug --text "AAAA bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll mmmm nnnn" --json

  assert_success
  printf '%s\n' "$output" | jq -e '(.slug | test("^[a-z0-9-]+$")) and (.slug | length) <= 60 and .max_length == 60' >/dev/null
}

@test "cog plan-slug --help dispatches" {
  run cog plan-slug --help

  assert_success
  [[ $output == *"Derive and validate"* ]]
}
