# shellcheck shell=bash

__cog_help_command_path() {
  local sub="$1"
  local derived="${sub//-/_}"
  cog::fn::ui_dataf '%s/commands/cmd_%s.sh\n' "$LIB_DIR" "$derived"
}

__cog_help_desc_for() {
  local path="$1"
  local line

  line="$(sed -n '2p' "$path")"
  if [[ $line =~ ^:\ \'desc:\ (.*)\'$ ]]; then
    cog::fn::ui_data "${BASH_REMATCH[1]}"
    return 0
  fi

  cog::helpers::die "$EX_SOFTWARE" "CommandDescriptionMissing" \
    "command module has no desc sentinel" "path: ${path}" \
    "line 2 must be \": 'desc: ...'\"" ""
}

__cog_help_usage_for() {
  local sub="$1" path="$2"
  local derived="${sub//-/_}"
  local fn="__cog_${derived}_usage"

  # Surface the command's own usage/synopsis when it defines one. Source the
  # module in a subshell so its function definitions never leak into the help
  # process, and fall back to the generic synopsis when no usage function exists.
  if (
    # shellcheck source=/dev/null
    source "$path" >/dev/null 2>&1 || exit 1
    declare -F "$fn" >/dev/null 2>&1 || exit 1
    "$fn"
  ); then
    return 0
  fi

  cog::fn::ui_dataf 'Usage: cog %s [args]\n' "$sub"
}

__cog_help_global_flags() {
  cog::fn::ui_data "Global flags:"
  cog::fn::ui_data "  -h, --help          Show help"
  cog::fn::ui_data "  -V, --version       Show version"
  cog::fn::ui_data "      --json          Request machine-readable output"
  cog::fn::ui_data "      --dry-run       Show what would happen without changing state"
  cog::fn::ui_data "      --print-config  Print resolved configuration and sources"
  cog::fn::ui_data "  -v, -vv, -vvv       Increase verbosity"
}

__cog_help_list_commands() {
  local path base slug display desc
  local -a paths=()

  # LC_ALL=C pins byte order, so the command list is identical under every
  # locale. A UTF-8 collation ignores the hyphen at the first level and orders
  # `claudemd-audit` before `claude-runner`, which drifts the help output away
  # from the tracked inventories that were generated with byte order.
  while IFS= read -r path; do
    paths+=("$path")
  done < <(find "${LIB_DIR}/commands" -maxdepth 1 -type f -name 'cmd_*.sh' | LC_ALL=C sort)

  for path in "${paths[@]}"; do
    base="${path##*/}"
    slug="${base#cmd_}"
    slug="${slug%.sh}"
    display="${slug//_/-}"
    desc="$(__cog_help_desc_for "$path")" || return $?
    cog::fn::ui_dataf '  %-14s %s\n' "$display" "$desc"
  done
}

cog::fn::help_generate() {
  local mode="${1:-}"
  local sub="${2:-}"
  local path desc

  case "$mode" in
    root)
      cog::fn::ui_data "Usage: cog [global-flags] <command> [args]"
      cog::fn::ui_data ""
      __cog_help_global_flags
      cog::fn::ui_data ""
      cog::fn::ui_data "Commands:"
      __cog_help_list_commands
      ;;
    command)
      [[ -n $sub ]] || cog::helpers::die "$EX_USAGE" "MissingCommand" \
        "no command given" "" "" "run 'cog --help'"
      [[ $sub =~ ^[a-z][a-z0-9_-]*$ ]] || cog::helpers::die "$EX_USAGE" "BadCommandName" \
        "invalid command name" "command: ${sub}" "command names must match [a-z][a-z0-9_-]*" ""

      path="$(__cog_help_command_path "$sub")"
      if [[ ! -r $path ]]; then
        # A plugin documents itself: cog has no metadata for it beyond the
        # probe's one-line summary, so `cog help <plugin>` hands the question
        # to the plugin and passes its output and exit status through.
        local plugin_path=""
        if declare -F cog::fn::plugin_resolve >/dev/null \
          && plugin_path="$(cog::fn::plugin_resolve "$sub")"; then
          cog::fn::plugin_exec "$sub" "$plugin_path" --help
        fi
        cog::helpers::die "$EX_USAGE" "UnknownCommand" \
          "unknown command" "command: ${sub}" "" "run 'cog --help'"
      fi

      desc="$(__cog_help_desc_for "$path")" || return $?
      __cog_help_usage_for "$sub" "$path"
      cog::fn::ui_data ""
      cog::fn::ui_data "$desc"
      cog::fn::ui_data ""
      __cog_help_global_flags
      ;;
    *)
      cog::helpers::die "$EX_SOFTWARE" "BadCall" \
        "invalid help generation mode" "mode: ${mode}" "" \
        "call cog::fn::help_generate root or command"
      ;;
  esac
}
