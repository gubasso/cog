# shellcheck shell=bash

cog::loader::dispatch() {
  local sub="${1:-}"
  shift || true

  [[ -n $sub ]] || cog::helpers::die "$EX_USAGE" "MissingCommand" \
    "no command given" "" "" "run 'cog <command>'"

  # Reject unsafe slugs before building a path.
  [[ $sub =~ ^[a-z][a-z0-9_-]*$ ]] || cog::helpers::die "$EX_USAGE" "BadCommandName" \
    "invalid command name" "command: ${sub}" "command names must match [a-z][a-z0-9_-]*" ""

  # Derive module/function slug: print-config -> print_config.
  local derived="${sub//-/_}"
  local path="${LIB_DIR}/commands/cmd_${derived}.sh"
  # A first-party module always wins: resolution is attempted only once the
  # module check has failed, so a plugin can never replace, wrap, or hide a
  # built-in command, and normal dispatch pays nothing for the seam.
  if [[ ! -r $path ]]; then
    local plugin_path=""
    if plugin_path="$(cog::fn::plugin_resolve "$sub")"; then
      # Execs; does not return. argv passes verbatim and the plugin's exit
      # status becomes cog's, unmodified.
      cog::fn::plugin_exec "$sub" "$plugin_path" "$@"
    fi

    # A cog-<name> that exists but is not a regular executable file is a
    # forgotten chmod far more often than a typo, so it gets its own error
    # rather than being folded into "unknown command".
    if [[ -n "$(cog::fn::plugin_candidates "$sub" 2>/dev/null || true)" ]]; then
      cog::helpers::die "$EX_UNAVAILABLE" "PluginNotExecutable" \
        "plugin is not executable" "command: ${sub}" \
        "cog-${sub} was found but is not a regular file executable by the current user" \
        "run 'cog plugin list' to see why, then make it executable"
    fi

    cog::helpers::die "$EX_USAGE" "UnknownCommand" \
      "unknown command" "command: ${sub}" \
      "no readable command module and no executable cog-${sub} on \$COG_PLUGIN_DIR or \$PATH" \
      "check the command name, or install the plugin that provides it"
  fi

  # Derive function name: cmd_<derived>.sh -> cog::cmd::<derived>
  local fn="cog::cmd::${derived}"

  # shellcheck source=/dev/null
  source "$path"

  if ! declare -F "$fn" >/dev/null; then
    cog::helpers::die "$EX_SOFTWARE" "CommandHandlerMissing" \
      "command module did not define its handler" \
      "expected function: ${fn}" "module ${path} was sourced but ${fn} is undefined" ""
  fi

  "$fn" "$@"
}
