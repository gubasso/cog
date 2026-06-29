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
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_data.sh"
}

normalize_path() {
  cd -P "$1" && pwd
}

@test "data_root prefers XDG candidate" {
  local xdg_root="${XDG_DATA_HOME}/cog/data"
  local repo_root="${BATS_TEST_TMPDIR}/repo/data"
  # shellcheck disable=SC2030 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export LIB_DIR="${BATS_TEST_TMPDIR}/repo/lib"
  mkdir -p "$xdg_root" "$repo_root"

  run cog::fn::data_root

  assert_success
  assert_output "$(normalize_path "$xdg_root")"
}

@test "data_root falls back to repo source candidate" {
  local repo_root="${BATS_TEST_TMPDIR}/app/data"
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export LIB_DIR="${BATS_TEST_TMPDIR}/app/lib"
  mkdir -p "$LIB_DIR" "$repo_root"

  run cog::fn::data_root

  assert_success
  assert_output "$(normalize_path "$repo_root")"
}

@test "data_root returns nonzero and empty stdout when unresolved" {
  # shellcheck disable=SC2031 # Each bats @test runs in its own subshell; exporting the env here is intentional.
  export LIB_DIR="${BATS_TEST_TMPDIR}/app/lib"

  run cog::fn::data_root

  assert_failure
  assert_output ""
}

@test "data path resolves existing relative path and rejects invalid paths" {
  local xdg_root="${XDG_DATA_HOME}/cog/data"
  mkdir -p "$xdg_root/foo"
  printf '%s\n' "name: demo" >"${xdg_root}/foo/bar.yaml"

  run cog::fn::data::path foo/bar.yaml
  assert_success
  assert_output "$(normalize_path "$xdg_root")/foo/bar.yaml"

  run cog::fn::data::path missing.yaml
  assert_failure
  assert_output ""

  run cog::fn::data::path /etc/passwd
  assert_failure
  assert_output ""

  run cog::fn::data::path ../x
  assert_failure
  assert_output ""
}

@test "load_dir loads a single YAML file" {
  local file="${BATS_TEST_TMPDIR}/one.yaml"
  printf '%s\n' "name: demo" "count: 3" >"$file"

  run cog::fn::data::load_dir "$file"

  assert_success
  printf '%s\n' "$output" | jq -e '.name == "demo" and .count == 3' >/dev/null
}

@test "load_dir merges sorted YAML files" {
  local dir="${BATS_TEST_TMPDIR}/dataset"
  mkdir -p "$dir"
  printf '%s\n' "zeta: 1" >"$dir/z.yaml"
  printf '%s\n' "alpha:" "  nested: true" >"$dir/a.yaml"

  run cog::fn::data::load_dir "$dir"

  assert_success
  printf '%s\n' "$output" | jq -e '.alpha.nested == true and .zeta == 1' >/dev/null
}

@test "load_dir ignores empty and comment-only YAML files" {
  local dir="${BATS_TEST_TMPDIR}/dataset"
  mkdir -p "$dir"
  printf '%s\n' "# docs only" >"$dir/a.yaml"
  : >"$dir/b.yaml"
  printf '%s\n' "name: demo" >"$dir/c.yaml"

  run cog::fn::data::load_dir "$dir"

  assert_success
  printf '%s\n' "$output" | jq -e '. == {"name":"demo"}' >/dev/null
}

@test "load_dir rejects duplicate top-level keys" {
  local dir="${BATS_TEST_TMPDIR}/dataset"
  mkdir -p "$dir"
  printf '%s\n' "name: first" >"$dir/a.yaml"
  printf '%s\n' "name: second" >"$dir/b.yaml"

  run --separate-stderr cog::fn::data::load_dir "$dir"

  assert_failure 65
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "load_dir rejects invalid YAML" {
  local file="${BATS_TEST_TMPDIR}/bad.yaml"
  printf '%s\n' "name: {" >"$file"

  run --separate-stderr cog::fn::data::load_dir "$file"

  assert_failure 65
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "load_dir rejects missing path" {
  run --separate-stderr cog::fn::data::load_dir "${BATS_TEST_TMPDIR}/missing"

  assert_failure 66
  [[ $stderr == *"err.kind: InputNotFound"* ]]
}
