# shellcheck shell=bash
: 'desc: Detect pre-commit template type.'

__cog_precommit_detect_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.template_root|type=="string") and (.conflicts|type=="array") and (.signals|type=="array")'

__cog_precommit_detect_usage() {
  cog::fn::ui_data "Usage: cog precommit-detect [--project-root <dir>] [--template-root <dir>] [--type <type>] (<out.json>|--json)"
}

__cog_precommit_template_root_default() {
  realpath -m "${LIB_DIR}/../templates/pre-commit"
}

if ! declare -F __cog_classify_project_build_json >/dev/null; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_classify_project.sh"
fi

__cog_precommit_detect_json_string_array() {
  if [[ $# -eq 0 ]]; then jq -cn '[]'; else printf '%s\n' "$@" | jq -R . | jq -s .; fi
}

__cog_precommit_detect_find_files() {
  find "$PROJECT_ROOT" -path "$PROJECT_ROOT/.git" -prune -o -type f "$@"
}

__cog_precommit_detect_has_file() {
  [[ -f $PROJECT_ROOT/$1 ]]
}

__cog_precommit_detect_count_named_files() {
  local name="$1"
  __cog_precommit_detect_find_files -name "$name" -print | wc -l | tr -d ' '
}

__cog_precommit_detect_language_present() {
  local classification="$1" lang="$2"
  jq -e --arg lang "$lang" '.languages[]? | select(.lang == $lang)' <<<"$classification" >/dev/null
}

__cog_precommit_detect_add_match() {
  MATCHES+=("$1")
  SIGNALS+=("$2")
}

__cog_precommit_detect_matches() {
  local classification="$1"
  MATCHES=()
  SIGNALS=()
  if __cog_precommit_detect_language_present "$classification" svelte; then
    __cog_precommit_detect_add_match sveltekit "package.json plus *.svelte"
  fi
  if __cog_precommit_detect_language_present "$classification" rust; then
    __cog_precommit_detect_add_match rust "Cargo.toml"
  fi
  if __cog_precommit_detect_language_present "$classification" python; then
    __cog_precommit_detect_add_match python "python language signal"
  elif __cog_precommit_detect_has_file requirements.txt; then
    __cog_precommit_detect_add_match python "requirements.txt"
  fi
  if __cog_precommit_detect_language_present "$classification" javascript && ! __cog_precommit_detect_language_present "$classification" svelte; then
    __cog_precommit_detect_add_match node "package.json"
  fi
  if __cog_precommit_detect_language_present "$classification" c; then
    __cog_precommit_detect_add_match c "c language signal"
  elif [[ $(__cog_precommit_detect_count_named_files '*.h') -gt 0 ]] || __cog_precommit_detect_has_file CMakeLists.txt; then
    __cog_precommit_detect_add_match c "*.h or CMakeLists.txt"
  fi
  if __cog_precommit_detect_language_present "$classification" zig; then
    __cog_precommit_detect_add_match zig "zig language signal"
  elif [[ $(__cog_precommit_detect_count_named_files '*.zig') -gt 0 ]]; then
    __cog_precommit_detect_add_match zig "*.zig"
  fi
  if __cog_precommit_detect_language_present "$classification" bash; then
    __cog_precommit_detect_add_match bash "bash language signal"
  elif [[ $(__cog_precommit_detect_count_named_files '*.bash') -gt 0 || $(__cog_precommit_detect_count_named_files '*.bats') -gt 0 ]]; then
    __cog_precommit_detect_add_match bash "*.bash or *.bats"
  fi
}

__cog_precommit_detect_build_json() {
  local project_root="$1" template_root="$2" requested_type="$3"
  local ok=true reason="" detected_type="" confidence=none classification='{}'
  local template_dir="" template_config="" template_exists=false conflicts_json signals_json
  PROJECT_ROOT="$project_root"
  if [[ -n $requested_type && ! $requested_type =~ ^[a-z0-9-]+$ ]]; then
    ok=false; reason="type must match ^[a-z0-9-]+$"
  elif [[ ! -d $project_root ]]; then
    ok=false; reason="project root is not a directory"
  elif [[ ! -d $template_root ]]; then
    ok=false; reason="template root is not a directory"
  fi
  if [[ $ok == true ]]; then
    classification="$(cd "$project_root" && __cog_classify_project_build_json)"
    if [[ -n $requested_type ]]; then
      detected_type="$requested_type"; confidence=requested; SIGNALS=("requested type"); MATCHES=("$requested_type")
    else
      __cog_precommit_detect_matches "$classification"
      if [[ ${#MATCHES[@]} -eq 1 ]]; then
        detected_type="${MATCHES[0]}"; confidence=high
      elif [[ ${#MATCHES[@]} -gt 1 ]]; then
        ok=false; reason="multiple pre-commit template types detected"
      else
        ok=false; reason="could not detect pre-commit template type"
      fi
    fi
    if [[ -n $detected_type ]]; then
      template_dir="$template_root/$detected_type"
      template_config="$template_dir/.pre-commit-config.yaml"
      if [[ -f $template_config ]]; then template_exists=true; else ok=false; reason="${reason:-template config not found}"; fi
    fi
  else
    MATCHES=(); SIGNALS=()
  fi
  conflicts_json='[]'
  if [[ $ok == false && ${#MATCHES[@]} -gt 1 && -z $requested_type ]]; then
    conflicts_json="$(__cog_precommit_detect_json_string_array "${MATCHES[@]}")"
  fi
  signals_json="$(__cog_precommit_detect_json_string_array "${SIGNALS[@]}")"
  jq -n \
    --argjson ok "$ok" --arg project_root "$project_root" --arg template_root "$template_root" \
    --arg requested_type "$requested_type" --arg detected_type "$detected_type" --arg confidence "$confidence" \
    --argjson classification "$classification" --argjson signals "$signals_json" --argjson conflicts "$conflicts_json" \
    --arg template_dir "$template_dir" --arg template_config "$template_config" --argjson template_exists "$template_exists" \
    --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root,
      requested_type: (if $requested_type == "" then null else $requested_type end),
      detected_type: (if $detected_type == "" then null else $detected_type end),
      confidence: $confidence, classification: $classification, signals: $signals, conflicts: $conflicts,
      template_dir: $template_dir, template_config: $template_config, template_exists: $template_exists,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::precommit_detect() {
  local project_root template_root requested_type="" mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(__cog_precommit_template_root_default)"
  while (($# > 0)); do
    case "$1" in
      -h | --help) __cog_precommit_detect_usage; return 0 ;;
      --project-root) [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog precommit-detect --help'"; project_root="$2"; shift 2 ;;
      --template-root) [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template root" "option: --template-root" "" "run 'cog precommit-detect --help'"; template_root="$2"; shift 2 ;;
      --type) [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template type" "option: --type" "" "run 'cog precommit-detect --help'"; requested_type="$2"; shift 2 ;;
      --json) [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate precommit-detect output mode" "" "" "choose either --json or an output path"; mode=json; shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown precommit-detect option" "option: $1" "" "run 'cog precommit-detect --help'" ;;
      *) [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many precommit-detect output paths" "argument: $1" "" "run 'cog precommit-detect --help'"; out="$1"; mode=file; shift ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing precommit-detect output mode" "usage: cog precommit-detect [flags] (<out.json>|--json)" "" "run 'cog precommit-detect --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_precommit_detect_build_json "$project_root" "$template_root" "$requested_type")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_precommit_detect_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_precommit_detect_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
