#!/usr/bin/env bats
#
# `cog plugin` and its four verbs.
#
# Every test builds its own PATH under BATS_TEST_TMPDIR, after _common_setup has
# prepended the repo's bin/. A cog-* executable the developer happens to have
# installed must not be able to change a result.

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  FIXTURES="${REPO_ROOT}/test/fixtures/plugins"

  PLUGIN_BIN="${BATS_TEST_TMPDIR}/bin"
  PLUGIN_ALT="${BATS_TEST_TMPDIR}/alt"
  mkdir -p "$PLUGIN_BIN" "$PLUGIN_ALT"
  local clean_path
  clean_path="$(path_without_plugins "$PATH")"
  export PATH="${PLUGIN_BIN}:${PLUGIN_ALT}:${clean_path}"
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
  local fixture="$1" dir="$2" name="${3:-}"
  [[ -n $name ]] || name="$fixture"
  cp "${FIXTURES}/cog-${fixture}" "${dir}/cog-${name}"
  chmod 0755 "${dir}/cog-${name}"
}

state_of() {
  jq -r --arg name "$1" '.plugins[] | select(.name == $name) | .state' <<<"$2"
}

# --- list ----------------------------------------------------------------------

@test "list exits 0 with an empty array when nothing is installed" {
  run cog plugin list --json

  assert_success
  assert_equal "$(jq -r '.schema' <<<"$output")" "cog.plugin.list.v1"
  assert_equal "$(jq -r '.plugins | length' <<<"$output")" "0"
}

@test "list reports a conformant plugin as ok with its version and summary" {
  install_fixture good "$PLUGIN_BIN"

  run cog plugin list --json

  assert_success
  assert_equal "$(state_of good "$output")" "ok"
  assert_equal "$(jq -r '.plugins[0].version' <<<"$output")" "1.0.0"
  assert_equal "$(jq -r '.plugins[0].protocol' <<<"$output")" "1"
  assert_equal "$(jq -r '.plugins[0].summary' <<<"$output")" "A conformant fixture plugin"
  assert_equal "$(jq -r '.plugins[0].path' <<<"$output")" "${PLUGIN_BIN}/cog-good"
}

@test "list reports a duplicate as shadowed-by-path and names the winner" {
  install_fixture good "$PLUGIN_ALT"
  install_fixture good "$PLUGIN_BIN"

  run cog plugin list --json

  assert_success
  # One row per candidate, so the loser is visible rather than silently dropped.
  assert_equal "$(jq -r '.plugins | length' <<<"$output")" "2"
  assert_equal "$(jq -r '.plugins[0].state' <<<"$output")" "ok"
  assert_equal "$(jq -r '.plugins[0].path' <<<"$output")" "${PLUGIN_BIN}/cog-good"
  assert_equal "$(jq -r '.plugins[1].state' <<<"$output")" "shadowed-by-path"
  assert_equal "$(jq -r '.plugins[1].shadowed_by' <<<"$output")" "${PLUGIN_BIN}/cog-good"

  run cog plugin info good --json
  assert_success
  assert_equal "$(jq -r '.candidates | length' <<<"$output")" "2"
  assert_equal "$(jq -r '.candidates[0]' <<<"$output")" "${PLUGIN_BIN}/cog-good"
}

@test "list reports a first-party collision as shadowed-by-core" {
  install_fixture good "$PLUGIN_BIN" plan-gate

  run cog plugin list --json

  assert_success
  assert_equal "$(state_of plan-gate "$output")" "shadowed-by-core"
  assert_equal "$(jq -r '.plugins[] | select(.name == "plan-gate") | .shadowed_by' <<<"$output")" \
    "lib/commands/cmd_plan_gate.sh"
}

@test "list reports a 0644 candidate as not-executable" {
  cp "${FIXTURES}/cog-good" "${PLUGIN_BIN}/cog-notexec"
  chmod 0644 "${PLUGIN_BIN}/cog-notexec"

  run cog plugin list --json

  assert_success
  assert_equal "$(state_of notexec "$output")" "not-executable"
}

