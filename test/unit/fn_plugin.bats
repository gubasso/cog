#!/usr/bin/env bats
#
# Resolution, rejection, environment construction, and the metadata probe.
#
# Every test builds its own PATH and COG_PLUGIN_DIR under BATS_TEST_TMPDIR,
# after _common_setup has prepended the repo's bin/. No test may observe the
# developer's real PATH: a cog-* executable someone happens to have installed
# would otherwise change the result.

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  FIXTURES="${REPO_ROOT}/test/fixtures/plugins"
  export LIB_DIR="${REPO_ROOT}/lib"
  export SCRIPT_DIR="${REPO_ROOT}/bin"

  PLUGIN_BIN="${BATS_TEST_TMPDIR}/bin"
  PLUGIN_ALT="${BATS_TEST_TMPDIR}/alt"
  PLUGIN_DIR="${BATS_TEST_TMPDIR}/plugins"
  mkdir -p "$PLUGIN_BIN" "$PLUGIN_ALT" "$PLUGIN_DIR"

  # The fixture directories in front of a PATH with every cog-* carrier dropped,
  # so the tools these tests need stay reachable while a plugin the developer
  # happens to have installed cannot change a discovery or resolution result.
  local clean_path
  clean_path="$(path_without_plugins "$PATH")"
  export PATH="${PLUGIN_BIN}:${PLUGIN_ALT}:${clean_path}"
  unset COG_PLUGIN_DIR

  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_plugin.sh"
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
  local fixture="$1" dir="$2" name="${3:-}"
  [[ -n $name ]] || name="$fixture"
  install -m 0755 "${FIXTURES}/cog-${fixture}" "${dir}/cog-${name}"
}

# --- the data table and the literals it publishes ------------------------------

@test "fn_plugin constants match the published data table" {
  local table="${REPO_ROOT}/data/plugin-protocol/protocol.yaml"

  assert_equal "$(yq e '.plugin-protocol.version' "$table")" "$(cog::fn::plugin_protocol_version)"
  assert_equal "$(yq e '.plugin-protocol.probe_timeout_seconds' "$table")" "$(cog::fn::plugin_probe_timeout)"
  assert_equal "$(yq e '.plugin-protocol.probe_output_cap_bytes' "$table")" "$(cog::fn::plugin_probe_cap)"
  assert_equal "$(yq e '.plugin-protocol.reserved_subcommand' "$table")" "$(cog::fn::plugin_reserved_subcommand)"
}

@test "every check name is published in the data table" {
  local table="${REPO_ROOT}/data/plugin-protocol/meta.yaml"
  local declared implemented

  declared="$(yq e '.plugin-protocol-checks | keys | .[]' "$table" | LC_ALL=C sort)"
  implemented="$(cog::fn::plugin_check_names | LC_ALL=C sort)"

  assert_equal "$implemented" "$declared"
}

# --- resolution ----------------------------------------------------------------

@test "COG_PLUGIN_DIR wins over PATH" {
  install_fixture good "$PLUGIN_DIR"
  install_fixture noprobe "$PLUGIN_BIN" good
  # shellcheck disable=SC2030 # Each bats @test runs in its own subshell; exporting here is intentional.
  export COG_PLUGIN_DIR="$PLUGIN_DIR"

  run cog::fn::plugin_resolve good

  assert_success
  assert_output "${PLUGIN_DIR}/cog-good"
}

@test "PATH resolves when COG_PLUGIN_DIR is unset, empty, or lacks the file" {
  install_fixture good "$PLUGIN_BIN"

  run cog::fn::plugin_resolve good
  assert_success
  assert_output "${PLUGIN_BIN}/cog-good"

  COG_PLUGIN_DIR="" run cog::fn::plugin_resolve good
  assert_success
  assert_output "${PLUGIN_BIN}/cog-good"

  COG_PLUGIN_DIR="$PLUGIN_DIR" run cog::fn::plugin_resolve good
  assert_success
  assert_output "${PLUGIN_BIN}/cog-good"
}

