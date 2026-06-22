# shellcheck shell=bash
: 'desc: Detect review technologies and bundled reference targets.'

__cog_review_tech_scope_self_check='
(.repo_root | type == "string") and
(.detected_technologies | type == "array") and
(.is_cli | type == "boolean") and
(.available_refs | type == "array") and
(.research_targets | type == "array")
'

__cog_review_tech_scope_usage() {
  cog::fn::ui_data "Usage: cog review-tech-scope --scope <scope.json> [--classification <classification.json>] (<out.json>|--json)"
}

__cog_review_tech_scope_add_tech() {
  local kind="$1" name="$2" confidence="$3" evidence="$4"
  REVIEW_TECHS+=("$(jq -cn --arg kind "$kind" --arg name "$name" --arg confidence "$confidence" --arg evidence "$evidence" \
    '{kind: $kind, name: $name, confidence: $confidence, evidence: [$evidence]}')")
}

__cog_review_tech_scope_lang_for_path() {
  case "$1" in
    *.bash | *.sh) printf '%s\n' bash ;;
    *.py) printf '%s\n' python ;;
    *.js | *.jsx | *.ts | *.tsx) printf '%s\n' javascript ;;
    *.go) printf '%s\n' go ;;
    *.rs) printf '%s\n' rust ;;
    *.c | *.h) printf '%s\n' c ;;
    *.css | *.scss | *.sass | *.less) printf '%s\n' css ;;
    *.lua) printf '%s\n' lua ;;
    *.R | *.r) printf '%s\n' r ;;
    *.svelte) printf '%s\n' svelte ;;
    *.zig) printf '%s\n' zig ;;
    *) return 1 ;;
  esac
}

__cog_review_tech_scope_detect_file() {
  local repo_root="$1" rel="$2" path lang first
  path="${repo_root}/${rel}"
  if lang="$(__cog_review_tech_scope_lang_for_path "$rel")"; then
    __cog_review_tech_scope_add_tech language "$lang" high "${rel} extension"
  fi
  [[ -r $path && -f $path ]] || return 0
  IFS= read -r first <"$path" || first=""
  case "$first" in
    '#!'*bash* | '#!'*sh)
      __cog_review_tech_scope_add_tech language bash high "${rel} shebang"
      __cog_review_tech_scope_add_tech tool cli medium "${rel} executable script"
      ;;
    '#!'*python*)
      __cog_review_tech_scope_add_tech language python high "${rel} shebang"
      __cog_review_tech_scope_add_tech tool cli medium "${rel} executable script"
      ;;
    '#!'*node*)
      __cog_review_tech_scope_add_tech language javascript high "${rel} shebang"
      __cog_review_tech_scope_add_tech tool cli medium "${rel} executable script"
      ;;
  esac
  if [[ -x $path && $first == '#!'* ]]; then
    __cog_review_tech_scope_add_tech tool cli medium "${rel} executable shebang"
  fi
}

__cog_review_tech_scope_file_contains() {
  local repo_root="$1" rel="$2" pattern="$3"
  [[ -r ${repo_root}/${rel} && -f ${repo_root}/${rel} ]] || return 1
  grep -Eq "$pattern" "${repo_root}/${rel}" 2>/dev/null
}