@test "list reports a broken probe as metadata-unavailable and a high protocol as protocol-newer" {
  install_fixture noprobe "$PLUGIN_BIN"
  install_fixture newer "$PLUGIN_BIN"

  run cog plugin list --json

  assert_success
  assert_equal "$(state_of noprobe "$output")" "metadata-unavailable"
  assert_equal "$(state_of newer "$output")" "protocol-newer"
}

@test "list --names prints bare names, one per line, and nothing else" {
  install_fixture good "$PLUGIN_BIN"
  install_fixture noprobe "$PLUGIN_BIN"

  run cog plugin list --names

  assert_success
  assert_output "good
noprobe"
}

# --- info ----------------------------------------------------------------------

@test "info reports the environment block with exactly four keys" {
  install_fixture good "$PLUGIN_BIN"

  run cog plugin info good --json

  assert_success
  assert_equal "$(jq -r '.schema' <<<"$output")" "cog.plugin.info.v1"
  assert_equal "$(jq -r '.environment | keys | length' <<<"$output")" "4"
  assert_equal "$(jq -r '.environment.COG_PLUGIN_PROTOCOL' <<<"$output")" "1"
  assert_equal "$(jq -r '.environment.COG_PLUGIN_NAME' <<<"$output")" "good"
  assert_equal "$(jq -r '.environment.COG_HOST_VERSION' <<<"$output")" "$(<"${REPO_ROOT}/VERSION")"
  assert_equal "$(jq -r '.requires_cog_satisfied' <<<"$output")" "true"
}

@test "info reports no path into cog's own sources" {
  install_fixture good "$PLUGIN_BIN"

  run cog plugin info good --json

  assert_success
  refute_output --partial "/lib/functions"
  refute_output --partial "/lib/commands"
}

@test "info on an unknown name exits non-zero with a cog-prefixed error" {
  run cog plugin info nosuchplugin --json

  assert_failure
  assert_output --partial "cog:"
  assert_output --partial "UnknownPlugin"
}

# --- validate ------------------------------------------------------------------

@test "validate on a conformant plugin exits 0 with every check passing" {
  install_fixture good "$PLUGIN_BIN"

  run cog plugin validate good --json

  assert_success
  assert_equal "$(jq -r '.schema' <<<"$output")" "cog.plugin.validate.v1"
  assert_equal "$(jq -r '.ok' <<<"$output")" "true"
  assert_equal "$(jq -r '.failures | length' <<<"$output")" "0"
  assert_equal "$(jq -r '[.checks[] | select(. != "pass")] | length' <<<"$output")" "0"
}

@test "validate accepts a path as well as a resolved name" {
  run cog plugin validate "${FIXTURES}/cog-good" --json

  assert_success
  assert_equal "$(jq -r '.name' <<<"$output")" "good"
}

@test "validate fails exactly metadata_json for a probe that emits non-JSON" {
  install_fixture badjson "$PLUGIN_BIN"

  run cog plugin validate badjson --json

  assert_failure
  assert_equal "$(jq -r '.ok' <<<"$output")" "false"
  assert_equal "$(jq -c '.failures' <<<"$output")" '["metadata_json"]'
}

@test "validate fails exactly metadata_exit for a probe that exits non-zero" {
  install_fixture noprobe "$PLUGIN_BIN"

  run cog plugin validate noprobe --json

  assert_failure
  assert_equal "$(jq -c '.failures' <<<"$output")" '["metadata_exit"]'
}

@test "validate fails exactly probe_side_effect_free for a probe that writes" {
  install_fixture dirty "$PLUGIN_BIN"

  run cog plugin validate dirty --json

  assert_failure
  assert_equal "$(jq -c '.failures' <<<"$output")" '["probe_side_effect_free"]'
}

@test "validate fails protocol_supported for a plugin declaring a newer protocol" {
  install_fixture newer "$PLUGIN_BIN"

  run cog plugin validate newer --json

  assert_failure
  assert_equal "$(jq -c '.failures' <<<"$output")" '["protocol_supported"]'
}