@test "an earlier PATH entry wins and the later one is still a candidate" {
  install_fixture good "$PLUGIN_BIN"
  install_fixture good "$PLUGIN_ALT"

  run cog::fn::plugin_resolve good
  assert_success
  assert_output "${PLUGIN_BIN}/cog-good"

  run cog::fn::plugin_candidates good
  assert_success
  assert_line --index 0 "${PLUGIN_BIN}/cog-good"
  assert_line --index 1 "${PLUGIN_ALT}/cog-good"
}

@test "a directory named cog-<name> is not resolved as a plugin" {
  mkdir -p "${PLUGIN_BIN}/cog-adir"

  run cog::fn::plugin_resolve adir
  assert_failure
  assert_output ""

  run cog::fn::plugin_state adir "${PLUGIN_BIN}/cog-adir"
  assert_success
  assert_output "not-executable"
}

@test "a mode-0644 file yields not-executable" {
  install -m 0644 "${FIXTURES}/cog-good" "${PLUGIN_BIN}/cog-notexec"

  run cog::fn::plugin_resolve notexec
  assert_failure

  run cog::fn::plugin_state notexec "${PLUGIN_BIN}/cog-notexec"
  assert_success
  assert_output "not-executable"
}

@test "a dangling symlink yields not-executable rather than a crash" {
  ln -s "${BATS_TEST_TMPDIR}/nothing-here" "${PLUGIN_BIN}/cog-dangling"

  run cog::fn::plugin_resolve dangling
  assert_failure

  run cog::fn::plugin_state dangling "${PLUGIN_BIN}/cog-dangling"
  assert_success
  assert_output "not-executable"
}

@test "a symlink to a real executable resolves to its absolute target" {
  install_fixture good "$PLUGIN_ALT" target
  ln -s "${PLUGIN_ALT}/cog-target" "${PLUGIN_BIN}/cog-linked"

  run cog::fn::plugin_resolve linked

  assert_success
  assert_output "${PLUGIN_ALT}/cog-target"
}

@test "a name failing the slug rule is rejected before any filesystem access" {
  run cog::fn::plugin_resolve "../etc/passwd"
  assert_failure
  assert_output ""

  run cog::fn::plugin_candidates "Bad-Name"
  assert_failure
  assert_output ""
}

@test "discover reports each name once, sorted" {
  install_fixture good "$PLUGIN_BIN"
  install_fixture good "$PLUGIN_ALT"
  install_fixture noprobe "$PLUGIN_ALT"
  : >"${PLUGIN_BIN}/cog-Bad"

  run cog::fn::plugin_discover

  assert_success
  assert_output "good
noprobe"
}

# --- environment ---------------------------------------------------------------

@test "plugin_env emits exactly four variables in a stable order" {
  run cog::fn::plugin_env demo

  assert_success
  assert_equal "${#lines[@]}" 4
  assert_line --index 0 "COG_PLUGIN_PROTOCOL=1"
  assert_line --index 1 "COG_HOST_VERSION=$(<"${REPO_ROOT}/VERSION")"
  assert_line --index 2 "COG_PLUGIN_NAME=demo"
  assert_line --index 3 "COG_EXECUTABLE=${REPO_ROOT}/bin/cog"
}

@test "plugin_env output contains no path under lib/" {
  run cog::fn::plugin_env demo

  assert_success
  refute_output --partial "/lib/functions"
  refute_output --partial "/lib/commands"
  refute_output --partial "LIB_DIR"
  refute_output --partial "SCRIPT_DIR"
}

# --- the probe -----------------------------------------------------------------

@test "plugin_probe returns the metadata object for a conformant plugin" {
  install_fixture good "$PLUGIN_BIN"

  run cog::fn::plugin_probe "${PLUGIN_BIN}/cog-good"

  assert_success
  assert_equal "$(jq -r '.name' <<<"$output")" "good"
  assert_equal "$(jq -r '.protocol' <<<"$output")" "1"
}

@test "plugin_probe fails silently on a non-zero probe exit" {
  install_fixture noprobe "$PLUGIN_BIN"

  run cog::fn::plugin_probe "${PLUGIN_BIN}/cog-noprobe"

  assert_failure
  assert_output ""
}

