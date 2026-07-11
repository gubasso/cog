setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  source "${LIB_DIR}/functions/fn_env.sh"

  ROOT="${BATS_TEST_TMPDIR}/proj"
  mkdir -p "$ROOT"
  FAKEBIN="${BATS_TEST_TMPDIR}/fakebin"
  mkdir -p "$FAKEBIN"
  export DIRENV_LOG="${BATS_TEST_TMPDIR}/direnv.log"
  export NIX_LOG="${BATS_TEST_TMPDIR}/nix.log"
  : >"$DIRENV_LOG"
  : >"$NIX_LOG"

  # Stub direnv: records every call; `status --json` reports the allow state from
  # $DIRENV_STATUS_JSON; `exec <dir> <cmd...>` runs the wrapped command.
  cat >"$FAKEBIN/direnv" <<'SH'
#!/usr/bin/env bash
printf 'direnv %s\n' "$*" >>"$DIRENV_LOG"
case "$1" in
  status)
    [[ ${2:-} == --json ]] && { printf '%s\n' "${DIRENV_STATUS_JSON:-}"; exit 0; }
    printf '%s\n' "${DIRENV_STATUS_TEXT:-}"; exit 0 ;;
  exec)
    shift 2; exec "$@" ;;
esac
exit 0
SH

  # Stub nix: records every call; `develop <dir> --command <cmd...>` runs it.
  cat >"$FAKEBIN/nix" <<'SH'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >>"$NIX_LOG"
if [[ ${1:-} == develop ]]; then
  shift 2
  [[ ${1:-} == --command ]] && shift
  exec "$@"
fi
exit 0
SH
  chmod +x "$FAKEBIN/direnv" "$FAKEBIN/nix"
}

allow_direnv() { export DIRENV_STATUS_JSON='{"state":{"foundRC":{"allowed":0}}}'; }
block_direnv() { export DIRENV_STATUS_JSON='{"state":{"foundRC":{"allowed":1}}}'; }

@test "runner is bare when neither .envrc nor flake.nix exists" {
  PATH="$FAKEBIN:$PATH" run cog::fn::env::runner "$ROOT"
  assert_success
  [[ $output == bare ]]
}

@test "runner is nix-develop with flake.nix and nix on PATH, no .envrc" {
  : >"$ROOT/flake.nix"
  PATH="$FAKEBIN:$PATH" run cog::fn::env::runner "$ROOT"
  assert_success
  [[ $output == nix-develop ]]
}

@test "runner is direnv with an allowed .envrc" {
  : >"$ROOT/.envrc"
  allow_direnv
  PATH="$FAKEBIN:$PATH" run cog::fn::env::runner "$ROOT"
  assert_success
  [[ $output == direnv ]]
}

@test "runner falls back to nix-develop when .envrc is blocked" {
  : >"$ROOT/.envrc"
  : >"$ROOT/flake.nix"
  block_direnv
  PATH="$FAKEBIN:$PATH" run cog::fn::env::runner "$ROOT"
  assert_success
  [[ $output == nix-develop ]]
}

@test "runner falls back to bare when .envrc is blocked and no flake" {
  : >"$ROOT/.envrc"
  block_direnv
  PATH="$FAKEBIN:$PATH" run cog::fn::env::runner "$ROOT"
  assert_success
  [[ $output == bare ]]
}

@test "COG_ENV_RUNNER overrides file detection" {
  : >"$ROOT/.envrc"
  : >"$ROOT/flake.nix"
  allow_direnv
  COG_ENV_RUNNER=bare PATH="$FAKEBIN:$PATH" run cog::fn::env::runner "$ROOT"
  assert_success
  [[ $output == bare ]]
}

@test "exec bare runs the command unwrapped without changing directory" {
  local here="${BATS_TEST_TMPDIR}/here"
  mkdir -p "$here"
  run bash -c "cd '${here}'; source '${LIB_DIR}/functions/fn_env.sh'; cog::fn::env::exec '${ROOT}' bare -- pwd"
  assert_success
  [[ $output == "$here" ]]
}

@test "exec direnv wraps the command in direnv exec" {
  PATH="$FAKEBIN:$PATH" run cog::fn::env::exec "$ROOT" direnv -- printf hello
  assert_success
  [[ $output == hello ]]
  grep -q "direnv exec ${ROOT} printf hello" "$DIRENV_LOG"
}

@test "exec nix-develop wraps the command in nix develop --command" {
  PATH="$FAKEBIN:$PATH" run cog::fn::env::exec "$ROOT" nix-develop -- printf hello
  assert_success
  [[ $output == hello ]]
  grep -q "nix develop ${ROOT} --command printf hello" "$NIX_LOG"
}

@test "exec passes stdin through to the wrapped command" {
  run bash -c "source '${LIB_DIR}/functions/fn_env.sh'; printf 'piped' | cog::fn::env::exec '${ROOT}' bare -- cat"
  assert_success
  [[ $output == piped ]]
}
