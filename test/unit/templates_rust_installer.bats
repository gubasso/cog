#!/usr/bin/env bats
#
# Behavioural assertions over the shipped Rust installer template.
#
# `--locked` is an assertion, not a preference: cargo exits with an error when
# the lock file is missing
# (https://doc.rust-lang.org/cargo/commands/cargo-install.html#option-cargo-install---locked).
# The template shipped passing --locked unconditionally while its own preflight
# promised that a missing Cargo.lock merely warns and resolves afresh, so a
# freshly scaffolded crate could not be installed at all. These tests drive the
# template against a stub `cargo` and assert the argv it actually builds, which
# is the only thing that distinguishes the three lockfile branches.

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  INSTALLER_TEMPLATES="${BATS_TEST_DIRNAME}/../../skill-refs/templates/installer"

  PROJECT="${BATS_TEST_TMPDIR}/project"
  mkdir -p "$PROJECT/bin"
  cp "${INSTALLER_TEMPLATES}/install-common.sh" "${INSTALLER_TEMPLATES}/rust/install.sh" "$PROJECT/"
  cat >"$PROJECT/bin/cargo" <<'STUB'
#!/usr/bin/env bash
printf 'CARGO_ARGS: %s\n' "$*"
STUB
  chmod +x "$PROJECT/bin/cargo"
  PATH="$PROJECT/bin:$PATH"
  export HOME="$BATS_TEST_TMPDIR"
}

_run_installer() {
  cd "$PROJECT" || return 1
  run bash install.sh
}

# The argv line alone. The surrounding prose mentions `--locked` by name, so a
# whole-output match would not distinguish the branches.
_cargo_args() {
  printf '%s\n' "$output" | sed -n 's/^CARGO_ARGS: //p'
}

@test "rust installer passes --locked when the project has a Cargo.lock" {
  touch "$PROJECT/Cargo.lock"

  _run_installer

  assert_success
  [ "$(_cargo_args)" = "install --path ${PROJECT} --force --locked" ]
}

@test "rust installer drops --locked when the project has no Cargo.lock" {
  # Keeping --locked here would make cargo exit with an error, contradicting the
  # warning the same branch prints.
  _run_installer

  assert_success
  [ "$(_cargo_args)" = "install --path ${PROJECT} --force" ]
  [[ $output == *"no Cargo.lock"* ]]
}

@test "rust installer drops --locked under INSTALLER_LOCKED=0" {
  touch "$PROJECT/Cargo.lock"

  cd "$PROJECT" || return 1
  run env INSTALLER_LOCKED=0 bash install.sh

  assert_success
  [ "$(_cargo_args)" = "install --path ${PROJECT} --force" ]
  [[ $output == *"INSTALLER_LOCKED=0"* ]]
}
