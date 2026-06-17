# shellcheck shell=bash
: 'desc: Resolve and initialize the shared tsk store.'

__cog_tsk_store_init_self_check='.store != "" and .config_path != "" and .template_path != "" and .config_exists == true and (.template_exists|type=="boolean") and (.initialized|type=="boolean") and ((.doctor_repo|type=="string") or .doctor_repo == null)'

__cog_tsk_store_init_usage() {
  cog::fn::ui_data "Usage: cog tsk-store-init (<out.json>|--json)"
}

__cog_tsk_store_init_build_json() {
  __have tsk || cog::fn::error_raise "MissingRequirement" "required command not found" "command: tsk" "" "install tsk and retry"
  local doctor_out doctor_repo store config_path template_path initialized=false template_exists=false
  doctor_out="$(tsk doctor 2>/dev/null || true)"
  doctor_repo="$(printf '%s\n' "$doctor_out" \
    | sed -n 's/^[[:space:]]*riptask_repo[[:space:]]*=[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1/p' \
    | head -n 1)"
  store="${doctor_repo:-${RIPTASK_REPO:-${XDG_DATA_HOME:-$HOME/.local/share}/riptask}}"
  config_path="$store/config.yaml"
  template_path="$store/templates/task.md"
  if [[ ! -f $config_path ]]; then
    tsk init --system >&2
    initialized=true
  fi
  [[ -f $config_path ]] || cog::fn::error_raise "InputNotFound" "tsk store config not present after init" "path: ${config_path}" "" "check tsk store setup"
  if [[ -f $template_path ]]; then
    template_exists=true
  elif declare -F cog::fn::log_warn >/dev/null; then
    cog::fn::log_warn "cog::tsk-store-init" "msg=tsk store template missing" "path=${template_path}"
  fi
  jq -n --arg store "$store" --arg config_path "$config_path" --arg template_path "$template_path" \
    --argjson config_exists true --argjson template_exists "$template_exists" --argjson initialized "$initialized" \
    --arg doctor_repo "$doctor_repo" \
    '{store: $store, config_path: $config_path, template_path: $template_path, config_exists: $config_exists,
      template_exists: $template_exists, initialized: $initialized,
      doctor_repo: (if $doctor_repo == "" then null else $doctor_repo end)}'
}

cog::cmd::tsk_store_init() {
  local mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_tsk_store_init_usage
        return 0
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate tsk-store-init output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown tsk-store-init option" "option: $1" "" "run 'cog tsk-store-init --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many tsk-store-init output paths" "argument: $1" "" "run 'cog tsk-store-init --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing tsk-store-init output mode" "usage: cog tsk-store-init (<out.json>|--json)" "" "run 'cog tsk-store-init --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_tsk_store_init_build_json)"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_tsk_store_init_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_tsk_store_init_self_check" "$json"; fi
}