__cog_review_tech_scope_detect_manifests() {
  local repo_root="$1"
  [[ -f ${repo_root}/package.json ]] && __cog_review_tech_scope_add_tech manifest package-json medium "package.json"
  [[ -f ${repo_root}/pyproject.toml ]] && __cog_review_tech_scope_add_tech manifest pyproject medium "pyproject.toml"
  [[ -f ${repo_root}/Cargo.toml ]] && __cog_review_tech_scope_add_tech manifest cargo medium "Cargo.toml"
  [[ -f ${repo_root}/go.mod ]] && __cog_review_tech_scope_add_tech manifest go-mod medium "go.mod"
  [[ -f ${repo_root}/build.zig ]] && __cog_review_tech_scope_add_tech manifest build-zig medium "build.zig"
  [[ -d ${repo_root}/bin || -d ${repo_root}/cli ]] && __cog_review_tech_scope_add_tech tool cli medium "bin/ or cli/ directory"

  if [[ -f ${repo_root}/Cargo.toml ]] && grep -Eq '(^|[[:space:]])clap([[:space:]]*=|[[:space:]])|^\[(workspace\.)?(dev-|build-)?dependencies\.clap\]' "${repo_root}/Cargo.toml"; then
    __cog_review_tech_scope_add_tech framework clap high "Cargo.toml"
    __cog_review_tech_scope_add_tech tool cli high "clap dependency"
  fi
  if [[ -f ${repo_root}/pyproject.toml ]] && grep -Eq '^\[project\.scripts\]|click|typer' "${repo_root}/pyproject.toml"; then
    __cog_review_tech_scope_add_tech tool cli high "pyproject.toml"
  fi
  if [[ -f ${repo_root}/package.json ]] && grep -Eq 'commander|yargs' "${repo_root}/package.json"; then
    __cog_review_tech_scope_add_tech tool cli high "package.json CLI dependency"
  fi
  return 0
}

__cog_review_tech_scope_detect_imports() {
  local repo_root="$1" rel="$2"
  __cog_review_tech_scope_file_contains "$repo_root" "$rel" '(^|[^[:alnum:]_])click([^[:alnum:]_]|$)' \
    && {
      __cog_review_tech_scope_add_tech framework click medium "${rel} import"
      __cog_review_tech_scope_add_tech tool cli medium "${rel} click import"
    }
  __cog_review_tech_scope_file_contains "$repo_root" "$rel" '(^|[^[:alnum:]_])typer([^[:alnum:]_]|$)' \
    && {
      __cog_review_tech_scope_add_tech framework typer medium "${rel} import"
      __cog_review_tech_scope_add_tech tool cli medium "${rel} typer import"
    }
  __cog_review_tech_scope_file_contains "$repo_root" "$rel" '(^|[^[:alnum:]_])cobra([^[:alnum:]_]|$)' \
    && {
      __cog_review_tech_scope_add_tech framework cobra medium "${rel} import"
      __cog_review_tech_scope_add_tech tool cli medium "${rel} cobra import"
    }
  __cog_review_tech_scope_file_contains "$repo_root" "$rel" '(^|[^[:alnum:]_])commander([^[:alnum:]_]|$)' \
    && {
      __cog_review_tech_scope_add_tech framework commander medium "${rel} import"
      __cog_review_tech_scope_add_tech tool cli medium "${rel} commander import"
    }
  __cog_review_tech_scope_file_contains "$repo_root" "$rel" '(^|[^[:alnum:]_])yargs([^[:alnum:]_]|$)' \
    && {
      __cog_review_tech_scope_add_tech framework yargs medium "${rel} import"
      __cog_review_tech_scope_add_tech tool cli medium "${rel} yargs import"
    }
  return 0
}

__cog_review_tech_scope_refs_json() {
  local techs_json="$1" is_cli="$2" rel lang
  {
    cog::fn::skill_refs_path "code-review/AGENTS.md" >/dev/null 2>&1 && printf '%s\n' "code-review/AGENTS.md"
    if [[ $is_cli == true ]] && cog::fn::skill_refs_path "cli-design/AGENTS.md" >/dev/null 2>&1; then
      printf '%s\n' "cli-design/AGENTS.md"
    fi
    while IFS= read -r lang; do
      [[ -n $lang ]] || continue
      rel="code-review/languages/${lang}/code-review-guide.md"
      cog::fn::skill_refs_path "$rel" >/dev/null 2>&1 && printf '%s\n' "$rel"
    done < <(jq -r '.[] | select(.kind == "language") | .name' <<<"$techs_json")
  } | sort -u | jq -R . | jq -s .
}

__cog_review_tech_scope_research_targets_json() {
  local techs_json="$1" refs_json="$2"
  jq -cn --argjson techs "$techs_json" --argjson refs "$refs_json" '
    def has_lang_ref($name): $refs | index("code-review/languages/" + $name + "/code-review-guide.md");
    $techs
    | map(select((.kind == "language" and (has_lang_ref(.name) | not)) or (.kind == "framework")))
    | unique_by(.kind, .name)
    | map({kind, name, evidence, reason: "no bundled guide"})
  '
}

