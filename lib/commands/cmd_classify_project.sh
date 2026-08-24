# shellcheck shell=bash
: 'desc: Classify repository shape.'

__cog_classify_project_self_check='.git_root != null and (.languages|type=="array") and (.project_types|type=="array") and (.frameworks|type=="array") and (.cli_signals|type=="array") and (.is_cli|type=="boolean") and (.is_monorepo|type=="boolean") and ((.primary_type|type=="string") or (.primary_type==null)) and (.confidence|type=="string") and (.ambiguous|type=="boolean")'

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

# Count files whose extension is in the given set (args are bare extensions).
__cog_classify_project_count_ext() {
  local -a preds=()
  local e
  for e in "$@"; do
    preds+=(-o -name "*.$e")
  done
  preds=("${preds[@]:1}")
  __cog_classify_project_find_files \( "${preds[@]}" \) -print | wc -l | tr -d ' '
}

# Content/prose files: they describe a project but never classify its code.
__cog_classify_project_count_content_files() {
  __cog_classify_project_count_ext md mdx markdown rst txt org adoc
}

# Source files in a recognized programming language.
__cog_classify_project_count_code_files() {
  __cog_classify_project_count_ext \
    rs py js jsx ts tsx mjs cjs go c h cc cpp hpp zig sh bash bats lua R svelte rb java kt nix
}

# Scoped keyword scan: grep a pattern only across the named file globs (a
# language's own sources and manifests), never across the whole tree or prose.
# Usage: __cog_classify_project_scan '<ere pattern>' '<glob>' ['<glob>' ...]
__cog_classify_project_scan() {
  local pattern="$1"
  shift
  local -a preds=()
  local g
  for g in "$@"; do
    preds+=(-o -name "$g")
  done
  preds=("${preds[@]:1}")
  __cog_classify_project_find_files \( "${preds[@]}" \) -print0 \
    | xargs -0 grep -EIl "$pattern" 2>/dev/null \
    | head -n 1 \
    | grep -q .
}

# A root build manifest is an authoritative, high-confidence project verdict.
__cog_classify_project_has_build_manifest() {
  __cog_classify_project_has_file Cargo.toml \
    || __cog_classify_project_has_file pyproject.toml \
    || __cog_classify_project_has_file setup.py \
    || __cog_classify_project_has_file package.json \
    || __cog_classify_project_has_file go.mod \
    || __cog_classify_project_has_file build.zig
}

# True when bin/ holds an executable shell entrypoint (a shell-CLI signal that
# survives even in a doc-heavy repo where scripts are not the file majority).
__cog_classify_project_has_shell_entrypoint() {
  __cog_classify_project_has_dir bin || return 1
  find "$PROJECT_ROOT/bin" -maxdepth 1 -type f -perm /111 -print0 2>/dev/null \
    | xargs -0 awk 'FNR == 1 && /^#!.*(ba|z|fi)?sh/ {found = 1} END {exit found ? 0 : 1}' 2>/dev/null
}

