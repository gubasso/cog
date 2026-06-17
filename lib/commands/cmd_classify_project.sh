# shellcheck shell=bash
: 'desc: Classify repository shape.'

__cog_classify_project_self_check='.git_root != null and (.languages|type=="array") and (.project_types|type=="array") and (.frameworks|type=="array") and (.cli_signals|type=="array") and (.is_cli|type=="boolean") and (.is_monorepo|type=="boolean")'

__cog_classify_project_usage() {
  cog::fn::ui_data "Usage: cog classify-project (<out.json>|--json)"
}

__cog_classify_project_json_string_array() {
  if [[ $# -eq 0 ]]; then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

__cog_classify_project_json_object_array() {
  if [[ $# -eq 0 ]]; then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -s .
  fi
}

__cog_classify_project_find_files() {
  find "$PROJECT_ROOT" -path "$PROJECT_ROOT/.git" -prune -o -type f "$@"
}

__cog_classify_project_count_files() {
  __cog_classify_project_find_files -print | wc -l | tr -d ' '
}

__cog_classify_project_count_named_files() {
  local name="$1"
  __cog_classify_project_find_files -name "$name" -print | wc -l | tr -d ' '
}

__cog_classify_project_has_file() {
  [[ -f $PROJECT_ROOT/$1 ]]
}

__cog_classify_project_has_dir() {
  [[ -d $PROJECT_ROOT/$1 ]]
}

__cog_classify_project_file_contains() {
  local file="$1" pattern="$2"
  [[ -f $PROJECT_ROOT/$file ]] && grep -Eq "$pattern" "$PROJECT_ROOT/$file"
}

__cog_classify_project_tree_contains() {
  local pattern="$1"
  __cog_classify_project_find_files -print0 \
    | xargs -0 grep -EIl "$pattern" 2>/dev/null \
    | head -n 1 \
    | grep -q .
}

__cog_classify_project_count_shell_shebangs() {
  __cog_classify_project_find_files -print0 \
    | xargs -0 awk 'FNR == 1 && /^#!.*(ba|z|fi)?sh/ {count++} END {print count + 0}' 2>/dev/null \
    | awk '{sum += $1} END {print sum + 0}'
}

__cog_classify_project_add_language() {
  local lang="$1" detected_by="$2" confidence="${3:-high}"
  LANGUAGES+=("$(jq -cn --arg lang "$lang" --arg confidence "$confidence" --arg detected_by "$detected_by" \
    '{lang: $lang, confidence: $confidence, detected_by: $detected_by}')")
}

__cog_classify_project_add_framework() {
  local name="$1" lang="$2" detected_by="$3"
  FRAMEWORKS+=("$(jq -cn --arg name "$name" --arg lang "$lang" --arg detected_by "$detected_by" \
    '{name: $name, lang: $lang, detected_by: $detected_by}')")
}

__cog_classify_project_root() {
  local root
  if root="$(cog::fn::git_root 2>/dev/null)"; then
    printf '%s\n' "$root"
  else
    pwd -P
  fi
}

__cog_classify_project_detect_languages() {
  __cog_classify_project_has_file Cargo.toml && __cog_classify_project_add_language rust "Cargo.toml"
  if __cog_classify_project_has_file pyproject.toml; then
    __cog_classify_project_add_language python "pyproject.toml"
  elif __cog_classify_project_has_file setup.py; then
    __cog_classify_project_add_language python "setup.py"
  fi
  __cog_classify_project_has_file package.json && __cog_classify_project_add_language javascript "package.json"
  __cog_classify_project_has_file go.mod && __cog_classify_project_add_language go "go.mod"
  if __cog_classify_project_has_file Makefile && [[ $(__cog_classify_project_count_named_files '*.c') -gt 0 ]]; then
    __cog_classify_project_add_language c "Makefile plus *.c"
  fi
  __cog_classify_project_has_file build.zig && __cog_classify_project_add_language zig "build.zig"

  local total sh_files shebangs
  total="$(__cog_classify_project_count_files)"
  sh_files="$(__cog_classify_project_count_named_files '*.sh')"
  shebangs="$(__cog_classify_project_count_shell_shebangs)"
  if [[ $total -gt 0 ]] && { [[ $((sh_files * 2)) -gt $total ]] || [[ $((shebangs * 2)) -gt $total ]]; }; then
    __cog_classify_project_add_language bash "majority *.sh scripts or shell shebang prevalence"
  fi
  if __cog_classify_project_has_file package.json && [[ $(__cog_classify_project_count_named_files '*.svelte') -gt 0 ]]; then
    __cog_classify_project_add_language svelte "package.json plus *.svelte"
  fi
  [[ $(__cog_classify_project_count_named_files '*.R') -gt 0 ]] && __cog_classify_project_add_language r "*.R"
  [[ $(__cog_classify_project_count_named_files '*.lua') -gt 0 ]] && __cog_classify_project_add_language lua "*.lua"
  # Always succeed: this populates LANGUAGES via optional probes, and the trailing
  # `[[ … ]] && …` would otherwise leak exit 1 and abort build_json under `set -e`.
  return 0
}

__cog_classify_project_detect_cli() {
  if __cog_classify_project_file_contains Cargo.toml '^\[\[bin\]\]'; then
    CLI_SIGNALS+=("Cargo.toml with [[bin]] section")
  fi
  if __cog_classify_project_file_contains Cargo.toml '(^|[[:space:]])clap([[:space:]]*=|[[:space:]])' \
    || __cog_classify_project_file_contains Cargo.toml '^\[(workspace\.)?(dev-|build-)?dependencies\.clap\]'; then
    CLI_SIGNALS+=("clap dependency")
    __cog_classify_project_add_framework clap rust "clap in Cargo.toml deps"
  fi
  if __cog_classify_project_file_contains pyproject.toml '^\[project\.scripts\]' || __cog_classify_project_tree_contains 'console_scripts'; then
    CLI_SIGNALS+=("Python project scripts or console_scripts")
  fi
  if __cog_classify_project_tree_contains '(^|[^[:alnum:]_])typer([^[:alnum:]_]|$)'; then
    CLI_SIGNALS+=("typer dependency/import")
    __cog_classify_project_add_framework typer python "typer dependency/import signal"
  fi
  if __cog_classify_project_tree_contains '(^|[^[:alnum:]_])click([^[:alnum:]_]|$)'; then
    CLI_SIGNALS+=("click dependency/import")
    __cog_classify_project_add_framework click python "click dependency/import signal"
  fi
  __cog_classify_project_has_dir bin && CLI_SIGNALS+=("bin/ directory")
  __cog_classify_project_has_dir cli && CLI_SIGNALS+=("cli/ directory")
  if __cog_classify_project_find_files -perm /111 -print0 \
    | xargs -0 awk 'FNR == 1 && /^#!/ {found=1} END {exit found ? 0 : 1}' 2>/dev/null; then
    CLI_SIGNALS+=("executable shebang scripts")
  fi
  if __cog_classify_project_tree_contains '(^|[^[:alnum:]_])cobra([^[:alnum:]_]|$)'; then
    CLI_SIGNALS+=("cobra dependency/import")
    __cog_classify_project_add_framework cobra go "cobra dependency/import signal"
  fi
  if __cog_classify_project_tree_contains '(^|[^[:alnum:]_])commander([^[:alnum:]_]|$)'; then
    CLI_SIGNALS+=("commander dependency/import")
    __cog_classify_project_add_framework commander javascript "commander dependency/import signal"
  fi
  if __cog_classify_project_tree_contains '(^|[^[:alnum:]_])yargs([^[:alnum:]_]|$)'; then
    CLI_SIGNALS+=("yargs dependency/import")
    __cog_classify_project_add_framework yargs javascript "yargs dependency/import signal"
  fi
}

__cog_classify_project_monorepo() {
  if __cog_classify_project_file_contains Cargo.toml '^\[workspace\]' \
    || __cog_classify_project_has_file pnpm-workspace.yaml \
    || __cog_classify_project_has_file lerna.json \
    || [[ $(__cog_classify_project_count_named_files go.mod) -gt 1 ]]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

__cog_classify_project_build_json() {
  PROJECT_ROOT="$(__cog_classify_project_root)"
  LANGUAGES=()
  FRAMEWORKS=()
  CLI_SIGNALS=()
  __cog_classify_project_detect_languages
  __cog_classify_project_detect_cli

  local is_cli=false project_types_json
  [[ ${#CLI_SIGNALS[@]} -gt 0 ]] && is_cli=true
  if [[ $is_cli == true ]]; then
    project_types_json="$(__cog_classify_project_json_string_array cli)"
  else
    project_types_json='[]'
  fi
  jq -n \
    --arg git_root "$PROJECT_ROOT" \
    --argjson languages "$(__cog_classify_project_json_object_array "${LANGUAGES[@]}")" \
    --argjson project_types "$project_types_json" \
    --argjson frameworks "$(__cog_classify_project_json_object_array "${FRAMEWORKS[@]}")" \
    --argjson cli_signals "$(__cog_classify_project_json_string_array "${CLI_SIGNALS[@]}")" \
    --argjson is_cli "$is_cli" \
    --argjson is_monorepo "$(__cog_classify_project_monorepo)" \
    '{git_root: $git_root, languages: $languages, project_types: $project_types, frameworks: $frameworks,
      cli_signals: $cli_signals, is_cli: $is_cli, is_monorepo: $is_monorepo}'
}

cog::cmd::classify_project() {
  local mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_classify_project_usage
        return 0
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate classify-project output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown classify-project option" "option: $1" "" "run 'cog classify-project --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many classify-project output paths" "argument: $1" "" "run 'cog classify-project --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing classify-project output mode" "usage: cog classify-project (<out.json>|--json)" "" "run 'cog classify-project --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_classify_project_build_json)"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_classify_project_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_classify_project_self_check" "$json"
  fi
}