@test "validate fails name_matches_filename when metadata disagrees with the filename" {
  install_fixture misnamed "$PLUGIN_BIN"

  run cog plugin validate misnamed --json

  assert_failure
  assert_equal "$(jq -c '.failures' <<<"$output")" '["name_matches_filename"]'
}

@test "validate fails probe_within_timeout for a probe that hangs" {
  install_fixture slow "$PLUGIN_BIN"

  run cog plugin validate slow --json

  assert_failure
  assert_equal "$(jq -c '.failures' <<<"$output")" '["probe_within_timeout"]'
}

@test "validate fails no_firstparty_collision for a name lib/commands owns" {
  install_fixture good "$PLUGIN_BIN" plan-gate

  run cog plugin validate plan-gate --json

  assert_failure
  assert_output --partial "no_firstparty_collision"
}

# --- host-info -----------------------------------------------------------------

@test "host-info reports protocol 1 and the four variable names" {
  run cog plugin host-info --json

  assert_success
  assert_equal "$(jq -r '.schema' <<<"$output")" "cog.plugin.host-info.v1"
  assert_equal "$(jq -r '.protocol' <<<"$output")" "1"
  assert_equal "$(jq -r '.host_version' <<<"$output")" "$(<"${REPO_ROOT}/VERSION")"
  assert_equal "$(jq -c '.exported_environment' <<<"$output")" \
    '["COG_PLUGIN_PROTOCOL","COG_HOST_VERSION","COG_PLUGIN_NAME","COG_EXECUTABLE"]'
  # shellcheck disable=SC2016 # The literal variable names are the asserted value.
  assert_equal "$(jq -c '.resolution_order' <<<"$output")" '["$COG_PLUGIN_DIR","$PATH"]'
  assert_equal "$(jq -r '.reserved_subcommand' <<<"$output")" "cog-plugin-metadata"
}

@test "host-info agrees with the published data table" {
  local table="${REPO_ROOT}/data/plugin-protocol/protocol.yaml"

  run cog plugin host-info --json

  assert_success
  assert_equal "$(jq -r '.protocol' <<<"$output")" "$(yq e '.plugin-protocol.version' "$table")"
  assert_equal "$(jq -r '.probe_timeout_seconds' <<<"$output")" "$(yq e '.plugin-protocol.probe_timeout_seconds' "$table")"
  assert_equal "$(jq -r '.probe_output_cap_bytes' <<<"$output")" "$(yq e '.plugin-protocol.probe_output_cap_bytes' "$table")"
}

# --- the ok field and the exit code agree ---------------------------------------

@test "every --json verb's ok field agrees with its exit code" {
  install_fixture good "$PLUGIN_BIN"
  install_fixture badjson "$PLUGIN_BIN"
  local verb

  for verb in "list" "host-info" "info good" "validate good"; do
    # shellcheck disable=SC2086 # Deliberate word splitting: verb carries args.
    run cog plugin $verb --json
    assert_success
    assert_equal "$(jq -r '.ok' <<<"$output")" "true"
  done

  run cog plugin validate badjson --json
  assert_failure
  assert_equal "$(jq -r '.ok' <<<"$output")" "false"
}

@test "an unknown verb is a usage error" {
  run cog plugin install something

  assert_failure
  assert_output --partial "unknown plugin verb"
}

# --- regressions ---------------------------------------------------------------
#
# Command-level counterparts to test/unit/fn_plugin.bats' regression block: the
# defects that were only visible through a verb's own output.

@test "list, info, and validate agree about a symlinked plugin" {
  install_fixture good "$BATS_TEST_TMPDIR" impl
  ln -s "${BATS_TEST_TMPDIR}/cog-impl" "${PLUGIN_BIN}/cog-good"

  run cog plugin list --json
  assert_success
  assert_equal "$(state_of good "$output")" "ok"

  # info and validate resolve by name, and must reach the same verdict as list
  # rather than inspecting the target the symlink points at.
  run cog plugin info good --json
  assert_success
  assert_equal "$(jq -r '.state' <<<"$output")" "ok"
  assert_equal "$(jq -r '.path' <<<"$output")" "${PLUGIN_BIN}/cog-good"

  run cog plugin validate good --json
  assert_success
  assert_equal "$(jq -r '.failures | length' <<<"$output")" "0"
}