# Whether a language (or any non-content language) is in the detected set.
__cog_classify_project_has_language() {
  local lang="$1"
  [[ ${#LANGUAGES[@]} -gt 0 ]] || return 1
  printf '%s\n' "${LANGUAGES[@]}" | jq -se --arg l "$lang" 'any(.[]; .lang == $l)' >/dev/null 2>&1
}

__cog_classify_project_has_code_language() {
  [[ ${#LANGUAGES[@]} -gt 0 ]] || return 1
  printf '%s\n' "${LANGUAGES[@]}" | jq -se 'any(.[]; .lang != "markdown")' >/dev/null 2>&1
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
  # Manifest-anchored probes are authoritative.
  __cog_classify_project_has_file Cargo.toml && __cog_classify_project_add_language rust "Cargo.toml"
  if __cog_classify_project_has_file pyproject.toml; then
    __cog_classify_project_add_language python "pyproject.toml"
  elif __cog_classify_project_has_file setup.py; then
    __cog_classify_project_add_language python "setup.py"
  fi
  __cog_classify_project_has_file package.json && __cog_classify_project_add_language javascript "package.json"
  __cog_classify_project_has_file go.mod && __cog_classify_project_add_language go "go.mod"
  if [[ $(__cog_classify_project_count_named_files '*.c') -gt 0 ]]; then
    local c_build=""
    if __cog_classify_project_has_file CMakeLists.txt; then
      c_build=CMakeLists.txt
    elif __cog_classify_project_has_file meson.build; then
      c_build=meson.build
    elif __cog_classify_project_has_file configure.ac; then
      c_build=configure.ac
    elif __cog_classify_project_has_file config.mk; then
      c_build=config.mk
    fi
    [[ -n $c_build ]] && __cog_classify_project_add_language c "$c_build plus *.c"
  fi
  __cog_classify_project_has_file build.zig && __cog_classify_project_add_language zig "build.zig"
  if __cog_classify_project_has_file package.json && [[ $(__cog_classify_project_count_named_files '*.svelte') -gt 0 ]]; then
    __cog_classify_project_add_language svelte "package.json plus *.svelte"
  fi

  # Prevalence-based languages are measured against code files, not all files,
  # so a doc-heavy code repo is not diluted by its markdown into `languages: []`.
  # Bash is reported when a bin/ shell entrypoint exists, or shell scripts are the
  # plurality of code *and* a meaningful share of the tree — so a handful of
  # incidental scripts in a content vault never makes it "a bash project".
  local code_files content_files shell_files
  code_files="$(__cog_classify_project_count_code_files)"
  content_files="$(__cog_classify_project_count_content_files)"
  shell_files="$(__cog_classify_project_count_ext sh bash bats)"
  if [[ $shell_files -gt 0 ]] \
    && { __cog_classify_project_has_shell_entrypoint \
      || { [[ $((shell_files * 2)) -gt $code_files ]] && [[ $((shell_files * 5)) -ge $content_files ]]; }; }; then
    __cog_classify_project_add_language bash "bin/ shell entrypoint or shell scripts dominate code"
  fi
  [[ $(__cog_classify_project_count_named_files '*.R') -gt 0 ]] && __cog_classify_project_add_language r "*.R"
  [[ $(__cog_classify_project_count_named_files '*.lua') -gt 0 ]] && __cog_classify_project_add_language lua "*.lua"

  # Nix is reported only when its sources are the plurality of code files. A lone
  # flake.nix in a non-Nix repo (the per-project devShell standard) must not tag
  # the repo as Nix; a flake-defining repo (mostly *.nix) is a Nix project.
  local nix_files
  nix_files="$(__cog_classify_project_count_named_files '*.nix')"
  [[ $nix_files -gt 0 && $((nix_files * 2)) -gt $code_files ]] \
    && __cog_classify_project_add_language nix "*.nix dominate code"

  # Markdown is a content signal, not a code language: it is reported only when
  # markdown dominates the whole tree.
  local total md_files
  total="$(__cog_classify_project_count_files)"
  md_files="$(__cog_classify_project_count_named_files '*.md')"
  if [[ $md_files -gt 0 && $total -gt 0 && $((md_files * 2)) -gt $total ]]; then
    __cog_classify_project_add_language markdown "majority *.md content"
  fi
  # Always succeed: this populates LANGUAGES via optional probes, and the trailing
  # `[[ … ]] && …` would otherwise leak exit 1 and abort build_json under `set -e`.
  return 0
}

__cog_classify_project_detect_cli() {
  # Manifest-anchored CLI signals are authoritative regardless of file mix.
  if __cog_classify_project_file_contains Cargo.toml '^\[\[bin\]\]'; then
    CLI_SIGNALS+=("Cargo.toml with [[bin]] section")
  fi
  if __cog_classify_project_file_contains Cargo.toml '(^|[[:space:]])clap([[:space:]]*=|[[:space:]])' \
    || __cog_classify_project_file_contains Cargo.toml '^\[(workspace\.)?(dev-|build-)?dependencies\.clap\]'; then
    CLI_SIGNALS+=("clap dependency")
    __cog_classify_project_add_framework clap rust "clap in Cargo.toml deps"
  fi

  # Framework/import scans run only across a language's own sources and manifests
  # — never across prose — and only when that language is actually detected, so a
  # doc that merely mentions "click"/"cobra" can never invent a framework.
  if __cog_classify_project_has_language python; then
    if __cog_classify_project_file_contains pyproject.toml '^\[project\.scripts\]' \
      || __cog_classify_project_scan 'console_scripts' '*.py' 'setup.py' 'setup.cfg' 'pyproject.toml'; then
      CLI_SIGNALS+=("Python project scripts or console_scripts")
    fi
    if __cog_classify_project_scan '(^|[^[:alnum:]_])typer([^[:alnum:]_]|$)' '*.py' 'pyproject.toml' 'setup.py' 'setup.cfg' 'requirements*.txt'; then
      CLI_SIGNALS+=("typer dependency/import")
      __cog_classify_project_add_framework typer python "typer dependency/import signal"
    fi
    if __cog_classify_project_scan '(^|[^[:alnum:]_])click([^[:alnum:]_]|$)' '*.py' 'pyproject.toml' 'setup.py' 'setup.cfg' 'requirements*.txt'; then
      CLI_SIGNALS+=("click dependency/import")
      __cog_classify_project_add_framework click python "click dependency/import signal"
    fi
  fi
  if __cog_classify_project_has_language go; then
    if __cog_classify_project_scan '(^|[^[:alnum:]_])cobra([^[:alnum:]_]|$)' '*.go' 'go.mod' 'go.sum'; then
      CLI_SIGNALS+=("cobra dependency/import")
      __cog_classify_project_add_framework cobra go "cobra dependency/import signal"
    fi
  fi
  if __cog_classify_project_has_language javascript; then
    if __cog_classify_project_scan '(^|[^[:alnum:]_])commander([^[:alnum:]_]|$)' '*.js' '*.ts' '*.jsx' '*.tsx' '*.mjs' '*.cjs' 'package.json'; then
      CLI_SIGNALS+=("commander dependency/import")
      __cog_classify_project_add_framework commander javascript "commander dependency/import signal"
    fi
    if __cog_classify_project_scan '(^|[^[:alnum:]_])yargs([^[:alnum:]_]|$)' '*.js' '*.ts' '*.jsx' '*.tsx' '*.mjs' '*.cjs' 'package.json'; then
      CLI_SIGNALS+=("yargs dependency/import")
      __cog_classify_project_add_framework yargs javascript "yargs dependency/import signal"
    fi
  fi

  # Soft signals — a bin/ or cli/ directory, or executable shebang scripts — only
  # count toward CLI when a real code language is present, so incidental tooling
  # scripts in a content repo do not masquerade as a CLI project.
  if __cog_classify_project_has_code_language; then
    __cog_classify_project_has_dir bin && CLI_SIGNALS+=("bin/ directory")
    __cog_classify_project_has_dir cli && CLI_SIGNALS+=("cli/ directory")
    if __cog_classify_project_find_files -perm /111 -print0 \
      | xargs -0 awk 'FNR == 1 && /^#!/ {found=1} END {exit found ? 0 : 1}' 2>/dev/null; then
      CLI_SIGNALS+=("executable shebang scripts")
    fi
  fi
  return 0
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

  local langs_json project_types_json
  langs_json="$(__cog_classify_project_json_object_array "${LANGUAGES[@]}")"

  # File-mix and manifest facts drive a deterministic, prose-immune verdict.
  local has_manifest=false has_code=false
  __cog_classify_project_has_build_manifest && has_manifest=true
  __cog_classify_project_has_code_language && has_code=true

  local is_cli=false
  [[ ${#CLI_SIGNALS[@]} -gt 0 ]] && is_cli=true

  local -a project_types=()
  [[ $is_cli == true ]] && project_types+=(cli)
  project_types_json="$(__cog_classify_project_json_string_array "${project_types[@]}")"

  # Confidence + ambiguity: deterministic when a manifest anchors the shape or one
  # content/code class clearly dominates; otherwise defer to the caller's judgment.
  local primary_type=null confidence=low ambiguous=true
  if [[ $has_manifest == true ]]; then
    confidence=high
    ambiguous=false
    if [[ $is_cli == true ]]; then primary_type='"cli"'; else primary_type='"library"'; fi
  elif [[ $is_cli == true ]]; then
    confidence=medium
    ambiguous=false
    primary_type='"cli"'
  elif [[ $has_code == true ]]; then
    confidence=medium
    ambiguous=false
    primary_type='"library"'
  fi

  jq -n \
    --arg git_root "$PROJECT_ROOT" \
    --argjson languages "$langs_json" \
    --argjson project_types "$project_types_json" \
    --argjson frameworks "$(__cog_classify_project_json_object_array "${FRAMEWORKS[@]}")" \
    --argjson cli_signals "$(__cog_classify_project_json_string_array "${CLI_SIGNALS[@]}")" \
    --argjson is_cli "$is_cli" \
    --argjson is_monorepo "$(__cog_classify_project_monorepo)" \
    --argjson primary_type "$primary_type" \
    --arg confidence "$confidence" \
    --argjson ambiguous "$ambiguous" \
    '{git_root: $git_root, languages: $languages, project_types: $project_types, frameworks: $frameworks,
      cli_signals: $cli_signals, is_cli: $is_cli, is_monorepo: $is_monorepo,
      primary_type: $primary_type, confidence: $confidence, ambiguous: $ambiguous}'
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
