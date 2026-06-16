# shellcheck shell=bash

cog::main() {
  local version_file="${LIB_DIR}/../VERSION"

  [[ -r "$version_file" ]] || cog::helpers::die "$EX_SOFTWARE" "VersionUnavailable" \
    "VERSION file is missing or unreadable" "path: ${version_file}" "" ""

  # Thin global-flag pre-parse (R3 replaces with the real parser).
  case "${1:-}" in
    --version | -V)
      printf '%s\n' "$(<"$version_file")"
      return 0
      ;;
    --)
      shift # end-of-options; next token is the subcommand, rest pass through verbatim
      ;;
    "")
      cog::helpers::die "$EX_USAGE" "MissingCommand" \
        "no command given" "" "" "run 'cog <command>' or 'cog --version'"
      ;;
    -*)
      cog::helpers::die "$EX_USAGE" "UnknownGlobalFlag" \
        "unknown global flag" "flag: ${1}" \
        "global flag parsing is minimal in this version" "run 'cog --version'"
      ;;
  esac

  local sub="${1:-}"
  [[ -n "$sub" ]] || cog::helpers::die "$EX_USAGE" "MissingCommand" \
    "no command given" "" "" "run 'cog <command>'"
  shift

  cog::loader::dispatch "$sub" "$@"
}
