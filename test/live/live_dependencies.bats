setup() {
  bats_require_minimum_version 1.5.0
  load "${BATS_TEST_DIRNAME}/../test_helper/bats-support/load"
  load "${BATS_TEST_DIRNAME}/../test_helper/bats-assert/load"
}

require_live_tests() {
  [[ "${COG_LIVE_TESTS:-}" == "1" ]] || skip "set COG_LIVE_TESTS=1 to run live tests"
  return 0
}

require_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null || skip "$tool not installed"
  return 0
}

@test "git boundary is available" {
  local tmpdir

  require_live_tests
  require_tool git

  run git --version
  assert_success

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN
  run git -C "$tmpdir" init
  assert_success
  printf '%s\n' "live" >"$tmpdir/README.md"
  run git -C "$tmpdir" add README.md
  assert_success
  run git -C "$tmpdir" -c user.name="Cog Live Test" -c user.email="cog-live@example.invalid" commit -m "initial"
  assert_success
  run bash -c 'cd "$1" && "$2/bin/cog" tsk-snapshot --json' _ "$tmpdir" "${BATS_TEST_DIRNAME}/../.."
  assert_success
}

@test "gh boundary is available" {
  require_live_tests
  require_tool gh

  run gh --version
  assert_success
}

@test "codex-session boundary is available" {
  require_live_tests
  require_tool codex-session

  run codex-session --help
  assert_success
}
