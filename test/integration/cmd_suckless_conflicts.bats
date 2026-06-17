link_required_tool() {
  local tool="$1" target
  target="$(command -v "$tool")"
  ln -sf "$target" "${BATS_TEST_TMPDIR}/fakebin/$tool"
}

use_fakebin_only() {
  local tool
  for tool in bash jq dirname readlink pwd date mkdir; do
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
  export GIT_FAKE_LOG="${BATS_TEST_TMPDIR}/git-argv.log"
  export GIT_FAKE_ROOT="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$GIT_FAKE_ROOT/.git" "$GIT_FAKE_ROOT/sub" "${BATS_TEST_TMPDIR}/fakebin"
  cat >"${BATS_TEST_TMPDIR}/fakebin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GIT_FAKE_LOG"
case "$*" in
  "rev-parse --show-toplevel") printf '%s\n' "$GIT_FAKE_ROOT" ;;
  *) printf 'unexpected git args: %s\n' "$*" >&2; exit 2 ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/git"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
}

@test "cog suckless-conflicts lists rejects and orig files" {
  printf '%s\n' one two >"$GIT_FAKE_ROOT/dwm.c.rej"
  printf '%s\n' backup >"$GIT_FAKE_ROOT/dwm.c.orig"
  printf '%s\n' sub >"$GIT_FAKE_ROOT/sub/config.h.rej"
  printf '%s\n' ignored >"$GIT_FAKE_ROOT/.git/ignored.rej"

  run cog suckless-conflicts --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true and .count == 2 and
    (.rejects[] | select(.path == "dwm.c.rej" and .target == "dwm.c" and .lines == 2)) and
    (.rejects[] | select(.path == "sub/config.h.rej" and .target == "sub/config.h" and .lines == 1)) and
    (.orig_files | index("dwm.c.orig")) and
    ([.rejects[].path] | index(".git/ignored.rej") | not)
  ' >/dev/null
}

@test "cog suckless-conflicts fails closed when git is missing" {
  local tight_path
  rm -f "${BATS_TEST_TMPDIR}/fakebin/git"
  tight_path="$(use_fakebin_only)"

  run --separate-stderr env PATH="$tight_path" "${BATS_TEST_DIRNAME}/../../bin/cog" suckless-conflicts --json

  assert_failure
  [[ $stderr == *"err.kind: MissingRequirement"* ]]
  [[ $stderr == *"command: git"* ]]
}
