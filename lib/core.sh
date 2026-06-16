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

  if [[ ${ctx[version]} == true ]]; then
    printf '%s\n' "$(<"$version_file")"
    return 0
  fi

  if [[ ${ctx[help]} == true && -z ${ctx[subcommand]} ]]; then
    cog::fn::help_generate root
    return 0
  fi

  if [[ ${ctx[print_config]} == true ]]; then
    for key in dry_run json log_level; do
      printf '%s=%s source=%s\n' "$key" "${config[$key]}" "${config_source[$key]}"
    done
    return 0
  fi

  [[ -n ${ctx[subcommand]} ]] || cog::helpers::die "$EX_USAGE" "MissingCommand" \
    "no command given" "" "" "run 'cog --help' or 'cog <command>'"

  if [[ ${ctx[help]} == true || ${cmd_argv[0]:-} == "--help" || ${cmd_argv[0]:-} == "-h" ]]; then
    cog::fn::help_generate command "${ctx[subcommand]}"
    return 0
  fi

  cog::loader::dispatch "${ctx[subcommand]}" "${cmd_argv[@]}"
}
