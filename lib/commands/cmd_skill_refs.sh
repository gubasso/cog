# shellcheck shell=bash
: 'desc: Resolve in-repo/installed skill-source reference files.'

__cog_skill_refs_usage() {
  cog::fn::ui_data "Usage: cog skill-refs root"
  cog::fn::ui_data "Usage: cog skill-refs path <rel>"
  cog::fn::ui_data "Usage: cog skill-refs inspect [--json]"
}

cog::cmd::skill_refs() {
  local mode="${1:-}"
  local root resolved rel
  case "$mode" in
    -h | --help)
      __cog_skill_refs_usage
      ;;
    root)
      shift
      [[ $# -eq 0 ]] || cog::fn::error_raise "TooManyArguments" \
        "unexpected arguments to skill-refs root" \
        "usage: cog skill-refs root" "" "run 'cog skill-refs --help'"
      # shellcheck disable=SC2016 # Literal var names documented to the user, not expanded.
      root="$(cog::fn::skill_refs_root)" || cog::fn::error_raise "InputNotFound" \
        "skill-refs root not found" \
        'checked: $XDG_DATA_HOME/cog/skill-refs and ${LIB_DIR}/../skill-refs' "" \
        "deploy skill-refs (later round) or run from the cog repo"
      cog::fn::ui_data "$root"
      ;;
    path)
      shift
      [[ $# -le 1 ]] || cog::fn::error_raise "TooManyArguments" \
        "unexpected arguments to skill-refs path" \
        "usage: cog skill-refs path <rel>" "" "run 'cog skill-refs --help'"
      rel="${1:-}"
      [[ -n $rel ]] || cog::fn::error_raise "MissingArgument" \
        "missing skill-refs path" "usage: cog skill-refs path <rel>" "" \
        "run 'cog skill-refs --help'"
      case "$rel" in
        /* | *..*)
          cog::fn::error_raise "InvalidInput" "invalid skill-refs rel path" \
            "rel: ${rel}" "rel must be relative and contain no '..' segments" \
            "pass a path like foo/bar.md"
          ;;
      esac
      resolved="$(cog::fn::skill_refs_path "$rel")" || cog::fn::error_raise "InputNotFound" \
        "skill-refs path not found" "rel: ${rel}" \
        "unresolved root or missing target under the resolved root" \
        "verify the rel path and that skill-refs is deployed"
      cog::fn::ui_data "$resolved"
      ;;
    inspect)
      shift
      local json_mode=false inspect_json
      while (($# > 0)); do
        case "$1" in
          --json)
            json_mode=true
            shift
            ;;
          -*)
            cog::fn::error_raise "InvalidInput" "unknown skill-refs inspect option" \
              "option: $1" "" "run 'cog skill-refs --help'"
            ;;
          *)
            cog::fn::error_raise "TooManyArguments" "unexpected arguments to skill-refs inspect" \
              "argument: $1" "" "run 'cog skill-refs --help'"
            ;;
        esac
      done
      inspect_json="$(cog::fn::skill_refs_origin_json)"
      if [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]]; then
        cog::fn::json_emit \
          '(.ok|type=="boolean") and (.origin|type=="string") and (.writable|type=="boolean") and (.candidate_xdg|type=="string") and (.candidate_repo|type=="string")' \
          "$inspect_json"
      else
        cog::fn::ui_data "SKILLREFS_ROOT=$(jq -r '.root // ""' <<<"$inspect_json")"
        cog::fn::ui_data "SKILLREFS_ORIGIN=$(jq -r '.origin' <<<"$inspect_json")"
        cog::fn::ui_data "SKILLREFS_WRITABLE=$(jq -r '.writable' <<<"$inspect_json")"
      fi
      jq -e '.ok == true' <<<"$inspect_json" >/dev/null
      ;;
    "")
      cog::fn::error_raise "MissingArgument" "missing skill-refs subcommand" \
        "usage: cog skill-refs root | cog skill-refs path <rel> | cog skill-refs inspect" "" \
        "run 'cog skill-refs --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" "unknown skill-refs subcommand" \
        "subcommand: ${mode}" "" "run 'cog skill-refs --help'"
      ;;
  esac
}