@test "plugin_probe fails silently on invalid JSON" {
  install_fixture badjson "$PLUGIN_BIN"

  run cog::fn::plugin_probe "${PLUGIN_BIN}/cog-badjson"

  assert_failure
  assert_output ""
}

@test "plugin_probe gives up at the timeout rather than waiting out the plugin" {
  install_fixture slow "$PLUGIN_BIN"
  local started elapsed

  started="$SECONDS"
  run cog::fn::plugin_probe "${PLUGIN_BIN}/cog-slow"
  elapsed=$((SECONDS - started))

  assert_failure
  assert_output ""
  # The fixture sleeps 30s; the cap is 2s. A generous ceiling keeps this from
  # flaking on a loaded machine while still failing if the timeout is missing.
  ((elapsed < 15)) || fail "probe took ${elapsed}s; the timeout did not fire"
}

@test "plugin_probe fails when output exceeds the cap" {
  install_fixture loud "$PLUGIN_BIN"

  run cog::fn::plugin_probe "${PLUGIN_BIN}/cog-loud"

  assert_failure
  assert_output ""
}

# --- state ---------------------------------------------------------------------

@test "plugin_state reports shadowed-by-core for a name lib/commands owns" {
  install_fixture good "$PLUGIN_BIN" plan-gate

  run cog::fn::plugin_state plan-gate "${PLUGIN_BIN}/cog-plan-gate"

  assert_success
  assert_output "shadowed-by-core"
}

@test "plugin_state reports shadowed-by-path for a losing candidate" {
  install_fixture good "$PLUGIN_BIN"
  install_fixture good "$PLUGIN_ALT"

  run cog::fn::plugin_state good "${PLUGIN_ALT}/cog-good"
  assert_success
  assert_output "shadowed-by-path"

  run cog::fn::plugin_state good "${PLUGIN_BIN}/cog-good"
  assert_success
  assert_output "ok"
}

@test "plugin_state reports metadata-unavailable and protocol-newer" {
  install_fixture noprobe "$PLUGIN_BIN"
  install_fixture newer "$PLUGIN_BIN"

  run cog::fn::plugin_state noprobe "${PLUGIN_BIN}/cog-noprobe"
  assert_success
  assert_output "metadata-unavailable"

  run cog::fn::plugin_state newer "${PLUGIN_BIN}/cog-newer"
  assert_success
  assert_output "protocol-newer"
}

# --- checks --------------------------------------------------------------------

@test "plugin_check passes every check for a conformant plugin" {
  install_fixture good "$PLUGIN_BIN"

  run cog::fn::plugin_check "${PLUGIN_BIN}/cog-good"

  assert_success
  refute_output --partial " fail"
  refute_output --partial " skip"
}

@test "plugin_check skips the checks a failed probe makes unanswerable" {
  install_fixture noprobe "$PLUGIN_BIN"

  run cog::fn::plugin_check "${PLUGIN_BIN}/cog-noprobe"

  assert_success
  assert_line "metadata_exit fail"
  assert_line "metadata_json skip"
  assert_line "metadata_required_fields skip"
  assert_line "protocol_supported skip"
  assert_line "probe_within_timeout pass"
}

# --- regressions ---------------------------------------------------------------
#
# One test per defect the round-1 and round-2 reviews found. Each fixture is the
# input that produced the wrong answer, so a reintroduction fails here rather
# than in a third party's tree.

@test "a probe emitting two objects degrades instead of yielding two lines" {
  install_fixture twice "$PLUGIN_BIN"

  run cog::fn::plugin_probe "${PLUGIN_BIN}/cog-twice"
  assert_failure

  # The arithmetic context that a two-line protocol value used to reach.
  run cog::fn::plugin_state twice "${PLUGIN_BIN}/cog-twice"
  assert_success
  assert_output "metadata-unavailable"
}

@test "a non-integer protocol and a non-string requires_cog fail the field check" {
  install_fixture fractional "$PLUGIN_BIN"

  run cog::fn::plugin_check "${PLUGIN_BIN}/cog-fractional"
  assert_success
  assert_line "metadata_required_fields fail"

  run cog::fn::plugin_state fractional "${PLUGIN_BIN}/cog-fractional"
  assert_success
  assert_output "metadata-unavailable"
}