@test "list names the winning candidate when both candidates link to one target" {
  install_fixture good "$BATS_TEST_TMPDIR" impl
  ln -s "${BATS_TEST_TMPDIR}/cog-impl" "${PLUGIN_BIN}/cog-good"
  ln -s "${BATS_TEST_TMPDIR}/cog-impl" "${PLUGIN_ALT}/cog-good"

  run cog plugin list --json
  assert_success
  assert_equal "$(jq -r '.plugins | length' <<<"$output")" "2"
  assert_equal "$(jq -r '.plugins[0].state' <<<"$output")" "ok"
  assert_equal "$(jq -r '.plugins[1].state' <<<"$output")" "shadowed-by-path"
  # The winning candidate, not the target both candidates share.
  assert_equal "$(jq -r '.plugins[1].shadowed_by' <<<"$output")" "${PLUGIN_BIN}/cog-good"
}

@test "a probe emitting two objects is reported, not a jq crash" {
  install_fixture twice "$PLUGIN_BIN"

  run cog plugin list --json
  assert_success
  assert_equal "$(state_of twice "$output")" "metadata-unavailable"
  refute_output --partial "invalid JSON text"

  run cog plugin validate twice --json
  assert_failure
  assert_equal "$(jq -r '.checks.metadata_json' <<<"$output")" "fail"
}

@test "validate rejects a non-integer protocol and a non-string requires_cog" {
  install_fixture fractional "$PLUGIN_BIN"

  run cog plugin validate fractional --json
  assert_failure
  assert_equal "$(jq -r '.checks.metadata_required_fields' <<<"$output")" "fail"
}

@test "validate rejects a protocol beyond 64-bit arithmetic as unsupported" {
  install_fixture huge "$PLUGIN_BIN"

  run cog plugin validate huge --json
  assert_failure
  assert_equal "$(jq -r '.checks.protocol_supported' <<<"$output")" "fail"

  run cog plugin list --json
  assert_success
  assert_equal "$(state_of huge "$output")" "protocol-newer"
}

@test "validate rejects an executable that is not named cog-<name>" {
  cp "${FIXTURES}/cog-good" "${BATS_TEST_TMPDIR}/good"
  chmod 0755 "${BATS_TEST_TMPDIR}/good"

  run cog plugin validate "${BATS_TEST_TMPDIR}/good" --json
  assert_failure
  assert_equal "$(jq -r '.checks.name_matches_filename' <<<"$output")" "fail"
}

@test "validate reports a plugin exiting 124 as an exit failure, not a timeout" {
  install_fixture exit124 "$PLUGIN_BIN"

  run cog plugin validate exit124 --json
  assert_failure
  assert_equal "$(jq -r '.checks.probe_within_timeout' <<<"$output")" "pass"
  assert_equal "$(jq -r '.checks.metadata_exit' <<<"$output")" "fail"
}

@test "validate never reports ok while a check is still skipped" {
  install_fixture good "$PLUGIN_BIN"

  # An unusable TMPDIR fails the probe setup, leaving every probe check `skip`.
  # `ok` must follow every check passing, not merely nothing failing.
  TMPDIR="${BATS_TEST_TMPDIR}/nonexistent" run cog plugin validate good --json
  assert_failure
  assert_equal "$(jq -r '.ok' <<<"$output")" "false"
  assert_equal "$(jq -r '[.checks[] | select(. == "skip")] | length > 0' <<<"$output")" "true"
}

