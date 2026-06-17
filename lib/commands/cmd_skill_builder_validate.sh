# shellcheck shell=bash
: 'desc: Validate skill-builder inputs.'

__cog_skill_builder_validate_self_check='(.ok|type=="boolean") and (.name|type=="string") and (.scope|type=="string") and (.valid_name|type=="boolean") and (.collisions|type=="array") and (.invalid_characters|type=="array")'
__cog_skill_builder_validate_draft_self_check='(.ok|type=="boolean") and (.mode=="draft") and (.line_count|type=="number") and (.under_500|type=="boolean") and (.valid_name|type=="boolean") and (.has_trigger_tests|type=="boolean") and (.emojis|type=="array") and (.untagged_fences|type=="array")'

__cog_skill_builder_validate_usage() {
  cog::fn::ui_data "Usage: cog skill-builder-validate (--name <skill-name>|--draft <SKILL.md>) [--scope personal|project] [--project-root <dir>] [--home <dir>] [--run-dir <dir>] (<out.json>|--json)"
}

__cog_skill_builder_json_string_array() {
  if [[ $# -eq 0 ]]; then jq -cn '[]'; else printf '%s\n' "$@" | jq -R . | jq -s .; fi
}

__cog_skill_builder_invalid_characters_json() {
  local name="$1" char existing i
  local -a chars=()
  for ((i = 0; i < ${#name}; i++)); do
    char="${name:i:1}"
    [[ $char =~ [a-z0-9-] ]] && continue
    existing=false
    for item in "${chars[@]}"; do [[ $item == "$char" ]] && existing=true && break; done
    [[ $existing == true ]] || chars+=("$char")
  done
  __cog_skill_builder_json_string_array "${chars[@]}"
}

__cog_skill_builder_personal_root() {
  local home_dir="$1"
  printf '%s\n' "${COG_SKILLS_HOME:-${home_dir}/.local/share/cog/skills}"
}

__cog_skill_builder_validate_build_json() {
  local name="$1" scope="$2" project_root="$3" home_dir="$4" run_dir="$5"
  local ok=true valid_name=true reason="" invalid_chars collisions_json personal_root
  local -a collisions=()
  if [[ ! $name =~ ^[a-z0-9-]{1,64}$ ]]; then ok=false; valid_name=false; reason="invalid skill name"; fi
  if [[ $scope != personal && $scope != project ]]; then ok=false; reason="${reason:-scope must be personal or project}"; fi
  if [[ $scope == personal && -z $run_dir ]]; then ok=false; reason="${reason:-run dir required for personal scope}"; fi
  if [[ -n $name ]]; then
    personal_root="$(__cog_skill_builder_personal_root "$home_dir")"
    if [[ $scope == personal && -e $personal_root/claude/$name ]]; then
      collisions+=("$personal_root/claude/$name"); ok=false; reason="${reason:-skill name collision}"
    fi
    if [[ $scope == project && -e $project_root/skills/claude/$name ]]; then
      collisions+=("$project_root/skills/claude/$name"); ok=false; reason="${reason:-skill name collision}"
    fi
    if [[ $scope == project && -e $project_root/skills/codex/$name ]]; then
      collisions+=("$project_root/skills/codex/$name"); ok=false; reason="${reason:-skill name collision}"
    fi
  fi
  invalid_chars="$(__cog_skill_builder_invalid_characters_json "$name")"
  collisions_json="$(__cog_skill_builder_json_string_array "${collisions[@]}")"
  jq -n \
    --argjson ok "$ok" --arg name "$name" --arg scope "$scope" --arg project_root "$project_root" \
    --arg home "$home_dir" --arg run_dir "$run_dir" --argjson valid_name "$valid_name" \
    --argjson invalid_characters "$invalid_chars" --argjson collisions "$collisions_json" --arg reason "$reason" \
    '{ok: $ok, name: $name, scope: $scope, project_root: $project_root, home: $home, run_dir: $run_dir,
      valid_name: $valid_name, invalid_characters: $invalid_characters, collisions: $collisions,
      reason: (if $ok then null else $reason end)}'
}

__cog_skill_builder_nums_to_json() {
  jq -R 'select(length > 0) | tonumber' | jq -s 'unique'
}

__cog_skill_builder_validate_draft_json() {
  local file="$1" name line_count under_500 valid_name has_trigger_tests ok reason="" emoji_lines fence_lines emojis_json fences_json
  [[ -r $file && -f $file ]] || cog::fn::error_raise "InputUnreadable" "draft skill file is not readable" "path: ${file}" "" "check the path"
  line_count="$(wc -l <"$file")"; line_count="${line_count//[^0-9]/}"
  if [[ $line_count -le 500 ]]; then under_500=true; else under_500=false; fi
  name="$(awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f && /^name:[[:space:]]/{sub(/^name:[[:space:]]*/,""); print; exit}' "$file")"
  name="${name%\"}"; name="${name#\"}"; name="${name%\'}"; name="${name#\'}"; name="${name%"${name##*[![:space:]]}"}"
  if [[ $name =~ ^[a-z0-9-]{1,64}$ ]]; then valid_name=true; else valid_name=false; fi
  if grep -qE '<!--[[:space:]]*trigger-tests:' "$file"; then has_trigger_tests=true; else has_trigger_tests=false; fi
  emoji_lines="$(grep -nP '[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{1F1E6}-\x{1F1FF}]' "$file" | cut -d: -f1 || true)"
  fence_lines="$(awk '/^```/{if(!inf){inf=1; l=$0; sub(/^```[ \t]*/,"",l); if(l=="") print NR} else {inf=0}}' "$file" || true)"
  emojis_json="$(printf '%s\n' "$emoji_lines" | __cog_skill_builder_nums_to_json)"
  fences_json="$(printf '%s\n' "$fence_lines" | __cog_skill_builder_nums_to_json)"
  ok=true
  [[ $under_500 == true ]] || { ok=false; reason="SKILL.md exceeds 500 lines"; }
  [[ $valid_name == true ]] || { ok=false; reason="${reason:-invalid or missing skill name}"; }
  [[ $has_trigger_tests == true ]] || { ok=false; reason="${reason:-missing trigger-tests comment}"; }
  [[ $emojis_json == "[]" ]] || { ok=false; reason="${reason:-emoji characters present}"; }
  [[ $fences_json == "[]" ]] || { ok=false; reason="${reason:-untagged code fences}"; }
  jq -n --argjson ok "$ok" --arg file "$file" --argjson line_count "$line_count" --argjson under_500 "$under_500" \
    --arg name "$name" --argjson valid_name "$valid_name" --argjson has_trigger_tests "$has_trigger_tests" \
    --argjson emojis "$emojis_json" --argjson untagged_fences "$fences_json" --arg reason "$reason" \
    '{ok: $ok, mode: "draft", file: $file, line_count: $line_count, under_500: $under_500,
      name: $name, valid_name: $valid_name, has_trigger_tests: $has_trigger_tests,
      emojis: $emojis, untagged_fences: $untagged_fences, reason: (if $ok then null else $reason end)}'
}

cog::cmd::skill_builder_validate() {
  local name="" scope=personal project_root home_dir="${HOME:-}" run_dir="${RUN_DIR:-}" draft_file="" mode="" out="" json check
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help) __cog_skill_builder_validate_usage; return 0 ;;
      --name) [[ $# -ge 2 && -z $name ]] || cog::fn::error_raise "MissingArgument" "missing skill name" "option: --name" "" "run 'cog skill-builder-validate --help'"; name="$2"; shift 2 ;;
      --scope) [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing skill scope" "option: --scope" "" "run 'cog skill-builder-validate --help'"; scope="$2"; shift 2 ;;
      --project-root) [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog skill-builder-validate --help'"; project_root="$2"; shift 2 ;;
      --home) [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing home dir" "option: --home" "" "run 'cog skill-builder-validate --help'"; home_dir="$2"; shift 2 ;;
      --run-dir) [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing run dir" "option: --run-dir" "" "run 'cog skill-builder-validate --help'"; run_dir="$2"; shift 2 ;;
      --draft) [[ $# -ge 2 && -z $draft_file ]] || cog::fn::error_raise "MissingArgument" "missing draft file" "option: --draft" "" "run 'cog skill-builder-validate --help'"; draft_file="$2"; shift 2 ;;
      --json) [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate skill-builder-validate output mode" "" "" "choose either --json or an output path"; mode=json; shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown skill-builder-validate option" "option: $1" "" "run 'cog skill-builder-validate --help'" ;;
      *) [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many skill-builder-validate output paths" "argument: $1" "" "run 'cog skill-builder-validate --help'"; out="$1"; mode=file; shift ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing skill-builder-validate output mode" "usage: cog skill-builder-validate ... (<out.json>|--json)" "" "run 'cog skill-builder-validate --help'"
  [[ -n $mode ]] || mode=json
  if [[ -n $draft_file && -z $name ]]; then
    json="$(__cog_skill_builder_validate_draft_json "$draft_file")"; check="$__cog_skill_builder_validate_draft_self_check"
  elif [[ -n $name && -z $draft_file ]]; then
    json="$(__cog_skill_builder_validate_build_json "$name" "$scope" "$project_root" "$home_dir" "$run_dir")"; check="$__cog_skill_builder_validate_self_check"
  else
    cog::fn::error_raise "InvalidInput" "choose exactly one validation mode" "" "pass --name or --draft" "run 'cog skill-builder-validate --help'"
  fi
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$check" "$json"; else cog::fn::json_write_fragment "$out" "$check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
