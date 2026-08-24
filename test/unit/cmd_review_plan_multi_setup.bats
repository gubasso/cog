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
  source "${LIB_DIR}/functions/fn_rundir.sh"
  source "${LIB_DIR}/functions/fn_git.sh"
  source "${LIB_DIR}/functions/fn_skill.sh"
  source "${LIB_DIR}/functions/fn_plan_artifact.sh"
  source "${LIB_DIR}/functions/fn_plan_doc.sh"
  source "${LIB_DIR}/functions/fn_assess_input.sh"
  source "${LIB_DIR}/functions/fn_plan_gate.sh"
  source "${LIB_DIR}/commands/cmd_review_plan_multi_setup.sh"
}

@test "review-plan-multi parser strips solo and keeps input verbatim" {
  local solo output_path input

  __cog_review_plan_multi_setup_parse "--solo review this plan" solo output_path input

  [ "$solo" = true ]
  [ "$input" = "review this plan" ]
}

@test "review-plan-multi parser preserves newlines in inline input" {
  local solo output_path input

  __cog_review_plan_multi_setup_parse $'first line\nsecond line' solo output_path input

  [ "$solo" = false ]
  [ "$input" = $'first line\nsecond line' ]
}

@test "review-plan-multi parser honours -- terminator for dash-leading text" {
  local solo output_path input

  __cog_review_plan_multi_setup_parse "-- -starts-with-dash" solo output_path input

  [ "$solo" = false ]
  [ "$input" = "-starts-with-dash" ]
}

@test "review-plan-multi parser accepts output and solo in either order" {
  local solo output_path input
  __cog_review_plan_multi_setup_parse "--output /tmp/review.md --solo plan text" solo output_path input
  [ "$solo" = true ]
  [ "$output_path" = /tmp/review.md ]
  [ "$input" = "plan text" ]
}

# review-plan-multi-setup and cog plan-gate share one classifier, so the setup
# surface and the plan gate can never disagree about what input form was passed.
# The setup surface accepts only file and inline and rejects the directory form
# the classifier still reports for cog plan-gate.
@test "review-plan-multi classifier detects file, dir, and inline" {
  local f="${BATS_TEST_TMPDIR}/plan.md" d="${BATS_TEST_TMPDIR}/plandir"
  printf '# Plan\n' >"$f"
  mkdir -p "$d"

  run cog::fn::plan_gate::classify_input "$f"
  assert_success
  [[ $output == file*"$f" ]]

  run cog::fn::plan_gate::classify_input "$d"
  assert_success
  [[ $output == dir*"$d" ]]

  run cog::fn::plan_gate::classify_input "some inline plan text"
  assert_success
  [[ $output == inline* ]]
}
