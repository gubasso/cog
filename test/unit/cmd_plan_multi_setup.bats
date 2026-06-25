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
  source "${LIB_DIR}/functions/fn_research.sh"
  source "${LIB_DIR}/functions/fn_plan_slug.sh"
  source "${LIB_DIR}/functions/fn_plan_artifact.sh"
  source "${LIB_DIR}/commands/cmd_plan_multi_setup.sh"
}

@test "plan-multi parser extracts solo output research root and orientation" {
  local solo output research_root orientation

  __cog_plan_multi_setup_parse "--solo --output /tmp/final.md --research-root /tmp/research Do work" \
    solo output research_root orientation

  [ "$solo" = true ]
  [ "$output" = "/tmp/final.md" ]
  [ "$research_root" = "/tmp/research" ]
  [ "$orientation" = "Do work" ]
}

@test "plan-multi parser defaults optional flags" {
  local solo output research_root orientation

  __cog_plan_multi_setup_parse "Do work" solo output research_root orientation

  [ "$solo" = false ]
  [ "$output" = "" ]
  [ "$research_root" = "" ]
  [ "$orientation" = "Do work" ]
}

@test "plan-multi parser preserves orientation newlines and repeated whitespace verbatim" {
  local solo output research_root orientation
  local raw
  raw=$'--solo build a   foo\nwith newlines and   spaces'

  __cog_plan_multi_setup_parse "$raw" solo output research_root orientation

  [ "$solo" = true ]
  [ "$orientation" = $'build a   foo\nwith newlines and   spaces' ]
}

@test "plan-multi parser honors terminator for dash-leading orientation" {
  local solo output research_root orientation

  __cog_plan_multi_setup_parse "-- -starts-with-dash" solo output research_root orientation

  [ "$solo" = false ]
  [ "$output" = "" ]
  [ "$research_root" = "" ]
  [ "$orientation" = "-starts-with-dash" ]
}

@test "plan-multi parser rejects unknown flags with exit 2" {
  local solo output research_root orientation

  run --separate-stderr __cog_plan_multi_setup_parse "--bogus Do work" solo output research_root orientation

  assert_failure 2
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "plan-multi parser rejects relative output as InvalidInput" {
  local solo output research_root orientation

  run --separate-stderr __cog_plan_multi_setup_parse "--output relative.md Do work" solo output research_root orientation

  assert_failure
  [[ $status -ne 2 ]]
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}
