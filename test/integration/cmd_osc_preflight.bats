link_required_tool() {
  local tool="$1" target
  target="$(command -v "$tool")"
  ln -sf "$target" "${BATS_TEST_TMPDIR}/fakebin/$tool"
}

use_fakebin_only() {
  local tool
  for tool in bash jq awk sed grep mktemp head dirname readlink pwd date mkdir; do
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
  export OBS_HOME_PROJECT="home:test:project"
  export OBS_WORKSPACE="${BATS_TEST_TMPDIR}/obs-work"
  export OBS_BUILD_VC="${BATS_TEST_TMPDIR}/vc"
  export OSC_FAKE_LOG="${BATS_TEST_TMPDIR}/osc-argv.log"
  export TIMEOUT_FAKE_LOG="${BATS_TEST_TMPDIR}/timeout-argv.log"
  mkdir -p "$HOME/.config/osc" "$XDG_STATE_HOME" "$OBS_WORKSPACE" "${BATS_TEST_TMPDIR}/fakebin"
  printf '%s\n' "[https://api.opensuse.org]" "user = testuser" >"$HOME/.config/osc/oscrc"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$OBS_BUILD_VC"
  chmod +x "$OBS_BUILD_VC"
  cat >"${BATS_TEST_TMPDIR}/fakebin/timeout" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TIMEOUT_FAKE_LOG"
shift
"$@"
EOF
  cat >"${BATS_TEST_TMPDIR}/fakebin/osc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OSC_FAKE_LOG"
exit "${OSC_FAKE_EXIT:-0}"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/timeout" "${BATS_TEST_TMPDIR}/fakebin/osc"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
}

@test "cog osc-preflight passes and records osc probes" {
  run cog osc-preflight --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.checks[] | .status == "pass")' >/dev/null
  run grep -F -- "-A https://api.opensuse.org api /person/testuser" "$OSC_FAKE_LOG"
  assert_success
  run grep -F -- "-A https://api.opensuse.org meta prj home:test:project" "$OSC_FAKE_LOG"
  assert_success
  run grep -F -- "15s osc -A https://api.opensuse.org api /person/testuser" "$TIMEOUT_FAKE_LOG"
  assert_success
}

@test "cog osc-preflight fails closed without OBS_HOME_PROJECT" {
  unset OBS_HOME_PROJECT

  run --separate-stderr cog osc-preflight --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .checks.env.status == "fail" and .checks.home_project.status == "skip" and .reason == "missing OBS_HOME_PROJECT"' >/dev/null
}

@test "cog osc-preflight reports missing osc" {
  local tight_path
  rm -f "${BATS_TEST_TMPDIR}/fakebin/osc"
  tight_path="$(use_fakebin_only)"

  run --separate-stderr env PATH="$tight_path" "${BATS_TEST_DIRNAME}/../../bin/cog" osc-preflight --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .checks.osc_binary.status == "fail" and .checks.auth_probe.status == "skip" and .checks.home_project.status == "skip"' >/dev/null
}

@test "cog osc-preflight reports missing timeout" {
  local tight_path
  rm -f "${BATS_TEST_TMPDIR}/fakebin/timeout"
  tight_path="$(use_fakebin_only)"

  run --separate-stderr env PATH="$tight_path" "${BATS_TEST_DIRNAME}/../../bin/cog" osc-preflight --json

  assert_failure
  printf '%s\n' "$output" | jq -e '
    .ok == false and
    .checks.auth_probe.status == "fail" and
    .checks.auth_probe.reason == "timeout command missing" and
    (.checks.auth_probe.remediation | contains("Install coreutils timeout")) and
    .checks.home_project.status == "fail" and
    .checks.home_project.reason == "timeout command missing"
  ' >/dev/null
}

@test "cog osc-preflight writes a fragment" {
  local out="${BATS_TEST_TMPDIR}/osc-preflight.json"

  run cog osc-preflight "$out"

  assert_success
  assert_output "RESOLVED $out"
  jq -e '.ok == true and .home_project == "home:test:project"' "$out" >/dev/null
}