@test "a multi-line summary fails the field check" {
  install_fixture multiline "$PLUGIN_BIN"

  run cog::fn::plugin_check "${PLUGIN_BIN}/cog-multiline"
  assert_success
  assert_line "metadata_required_fields fail"
}

@test "a protocol beyond 64-bit arithmetic is protocol-newer, not ok" {
  install_fixture huge "$PLUGIN_BIN"

  run cog::fn::plugin_state huge "${PLUGIN_BIN}/cog-huge"
  assert_success
  assert_output "protocol-newer"

  run cog::fn::plugin_check "${PLUGIN_BIN}/cog-huge"
  assert_success
  assert_line "protocol_supported fail"
}

@test "metadata disagreeing with the filename is not state ok" {
  install_fixture misnamed "$PLUGIN_BIN"

  run cog::fn::plugin_state misnamed "${PLUGIN_BIN}/cog-misnamed"
  assert_success
  assert_output "metadata-unavailable"
}

@test "a file not named cog-<name> fails name_matches_filename" {
  install -m 0755 "${FIXTURES}/cog-good" "${PLUGIN_BIN}/good"

  run cog::fn::plugin_check "${PLUGIN_BIN}/good" good
  assert_success
  assert_line "name_matches_filename fail"
}

@test "a plugin exiting 124 quickly is an exit failure, not a timeout" {
  install_fixture exit124 "$PLUGIN_BIN"

  run cog::fn::plugin_check "${PLUGIN_BIN}/cog-exit124"
  assert_success
  assert_line "probe_within_timeout pass"
  assert_line "metadata_exit fail"
}

@test "a probe that really does hang still fails probe_within_timeout" {
  install_fixture slow "$PLUGIN_BIN"

  run cog::fn::plugin_check "${PLUGIN_BIN}/cog-slow"
  assert_success
  assert_line "probe_within_timeout fail"
}

@test "plugin_winner names the winning candidate, not the target it resolves to" {
  install_fixture good "${BATS_TEST_TMPDIR}" impl
  ln -s "${BATS_TEST_TMPDIR}/cog-impl" "${PLUGIN_BIN}/cog-good"
  ln -s "${BATS_TEST_TMPDIR}/cog-impl" "${PLUGIN_ALT}/cog-good"

  run cog::fn::plugin_winner good
  assert_success
  assert_output "${PLUGIN_BIN}/cog-good"

  # plugin_resolve answers the other question, and must keep answering it.
  run cog::fn::plugin_resolve good
  assert_success
  assert_output "${BATS_TEST_TMPDIR}/cog-impl"
}

@test "two links to one target are a winner and a shadowed loser" {
  install_fixture good "${BATS_TEST_TMPDIR}" impl
  ln -s "${BATS_TEST_TMPDIR}/cog-impl" "${PLUGIN_BIN}/cog-good"
  ln -s "${BATS_TEST_TMPDIR}/cog-impl" "${PLUGIN_ALT}/cog-good"

  run cog::fn::plugin_state good "${PLUGIN_BIN}/cog-good"
  assert_success
  assert_output "ok"

  run cog::fn::plugin_state good "${PLUGIN_ALT}/cog-good"
  assert_success
  assert_output "shadowed-by-path"
}

@test "an empty PATH component is not searched as the current directory" {
  install_fixture good "$PLUGIN_DIR"
  cd "$PLUGIN_DIR" || return 1
  local clean_path
  clean_path="$(path_without_plugins "$PATH")"
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting here is intentional.
  export PATH=":${clean_path}"

  run cog::fn::plugin_resolve good
  assert_failure
}

@test "a plugin exiting 124 after a delay is still an exit failure" {
  install_fixture slow124 "$PLUGIN_BIN"

  # Sub-second precision matters: a one-second-granularity clock reports 2 for
  # this 1.2-second run whenever it straddles an integer boundary.
  run cog::fn::plugin_check "${PLUGIN_BIN}/cog-slow124"
  assert_success
  assert_line "probe_within_timeout pass"
  assert_line "metadata_exit fail"
}

