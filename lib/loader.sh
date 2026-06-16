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
  if [[ ! -r $path ]]; then
    cog::helpers::die "$EX_USAGE" "UnknownCommand" \
      "unknown command" "command: ${sub}" \
      "no readable command module was found" "check the command name and retry"
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
