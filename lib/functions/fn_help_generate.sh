# shellcheck shell=bash

__cog_help_command_path() {
  local sub="$1"
  local derived="${sub//-/_}"
  printf '%s/commands/cmd_%s.sh\n' "$LIB_DIR" "$derived"
}

__cog_help_desc_for() {
  local path="$1"
  local line

  line="$(sed -n '2p' "$path")"
  if [[ $line =~ ^:\ \'desc:\ (.*)\'$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  cog::helpers::die "$EX_SOFTWARE" "CommandDescriptionMissing" \
    "command module has no desc sentinel" "path: ${path}" \
    "line 2 must be \": 'desc: ...'\"" ""
}

__cog_help_global_flags() {
  printf '%s\n' "Global flags:"
  printf '%s\n' "  -h, --help          Show help"
  printf '%s\n' "  -V, --version       Show version"
  printf '%s\n' "      --json          Request machine-readable output"
  printf '%s\n' "      --dry-run       Show what would happen without changing state"
  printf '%s\n' "      --print-config  Print resolved configuration and sources"
  printf '%s\n' "  -v, -vv, -vvv       Increase verbosity"
}

__cog_help_list_commands() {
  local path base slug display desc
  local -a paths=()

  while IFS= read -r path; do
    paths+=("$path")
  done < <(find "${LIB_DIR}/commands" -maxdepth 1 -type f -name 'cmd_*.sh' | sort)

  for path in "${paths[@]}"; do
    base="${path##*/}"
    slug="${base#cmd_}"
    slug="${slug%.sh}"
    display="${slug//_/-}"
    desc="$(__cog_help_desc_for "$path")" || return $?
    printf '  %-14s %s\n' "$display" "$desc"
  done
}

cog::fn::help_generate() {
  local mode="${1:-}"
  local sub="${2:-}"
  local path desc

  case "$mode" in
    root)
      printf '%s\n' "Usage: cog [global-flags] <command> [args]"
      printf '\n'
      __cog_help_global_flags
      printf '\n'
      printf '%s\n' "Commands:"
      __cog_help_list_commands
      ;;
    command)
      [[ -n $sub ]] || cog::helpers::die "$EX_USAGE" "MissingCommand" \
        "no command given" "" "" "run 'cog --help'"
      [[ $sub =~ ^[a-z][a-z0-9_-]*$ ]] || cog::helpers::die "$EX_USAGE" "BadCommandName" \
        "invalid command name" "command: ${sub}" "command names must match [a-z][a-z0-9_-]*" ""

      path="$(__cog_help_command_path "$sub")"
      if [[ ! -r $path ]]; then
        cog::helpers::die "$EX_USAGE" "UnknownCommand" \
          "unknown command" "command: ${sub}" "" "run 'cog --help'"
      fi

      desc="$(__cog_help_desc_for "$path")" || return $?
      printf 'Usage: cog %s [args]\n' "$sub"
      printf '\n'
      printf '%s\n' "$desc"
      printf '\n'
      __cog_help_global_flags
      ;;
    *)
      cog::helpers::die "$EX_SOFTWARE" "BadCall" \
        "invalid help generation mode" "mode: ${mode}" "" \
        "call cog::fn::help_generate root or command"
      ;;
  esac
}