@test "a directory whose path contains a newline is not searched" {
  local nldir="${BATS_TEST_TMPDIR}/a"$'\n'"b"
  mkdir -p "$nldir"
  install -m 0755 "${FIXTURES}/cog-good" "${nldir}/cog-good"
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting here is intentional.
  export COG_PLUGIN_DIR="$nldir"

  run cog::fn::plugin_candidates good
  assert_success
  assert_output ""

  run cog::fn::plugin_discover
  assert_success
  assert_output ""
}

@test "plugin_env_json carries every value intact and names exactly four keys" {
  run --separate-stderr cog::fn::plugin_env_json demo
  assert_success
  assert_equal "$(jq -r 'keys | length' <<<"$output")" "4"
  assert_equal "$(jq -r '.COG_PLUGIN_NAME' <<<"$output")" "demo"
  assert_equal "$(jq -r '.COG_PLUGIN_PROTOCOL' <<<"$output")" "1"
  # Built by value, so it cannot lose a key the NAME=VALUE listing would split.
  assert_equal "$(jq -r 'keys_unsorted | sort | join(",")' <<<"$output")" \
    "$(cog::fn::plugin_env_names | LC_ALL=C sort | paste -sd,)"
}

@test "plugin_env_json reports no path under lib/" {
  run cog::fn::plugin_env_json demo
  assert_success
  refute_output --partial "/lib/functions"
  refute_output --partial "/lib/commands"
}

@test "a PATH component containing a newline is not searched" {
  # The COG_PLUGIN_DIR half of this rule was covered; the $PATH half was not,
  # and $PATH is where the rule actually bites. The component below is ONE
  # directory that does not exist, whose name happens to contain a newline and a
  # second absolute path. Splitting $PATH by translating ':' to newline turned it
  # into two ordinary directories, the second of which does exist and does carry
  # a plugin — so cog resolved a plugin from a directory $PATH never named, and
  # the newline rejection could never fire because the newline was already gone.
  local realdir="${BATS_TEST_TMPDIR}/planted"
  mkdir -p "$realdir"
  install -m 0755 "${FIXTURES}/cog-good" "${realdir}/cog-good"
  local nldir="${BATS_TEST_TMPDIR}/absent"$'\n'"${realdir}"
  local clean_path
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting here is intentional.
  clean_path="$(path_without_plugins "$PATH")"
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting here is intentional.
  export PATH="${nldir}:${clean_path}"
  unset COG_PLUGIN_DIR

  run cog::fn::plugin_candidates good
  assert_success
  assert_output ""

  run cog::fn::plugin_resolve good
  assert_failure

  run cog::fn::plugin_discover
  assert_success
  assert_output ""
}

@test "a probe that ignores TERM is still bounded, by the kill that follows it" {
  install_fixture termproof "$PLUGIN_DIR"

  # The bound is the assertion. `timeout` alone sends TERM and then waits, so a
  # plugin ignoring TERM held the probe open forever; the outer bound here fails
  # the test rather than hanging the suite if that regresses.
  # shellcheck disable=SC2016 # The body is expanded by the inner bash, not here.
  run timeout 20 bash -c '
    source "$1/lib/functions/fn_plugin.sh"
    cog::fn::plugin_check "$2" termproof
  ' -- "$REPO_ROOT" "${PLUGIN_DIR}/cog-termproof"
  assert_success
  assert_line "probe_within_timeout fail"
}

@test "plugin_inspect probes once and reports state and metadata from that run" {
  install_fixture flaky "$PLUGIN_DIR"
  export COG_FLAKY_COUNTER="${BATS_TEST_TMPDIR}/probes"

  run cog::fn::plugin_inspect flaky "${PLUGIN_DIR}/cog-flaky"
  assert_success
  assert_line --index 0 "ok"
  # The metadata must come from the probe that decided the state. A second probe
  # would return malformed output, leaving `ok` beside a null version.
  assert_equal "$(jq -r '.version' <<<"${lines[1]}")" "1.0.0"
  assert_equal "$(<"$COG_FLAKY_COUNTER")" "1"
}
