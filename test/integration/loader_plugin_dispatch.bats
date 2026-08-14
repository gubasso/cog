#!/usr/bin/env bats
#
# Precedence, verbatim passthrough, and the two error regimes at the dispatch
# seam. Before exec, failures are cog's and use cog's sysexits; after exec, the
# exit code is the plugin's alone.
#
# Every test builds its own PATH under BATS_TEST_TMPDIR, after _common_setup has
# prepended the repo's bin/.

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  FIXTURES="${REPO_ROOT}/test/fixtures/plugins"

  PLUGIN_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$PLUGIN_BIN"
  local clean_path
  clean_path="$(path_without_plugins "$PATH")"
  export PATH="${PLUGIN_BIN}:${clean_path}"
  unset COG_PLUGIN_DIR
}

path_without_plugins() {
  local dir out=""
  while IFS= read -r dir; do
    [[ -n $dir ]] || continue
    compgen -G "${dir}/cog-*" >/dev/null 2>&1 && continue
    out+="${dir}:"
  done < <(printf '%s' "$1" | tr ':' '\n')
  printf '%s' "${out%:}"
}

install_fixture() {
  local fixture="$1" name="${2:-}"
  [[ -n $name ]] || name="$fixture"
  cp "${FIXTURES}/cog-${fixture}" "${PLUGIN_BIN}/cog-${name}"
  chmod 0755 "${PLUGIN_BIN}/cog-${name}"
}

# --- precedence ------------------------------------------------------------------

@test "a first-party command wins even when a same-named plugin resolves first" {
  install_fixture good plan-slug

  run cog plan-slug --help

  assert_success
  assert_output --partial "Usage: cog plan-slug"
  refute_output --partial "good:"
}

# --- passthrough -----------------------------------------------------------------

@test "argv passes verbatim and the plugin's exit code is cog's" {
  install_fixture echoargs

  run cog echoargs a b c 0
  assert_success
  assert_output "a
b
c
0"
}

@test "exit codes that collide with cog's sysexits pass through unmodified" {
  install_fixture echoargs
  local code

  for code in 1 64 69 70; do
    run cog echoargs "$code"
    assert_equal "$status" "$code"
  done
}

@test "cog's global flags are consumed before the command name and never forwarded" {
  install_fixture echoargs

  run cog --json echoargs x 0

  assert_success
  assert_output "x
0"
}

@test "plugin stderr reaches stderr and stdout reaches stdout, unannotated" {
  install_fixture streams

  run --separate-stderr cog streams

  assert_success
  assert_output "to stdout"
  assert_equal "$stderr" "to stderr"
}

@test "a plugin receives exactly the four contract variables" {
  install_fixture envdump
  local received

  # A pre-existing COG_ variable passes through untouched: cog exports its four
  # and scrubs nothing.
  COG_PREEXISTING=kept run cog envdump
  assert_success

  received="$(printf '%s\n' "$output" | grep -c '^COG_')"
  assert_equal "$received" "5"
  assert_line "COG_PLUGIN_PROTOCOL=1"
  assert_line "COG_PLUGIN_NAME=envdump"
  assert_line "COG_HOST_VERSION=$(<"${REPO_ROOT}/VERSION")"
  assert_line "COG_EXECUTABLE=${REPO_ROOT}/bin/cog"
  assert_line "COG_PREEXISTING=kept"
}

@test "COG_PLUGIN_DIR takes precedence over PATH at dispatch" {
  local dir="${BATS_TEST_TMPDIR}/plugins"
  mkdir -p "$dir"
  install_fixture noprobe echoargs
  cp "${FIXTURES}/cog-echoargs" "${dir}/cog-echoargs"
  chmod 0755 "${dir}/cog-echoargs"

  COG_PLUGIN_DIR="$dir" run cog echoargs hello 0

  assert_success
  assert_output "hello
0"
}

# --- the probe is never a gate ---------------------------------------------------

@test "a plugin with a broken probe still dispatches" {
  install_fixture noprobe

  run cog noprobe

  assert_success
  assert_output "noprobe ran"
}

@test "dispatch never runs the metadata probe" {
  install_fixture probemarker
  local marker="${BATS_TEST_TMPDIR}/probed"

  COG_PROBE_MARKER="$marker" run cog probemarker

  assert_success
  assert_output "probemarker ran"
  [[ ! -e $marker ]] || fail "dispatch invoked cog-plugin-metadata"
}

# --- errors before exec ----------------------------------------------------------

@test "an unknown command with no plugin present names both misses" {
  run cog nosuchthing

  assert_equal "$status" 64
  assert_output --partial "UnknownCommand"
  assert_output --partial "no readable command module and no executable cog-nosuchthing"
}

@test "a non-executable cog-<name> raises PluginNotExecutable rather than unknown command" {
  cp "${FIXTURES}/cog-good" "${PLUGIN_BIN}/cog-notexec"
  chmod 0644 "${PLUGIN_BIN}/cog-notexec"

  run cog notexec

  assert_equal "$status" 69
  assert_output --partial "PluginNotExecutable"
  refute_output --partial "UnknownCommand"
}

@test "a name failing the slug rule is still rejected before resolution" {
  run cog "Bad-Name"

  assert_equal "$status" 64
  assert_output --partial "BadCommandName"
}

# --- help ------------------------------------------------------------------------

@test "cog help <plugin> delegates to the plugin's own --help" {
  install_fixture good

  run cog help good

  assert_success
  assert_output "good: --help"
}

@test "cog help on a name with no module and no plugin still fails cleanly" {
  run cog help nosuchthing

  assert_equal "$status" 64
  assert_output --partial "UnknownCommand"
}

@test "cog --help is unchanged when plugins are present" {
  local before

  before="$(cog --help)"
  install_fixture good
  install_fixture noprobe

  run cog --help
  assert_success
  assert_output "$before"
  refute_output --partial "good"
  refute_output --partial "noprobe"
}

@test "a help flag after a plugin name is the plugin's argv, not cog's" {
  # Cog interprets nothing after a plugin name. The global help path used to
  # answer `-h`/`--help` for every command, which rewrote `cog good -h extra`
  # into `cog-good --help` — one argument changed and one dropped. `cog help
  # <plugin>` remains the documented delegation and is asserted separately.
  install_fixture good

  run cog good -h extra
  assert_success
  assert_output "good: -h extra"

  run cog good --help extra
  assert_success
  assert_output "good: --help extra"
}

@test "a help flag after a first-party command is still cog's to answer" {
  run cog plugin --help
  assert_success
  assert_output --partial "Usage: cog plugin"
}