@test "list does not report a plugin found only through an empty PATH component" {
  install_fixture good "$BATS_TEST_TMPDIR"
  cd "$BATS_TEST_TMPDIR" || return 1
  local clean_path
  clean_path="$(path_without_plugins "$PATH")"
  export PATH=":${clean_path}"

  run cog plugin list --json
  assert_success
  assert_equal "$(jq -r '.plugins | length' <<<"$output")" "0"
}

@test "info reports inspection success, not plugin health, and agrees with its exit code" {
  # `ok` used to mean "this plugin is healthy" while the command still exited 0,
  # so `info noprobe --json` handed automation ok:false and status 0 — two
  # opposite answers to one question. Health is `state`, which can also say how
  # the plugin is unhealthy; a broken probe never stops it from dispatching.
  install_fixture noprobe "$PLUGIN_BIN"

  run cog plugin info noprobe --json
  assert_success
  assert_equal "$(jq -r '.ok' <<<"$output")" "true"
  assert_equal "$(jq -r '.state' <<<"$output")" "metadata-unavailable"
}

@test "info probes once, so its state and metadata come from one run" {
  install_fixture flaky "$PLUGIN_BIN"
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting here is intentional.
  export COG_FLAKY_COUNTER="${BATS_TEST_TMPDIR}/probes"

  run cog plugin info flaky --json
  assert_success
  assert_equal "$(jq -r '.state' <<<"$output")" "ok"
  assert_equal "$(jq -r '.metadata.version' <<<"$output")" "1.0.0"
  assert_equal "$(<"$COG_FLAKY_COUNTER")" "1"
}

@test "list probes once per inspected candidate" {
  install_fixture flaky "$PLUGIN_BIN"
  # shellcheck disable=SC2030,SC2031 # Each bats @test runs in its own subshell; exporting here is intentional.
  export COG_FLAKY_COUNTER="${BATS_TEST_TMPDIR}/probes"

  run cog plugin list --json
  assert_success
  assert_equal "$(state_of flaky "$output")" "ok"
  assert_equal "$(jq -r '.plugins[] | select(.name == "flaky") | .version' <<<"$output")" "1.0.0"
  assert_equal "$(<"$COG_FLAKY_COUNTER")" "1"
}

@test "validate reports requires_cog and keeps it advisory" {
  # The reference promises validate *reports* a mismatch and equally that cog
  # does not block on one, so an unsatisfiable constraint must be visible in the
  # document while every check still passes.
  install_fixture future "$PLUGIN_BIN"

  run cog plugin validate future --json
  assert_success
  assert_equal "$(jq -r '.ok' <<<"$output")" "true"
  assert_equal "$(jq -r '.requires_cog' <<<"$output")" ">=999.0.0"
  assert_equal "$(jq -r '.requires_cog_satisfied' <<<"$output")" "false"
  assert_equal "$(jq -r '.failures | length' <<<"$output")" "0"
}

@test "validate reports a satisfied requires_cog, and null when there is none" {
  install_fixture good "$PLUGIN_BIN"
  install_fixture probemarker "$PLUGIN_BIN"

  run cog plugin validate good --json
  assert_success
  assert_equal "$(jq -r '.requires_cog' <<<"$output")" ">=0.1.0"
  assert_equal "$(jq -r '.requires_cog_satisfied' <<<"$output")" "true"

  # A plugin declaring no constraint is not a mismatch and not a failure.
  # The marker goes outside the probe's working directory, which is the one
  # thing probe_side_effect_free audits.
  export COG_PROBE_MARKER="${BATS_TEST_TMPDIR}/marker"
  run cog plugin validate probemarker --json
  assert_success
  assert_equal "$(jq -r '.requires_cog' <<<"$output")" "null"
  assert_equal "$(jq -r '.requires_cog_satisfied' <<<"$output")" "null"
}

@test "a plugin that ignores TERM does not hang an inspecting verb" {
  install_fixture termproof "$PLUGIN_BIN"

  run timeout 30 cog plugin validate termproof --json
  assert_failure
  assert_equal "$(jq -r '.checks.probe_within_timeout' <<<"$output")" "fail"
}
