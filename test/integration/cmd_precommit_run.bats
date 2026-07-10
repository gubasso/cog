link_required_tool() {
  local tool="$1" target
  target="$(command -v "$tool")"
  ln -sf "$target" "${BATS_TEST_TMPDIR}/fakebin/$tool"
}

# fakebin with cog's boot tools but deliberately no pre-commit, so __have
# pre-commit resolves nowhere on PATH.
use_fakebin_only() {
  local tool
  for tool in bash jq mktemp cp mv dirname readlink pwd head date mkdir sed grep git; do
    link_required_tool "$tool"
  done
  printf '%s\n' "${BATS_TEST_TMPDIR}/fakebin"
}

require_precommit() {
  command -v pre-commit >/dev/null 2>&1 || skip "pre-commit is not installed"
}

# Initialise a throwaway git repo under $1 with a local system-language config.
# $2 is the failing entry ("pass" leaves every hook green).
make_repo() {
  local root="$1" mode="${2:-pass}" fail_entry="exit 0"
  [[ $mode == fail ]] && fail_entry="echo SC2086 bad; exit 1"
  git init -q "$root"
  git -C "$root" config user.email t@t.co
  git -C "$root" config user.name t
  cat >"$root/.pre-commit-config.yaml" <<YAML
repos:
  - repo: local
    hooks:
      - id: commit-check
        name: commit check
        entry: bash -c '${fail_entry}'
        language: system
        pass_filenames: false
        stages: [pre-commit]
      - id: push-ok
        name: push ok
        entry: bash -c 'exit 0'
        language: system
        pass_filenames: false
        stages: [pre-push]
YAML
  printf '%s\n' 'placeholder' >"$root/file.txt"
  git -C "$root" add -A
}

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin" "${BATS_TEST_TMPDIR}/repo"
}

@test "cog precommit-run --help dispatches" {
  run cog precommit-run --help

  assert_success
  [[ $output == *"Usage: cog precommit-run"* ]]
}

@test "cog precommit-run fails closed when pre-commit is missing" {
  local tight_path
  tight_path="$(use_fakebin_only)"

  run --separate-stderr env PATH="$tight_path" "${BATS_TEST_DIRNAME}/../../bin/cog" \
    precommit-run --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  [[ $stderr == *"err.kind: MissingRequirement"* ]]
  [[ $stderr == *"command: pre-commit"* ]]
}

@test "cog precommit-run reports a clean tree as ok" {
  require_precommit
  make_repo "${BATS_TEST_TMPDIR}/clean" pass

  run cog precommit-run --project-root "${BATS_TEST_TMPDIR}/clean" \
    --log "${BATS_TEST_TMPDIR}/clean.log" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .installed == true and (.failed_hooks | length) == 0 and (.stages | index("pre-commit")) and (.stages | index("pre-push"))' >/dev/null
}

@test "cog precommit-run collects failing hooks" {
  require_precommit
  make_repo "${BATS_TEST_TMPDIR}/dirty" fail

  run --separate-stderr cog precommit-run --project-root "${BATS_TEST_TMPDIR}/dirty" \
    --log "${BATS_TEST_TMPDIR}/dirty.log" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.failed_hooks | index("hook:commit-check")) and .classification.class == "content-fix"' >/dev/null
  [ -s "${BATS_TEST_TMPDIR}/dirty.log" ]
}

@test "cog precommit-run --stage restricts to the named stage" {
  require_precommit
  make_repo "${BATS_TEST_TMPDIR}/staged" pass

  run cog precommit-run --project-root "${BATS_TEST_TMPDIR}/staged" \
    --stage pre-push --log "${BATS_TEST_TMPDIR}/staged.log" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.stages == ["pre-push"]' >/dev/null
}

@test "cog precommit-run -s is repeatable and preserves stage order" {
  require_precommit
  make_repo "${BATS_TEST_TMPDIR}/multi" pass

  run cog precommit-run --project-root "${BATS_TEST_TMPDIR}/multi" \
    -s pre-push -s pre-commit --log "${BATS_TEST_TMPDIR}/multi.log" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.stages == ["pre-push", "pre-commit"]' >/dev/null
}

@test "cog precommit-run returns a reason when config is missing" {
  require_precommit
  git init -q "${BATS_TEST_TMPDIR}/nocfg"

  run --separate-stderr cog precommit-run --project-root "${BATS_TEST_TMPDIR}/nocfg" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.reason | startswith("no .pre-commit-config.yaml"))' >/dev/null
}

@test "cog precommit-run returns a reason outside a git repo" {
  require_precommit

  run --separate-stderr cog precommit-run --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "not a git repository"' >/dev/null
}
