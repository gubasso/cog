# shellcheck shell=bash
: 'desc: Detect the CI target from the project git remote.'

__cog_ci_detect_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.host|type=="string") and (.target|type=="string") and (.requires_question|type=="boolean") and (.existing_ci|type=="array")'

__cog_ci_detect_usage() {
  cog::fn::ui_data "Usage: cog ci-detect [--project-root <dir>] (<out.json>|--json)"
}

# Read the origin remote url from a git config INI file without invoking git.
__cog_ci_detect_origin_url() {
  local config_file="$1" line trimmed section="" url=""
  [[ -f $config_file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [[ $trimmed =~ ^\[(.+)\]$ ]]; then
      section="${BASH_REMATCH[1]}"
      continue
    fi
    if [[ $section == 'remote "origin"' && $trimmed =~ ^url[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      url="${BASH_REMATCH[1]}"
      url="${url%"${url##*[![:space:]]}"}"
      printf '%s' "$url"
      return 0
    fi
  done <"$config_file"
  printf '%s' "$url"
}

# Classify a remote url host as github, gitlab, other, or none (empty url).
__cog_ci_detect_host() {
  local url="$1" host lower
  [[ -n $url ]] || {
    printf 'none'
    return 0
  }
  host="${url#*://}"
  host="${host#*@}"
  host="${host%%[:/]*}"
  lower="${host,,}"
  case "$lower" in
    *github*) printf 'github' ;;
    *gitlab*) printf 'gitlab' ;;
    *) printf 'other' ;;
  esac
}

__cog_ci_detect_build_json() {
  local project_root="$1"
  local ok=true reason="" config_file="$project_root/.git/config"
  local remote_url="" host=none target=none requires_question=true existing=() f
  if [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  fi
  if [[ $ok == true ]]; then
    remote_url="$(__cog_ci_detect_origin_url "$config_file")"
    host="$(__cog_ci_detect_host "$remote_url")"
    case "$host" in
      github | gitlab)
        target="$host"
        requires_question=false
        ;;
      other)
        target=none
        requires_question=true
        reason="origin remote host is neither github nor gitlab; ask the operator for the CI target"
        ;;
      *)
        target=none
        requires_question=true
        reason="no origin remote found in .git/config; ask the operator for the CI target"
        ;;
    esac
    [[ -f $project_root/.gitlab-ci.yml ]] && existing+=(".gitlab-ci.yml")
    if [[ -d $project_root/.github/workflows ]]; then
      while IFS= read -r -d '' f; do
        existing+=(".github/workflows/${f##*/}")
      done < <(find "$project_root/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 2>/dev/null | sort -z)
    fi
  fi
  jq -n \
    --argjson ok "$ok" --arg project_root "$project_root" \
    --arg remote_url "$remote_url" --arg host "$host" --arg target "$target" \
    --argjson requires_question "$requires_question" \
    --argjson existing_ci "$(cog::fn::template::json_string_array "${existing[@]}")" \
    --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root,
      remote_url: (if $remote_url == "" then null else $remote_url end),
      host: $host, target: $target, requires_question: $requires_question,
      existing_ci: $existing_ci,
      reason: (if $reason == "" then null else $reason end)}'
}

cog::cmd::ci_detect() {
  local project_root mode="" out="" json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_ci_detect_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog ci-detect --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate ci-detect output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown ci-detect option" "option: $1" "" "run 'cog ci-detect --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many ci-detect output paths" "argument: $1" "" "run 'cog ci-detect --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing ci-detect output mode" "usage: cog ci-detect [flags] (<out.json>|--json)" "" "run 'cog ci-detect --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_ci_detect_build_json "$project_root")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_ci_detect_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_ci_detect_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
