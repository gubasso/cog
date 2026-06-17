# shellcheck shell=bash
: 'desc: Detect suckless tree signals and clean state.'

__cog_suckless_preflight_self_check='(.ok|type=="boolean") and (.is_suckless_tree|type=="boolean") and (.signals|type=="object") and (.status|type=="object") and (.clean_tree|type=="boolean")'

__cog_suckless_preflight_usage() {
  cog::fn::ui_data "Usage: cog suckless-preflight (<out.json>|--json)"
}

__cog_suckless_preflight_json_string_array() {
  if (($# == 0)); then
    jq -cn '[]'
    return 0
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
  return 0
}

__cog_suckless_preflight_detect_project() {
  if [[ -f dwm.c ]]; then
    printf '%s\n' dwm
  elif [[ -f st.c ]]; then
    printf '%s\n' st
  elif [[ -f dmenu.c ]]; then
    printf '%s\n' dmenu
  elif [[ -f surf.c ]]; then
    printf '%s\n' surf
  else
    printf '%s\n' unknown
  fi
  return 0
}

__cog_suckless_preflight_build_json() {
  local repo_root has_config_mk has_makefile has_config_def_h has_config_h is_suckless_tree clean_tree ok reason detected_project status
  local -a c_files=()

  if ! repo_root="$(cog::fn::git_root 2>/dev/null)"; then
    jq -n \
      --argjson ok false \
      --argjson is_suckless_tree false \
      --argjson clean_tree false \
      '{
        ok: $ok,
        repo_root: null,
        is_suckless_tree: $is_suckless_tree,
        detected_project: "unknown",
        signals: {
          has_config_mk: false,
          has_makefile: false,
          c_files: [],
          has_config_def_h: false,
          has_config_h: false
        },
        clean_tree: $clean_tree,
        status: {root: null, branch: "", files: []},
        reason: "not a git work tree"
      }'
    return 0
  fi

  has_config_mk=false
  has_makefile=false
  has_config_def_h=false
  has_config_h=false
  [[ -f config.mk ]] && has_config_mk=true
  [[ -f Makefile ]] && has_makefile=true
  [[ -f config.def.h ]] && has_config_def_h=true
  [[ -f config.h ]] && has_config_h=true
  mapfile -t c_files < <(find . -maxdepth 1 -type f -name '*.c' -printf '%f\n' | LC_ALL=C sort)

  is_suckless_tree=false
  if [[ $has_config_mk == true && $has_makefile == true && ${#c_files[@]} -gt 0 ]]; then
    is_suckless_tree=true
  fi

  status="$(cog::fn::git_status_json)"
  clean_tree=false
  if jq -e '.files | length == 0' <<<"$status" >/dev/null; then
    clean_tree=true
  fi

  ok=false
  reason="not a suckless source tree"
  if [[ $is_suckless_tree == true && $clean_tree == true ]]; then
    ok=true
    reason=""
  elif [[ $is_suckless_tree == true && $clean_tree == false ]]; then
    reason="dirty git tree"
  fi

  detected_project="$(__cog_suckless_preflight_detect_project)"

  jq -n \
    --argjson ok "$ok" \
    --arg repo_root "$repo_root" \
    --argjson is_suckless_tree "$is_suckless_tree" \
    --arg detected_project "$detected_project" \
    --argjson has_config_mk "$has_config_mk" \
    --argjson has_makefile "$has_makefile" \
    --argjson c_files "$(__cog_suckless_preflight_json_string_array "${c_files[@]}")" \
    --argjson has_config_def_h "$has_config_def_h" \
    --argjson has_config_h "$has_config_h" \
    --argjson clean_tree "$clean_tree" \
    --argjson status "$status" \
    --arg reason "$reason" \
    '{
      ok: $ok,
      repo_root: $repo_root,
      is_suckless_tree: $is_suckless_tree,
      detected_project: $detected_project,
      signals: {
        has_config_mk: $has_config_mk,
        has_makefile: $has_makefile,
        c_files: $c_files,
        has_config_def_h: $has_config_def_h,
        has_config_h: $has_config_h
      },
      clean_tree: $clean_tree,
      status: $status,
      reason: (if $ok then null else $reason end)
    }'
  return 0
}

cog::cmd::suckless_preflight() {
  local mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_suckless_preflight_usage
        return 0
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate suckless-preflight output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown suckless-preflight option" "option: $1" "" "run 'cog suckless-preflight --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many suckless-preflight output paths" "argument: $1" "" "run 'cog suckless-preflight --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing suckless-preflight output mode" "usage: cog suckless-preflight (<out.json>|--json)" "" "run 'cog suckless-preflight --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_suckless_preflight_build_json)"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_suckless_preflight_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_suckless_preflight_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