__cog_review_tech_scope_build_json() {
  local scope_file="$1" classification_file="$2" scope repo_root rel techs is_cli refs research classification
  [[ -r $scope_file ]] || cog::fn::error_raise "InputUnreadable" \
    "scope file is not readable" "path: ${scope_file}" "" "check the file path"
  scope="$(jq -c . "$scope_file" 2>/dev/null)" || cog::fn::error_raise "InvalidJsonInput" \
    "scope file is not valid JSON" "path: ${scope_file}" "" "check the file contents"
  jq -e '(.repo_root | type == "string") and (.changed_files | type == "array") and (.status_files | type == "array")' <<<"$scope" >/dev/null \
    || cog::fn::error_raise "InvalidJsonInput" "scope file has invalid shape" "path: ${scope_file}" "" "run cog review-scope"
  repo_root="$(jq -r '.repo_root' <<<"$scope")"
  REVIEW_TECHS=()

  while IFS= read -r rel; do
    [[ -n $rel ]] || continue
    __cog_review_tech_scope_detect_file "$repo_root" "$rel"
    __cog_review_tech_scope_detect_imports "$repo_root" "$rel"
  done < <(jq -r '.changed_files[]' <<<"$scope")
  __cog_review_tech_scope_detect_manifests "$repo_root"

  if [[ -n $classification_file ]]; then
    [[ -r $classification_file ]] || cog::fn::error_raise "InputUnreadable" \
      "classification file is not readable" "path: ${classification_file}" "" "check the file path"
    classification="$(jq -c . "$classification_file" 2>/dev/null)" || cog::fn::error_raise "InvalidJsonInput" \
      "classification file is not valid JSON" "path: ${classification_file}" "" "check the file contents"
    while IFS= read -r rel; do
      [[ -n $rel ]] && __cog_review_tech_scope_add_tech language "$rel" low "classification supplemental"
    done < <(jq -r '(.languages // [])[]? | .lang // empty' <<<"$classification")
    [[ $(jq -r 'if .is_cli == true then "true" else "false" end' <<<"$classification") == true ]] \
      && __cog_review_tech_scope_add_tech tool cli low "classification supplemental"
  fi

  techs="$(printf '%s\n' "${REVIEW_TECHS[@]}" | jq -s '
    group_by(.kind, .name)
    | map({
        kind: .[0].kind,
        name: .[0].name,
        evidence: ([.[].evidence[]] | unique),
        confidence: (if any(.[]; .confidence == "high") then "high"
          elif any(.[]; .confidence == "medium") then "medium" else "low" end)
      })
    | sort_by(.kind, .name)
  ')"
  is_cli="$(jq -r 'any(.[]; .kind == "tool" and .name == "cli")' <<<"$techs")"
  refs="$(__cog_review_tech_scope_refs_json "$techs" "$is_cli")"
  research="$(__cog_review_tech_scope_research_targets_json "$techs" "$refs")"
  jq -n --arg repo_root "$repo_root" --argjson techs "$techs" --argjson is_cli "$is_cli" --argjson refs "$refs" --argjson research "$research" \
    '{repo_root: $repo_root, detected_technologies: $techs, is_cli: $is_cli,
      available_refs: $refs, research_targets: $research}'
}

cog::cmd::review_tech_scope() {
  local scope="" classification="" mode="" out="" json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_tech_scope_usage
        return 0
        ;;
      --scope)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing scope file" "option: --scope" "" "run 'cog review-tech-scope --help'"
        scope="$2"
        shift 2
        ;;
      --classification)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing classification file" "option: --classification" "" "run 'cog review-tech-scope --help'"
        classification="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate review-tech-scope output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-tech-scope option" "option: $1" "" "run 'cog review-tech-scope --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many review-tech-scope output paths" "argument: $1" "" "run 'cog review-tech-scope --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $scope && -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing review-tech-scope argument" \
    "usage: cog review-tech-scope --scope <scope.json> (<out.json>|--json)" "" \
    "run 'cog review-tech-scope --help'"

  json="$(__cog_review_tech_scope_build_json "$scope" "$classification")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_tech_scope_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_review_tech_scope_self_check" "$json"
  fi
}
