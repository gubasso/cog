setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR REFACTOR_GUIDELINE
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/repo" "${BATS_TEST_TMPDIR}/bin"
  export CARGO_LOG="${BATS_TEST_TMPDIR}/cargo.log"
  printf '[package]\nname = "x"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"
}

# Install a fake `cargo` early in PATH that logs its args and behaves per FAKE_MODE.
_install_fake_cargo() {
  cat >"${BATS_TEST_TMPDIR}/bin/cargo" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CARGO_LOG"
case "$1 $2" in
  "publish --dry-run")
    [ "${FAKE_MODE:-ok}" = "dryfail" ] && { echo "dry-run error" >&2; exit 1; }
    echo "Packaging x v0.1.0"
    ;;
  "package --list")
    printf '%s\n' Cargo.toml src/lib.rs README.md
    ;;
  *) echo "unexpected: $*" >&2; exit 2 ;;
esac
FAKE
  chmod +x "${BATS_TEST_TMPDIR}/bin/cargo"
  export PATH="${BATS_TEST_TMPDIR}/bin:$PATH"
}

@test "cog cargo-publish-check reports go on a clean dry-run" {
  _install_fake_cargo

  run env FAKE_MODE=ok cog cargo-publish-check --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .dry_run.command == "cargo publish --dry-run" and .package_list.files == 3' >/dev/null
  # never a bare `cargo publish`
  run ! grep -qx 'publish' "$CARGO_LOG"
}

@test "cog cargo-publish-check reports no-go when dry-run fails" {
  _install_fake_cargo

  run env FAKE_MODE=dryfail cog cargo-publish-check --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .dry_run.ok == false' >/dev/null
}

@test "cog cargo-publish-check reports absent cargo when unreachable" {
  # Drop only cargo's directory from PATH so cog/jq/coreutils stay reachable.
  local cargo_bin cargo_dir jq_dir newpath
  cargo_bin="$(command -v cargo || true)"
  [ -n "$cargo_bin" ] || skip "no cargo on PATH; absent branch is already the default"
  cargo_dir="$(dirname "$cargo_bin")"
  jq_dir="$(dirname "$(command -v jq)")"
  [ "$cargo_dir" != "$jq_dir" ] || skip "cargo and jq share a directory"
  newpath="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$cargo_dir" | paste -sd: -)"

  run env PATH="$newpath" cog cargo-publish-check --project-root "${BATS_TEST_TMPDIR}/repo" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and .cargo_runner == "absent"' >/dev/null
}

@test "cog cargo-publish-check rejects a non-directory project root" {
  run cog cargo-publish-check --project-root "${BATS_TEST_TMPDIR}/repo/nope" --json

  assert_failure
  printf '%s\n' "$output" | jq -e '.ok == false and (.reason|type=="string")' >/dev/null
}

@test "cog cargo-publish-check --help dispatches" {
  run cog cargo-publish-check --help

  assert_success
  [[ $output == *"Run cargo publish dry-run readiness checks"* ]]
}
