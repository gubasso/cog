# shellcheck shell=bash

cog::main() {
  local version_file="${LIB_DIR}/../VERSION"

  [[ -r $version_file ]] || cog::helpers::die "$EX_SOFTWARE" "VersionUnavailable" \
    "VERSION file is missing or unreadable" "path: ${version_file}" "" ""

  local -A ctx config config_source
  # shellcheck disable=SC2034 # Filled by config loader for per-key file provenance.
  local -A config_line
  local -a cmd_argv=()
  local key

  cog::fn::parse_globals ctx cmd_argv "$@"
  cog::fn::config_load ctx config config_source config_line
  cog::fn::ui_init ctx config
  cog::fn::log_init ctx config

  if [[ ${ctx[version]} == true ]]; then
    cog::fn::ui_data "$(<"$version_file")"
    return 0
  fi

  if [[ ${ctx[help]} == true && -z ${ctx[subcommand]} ]]; then
    cog::fn::help_generate root
    return 0
  fi

  if [[ ${ctx[print_config]} == true ]]; then
    for key in dry_run json log_level; do
      cog::fn::ui_dataf '%s=%s source=%s\n' "$key" "${config[$key]}" "${config_source[$key]}"
    done
    return 0
  fi

  [[ -n ${ctx[subcommand]} ]] || cog::helpers::die "$EX_USAGE" "MissingCommand" \
    "no command given" "" "" "run 'cog --help' or 'cog <command>'"

  # A global --help came *before* the command name, so it is cog's to answer for
  # any command, plugin included. `cog help <plugin>` reaches the same place
  # through cmd_help.sh.
  if [[ ${ctx[help]} == true ]]; then
    cog::fn::help_generate command "${ctx[subcommand]}"
    return 0
  fi

  # `-h`/`--help` *after* the command name belongs to the command. Cog answers
  # it for a first-party command, but for a plugin it is argv, and the published
  # contract is that cog interprets nothing after a plugin name. Answering it
  # here rewrote `cog demo -h extra` into `cog-demo --help`, changing one
  # argument and dropping another. Falling through to dispatch passes it
  # verbatim; the plugin decides what its own help flag means.
  if [[ ${cmd_argv[0]:-} == "--help" || ${cmd_argv[0]:-} == "-h" ]]; then
    if [[ -r "${LIB_DIR}/commands/cmd_${ctx[subcommand]//-/_}.sh" ]]; then
      cog::fn::help_generate command "${ctx[subcommand]}"
      return 0
    fi
  fi

  cog::loader::dispatch "${ctx[subcommand]}" "${cmd_argv[@]}"
}
