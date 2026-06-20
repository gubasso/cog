setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/xdg"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_skill_refs.sh"
}

normalize_path() {
  cd -P "$1" && pwd
}

@test "skill_refs_root prefers XDG candidate" {
  local xdg_root="${XDG_DATA_HOME}/cog/skill-refs"
  local repo_root="${BATS_TEST_TMPDIR}/repo/skill-refs"
  # shellcheck disable=SC2030 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export LIB_DIR="${BATS_TEST_TMPDIR}/repo/lib"
  mkdir -p "$xdg_root" "$repo_root"

  run cog::fn::skill_refs_root

  assert_success
  assert_output "$(normalize_path "$xdg_root")"
}

@test "skill_refs_root falls back to repo source candidate" {
  local repo_root="${BATS_TEST_TMPDIR}/app/skill-refs"
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export LIB_DIR="${BATS_TEST_TMPDIR}/app/lib"
  mkdir -p "$LIB_DIR" "$repo_root"

  run cog::fn::skill_refs_root

  assert_success
  assert_output "$(normalize_path "$repo_root")"
}

@test "skill_refs_root returns nonzero and empty stdout when unresolved" {
  # shellcheck disable=SC2031 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export LIB_DIR="${BATS_TEST_TMPDIR}/app/lib"

  run cog::fn::skill_refs_root

  assert_failure
  assert_output ""
}

@test "skill_refs_path resolves existing relative path" {
  local xdg_root="${XDG_DATA_HOME}/cog/skill-refs"
  mkdir -p "$xdg_root/foo"
  printf '%s\n' "ref" >"${xdg_root}/foo/bar.md"

  run cog::fn::skill_refs_path foo/bar.md

  assert_success
  assert_output "$(normalize_path "$xdg_root")/foo/bar.md"
}

@test "skill_refs_path fails closed for missing and invalid rel paths" {
  local xdg_root="${XDG_DATA_HOME}/cog/skill-refs"
  mkdir -p "$xdg_root"

  run cog::fn::skill_refs_path missing.md
  assert_failure
  assert_output ""

  run cog::fn::skill_refs_path /etc/passwd
  assert_failure
  assert_output ""

  run cog::fn::skill_refs_path ../x
  assert_failure
  assert_output ""
}
