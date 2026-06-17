link_required_tool() {
  local tool="$1" target
  target="$(command -v "$tool")"
  ln -sf "$target" "${BATS_TEST_TMPDIR}/fakebin/$tool"
}

use_fakebin_only() {
  local tool
  for tool in bash jq sed grep mktemp head dirname readlink pwd date mkdir; do
    link_required_tool "$tool"
  done
  printf '%s\n' "${BATS_TEST_TMPDIR}/fakebin"
}

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export OSC_FAKE_LOG="${BATS_TEST_TMPDIR}/osc-argv.log"
  export TIMEOUT_FAKE_LOG="${BATS_TEST_TMPDIR}/timeout-argv.log"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/timeout" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TIMEOUT_FAKE_LOG"
shift
"$@"
EOF
  cat >"${BATS_TEST_TMPDIR}/fakebin/osc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OSC_FAKE_LOG"
case "${OSC_FAKE_MODE:-single}" in
  single)
    printf '%s\n' '<collection><binary name="gcc-c++" package="gcc14" project="openSUSE:Factory"/></collection>'
    ;;
  same)
    printf '%s\n' '<collection><binary name="demo" package="demo" project="openSUSE:Factory"/></collection>'
    ;;
  empty)
    printf '%s\n' '<collection></collection>'
    ;;
  ambiguous)
    printf '%s\n' '<binary name="demo" package="one" project="p"/><binary name="demo" package="two" project="p"/>'
    ;;
  fail)
    printf '%s\n' 'probe failed' >&2
    exit 7
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/timeout" "${BATS_TEST_TMPDIR}/fakebin/osc"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
}

@test "cog osc-probe-binary resolves source package and records encoded query" {
  run cog osc-probe-binary --binary 'gcc-c++' --project 'openSUSE:Factory' --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .source_package == "gcc14" and .source_differs == true' >/dev/null
  assert_file_contains "$OSC_FAKE_LOG" '/search/published/binary/id?match=@name="gcc-c%2B%2B"+and+@project="openSUSE%3AFactory"'
}

@test "cog osc-probe-binary marks source_differs false for same package" {
  # shellcheck disable=SC2030 # Each bats @test runs in its own subshell; exporting the fake mode here is intentional.
  export OSC_FAKE_MODE=same

  run cog osc-probe-binary --binary demo --project p --json

  assert_success
  printf '%s\n' "$output" | jq -e '.source_package == "demo" and .source_differs == false' >/dev/null
}

@test "cog osc-probe-binary reports not found and ambiguity" {
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting the fake mode here is intentional.
  export OSC_FAKE_MODE=empty
  run --separate-stderr cog osc-probe-binary --binary demo --project p --json
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "binary not found in published search"' >/dev/null

  export OSC_FAKE_MODE=ambiguous
  run --separate-stderr cog osc-probe-binary --binary demo --project p --json
  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "ambiguous source package"' >/dev/null
}

@test "cog osc-probe-binary captures probe failure" {
  # shellcheck disable=SC2031 # Each bats @test runs in its own subshell; exporting the fake mode here is intentional.
  export OSC_FAKE_MODE=fail

  run --separate-stderr cog osc-probe-binary --binary demo --project p --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.probe.status == "fail" and .probe.exit_code == 7 and (.probe.stderr | contains("probe failed"))' >/dev/null
}

@test "cog osc-probe-binary reports missing osc" {
  local tight_path
  rm -f "${BATS_TEST_TMPDIR}/fakebin/osc"
  tight_path="$(use_fakebin_only)"

  run --separate-stderr env PATH="$tight_path" "${BATS_TEST_DIRNAME}/../../bin/cog" osc-probe-binary --binary demo --project p --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "osc binary missing" and .probe.status == "skip"' >/dev/null
}

@test "cog osc-probe-binary reports missing timeout" {
  local tight_path
  rm -f "${BATS_TEST_TMPDIR}/fakebin/timeout"
  tight_path="$(use_fakebin_only)"

  run --separate-stderr env PATH="$tight_path" "${BATS_TEST_DIRNAME}/../../bin/cog" osc-probe-binary --binary demo --project p --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .reason == "timeout command missing" and .probe.status == "fail"' >/dev/null
}
