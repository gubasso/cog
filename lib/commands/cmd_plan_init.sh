# shellcheck shell=bash
: 'desc: Bootstrap implementation plan root files.'

__cog_plan_init_self_check='(.ok|type=="boolean") and (.repo_root|type=="string") and (.plan_root|type=="string") and (.plans_dir|type=="string") and (.queue_path|type=="string") and (.created|type=="array") and (.existing|type=="array") and (.legacy_plan_dir|type=="boolean")'

__cog_plan_init_usage() {
  cog::fn::ui_data "Usage: cog plan-init [--repo-root <dir>] (<out.json>|--json)"
}

__cog_plan_init_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

__cog_plan_init_write_root_readme() {
  local readme="$1"
  {
    printf '%s\n' "# Implementation Plans"
    printf '\n'
    printf '%s\n' "This directory stores implementation plans generated for staged agent execution."
    printf '\n'
    # shellcheck disable=SC2016 # Literal Markdown backticks, not command substitutions.
    printf '%s\n' '`queue-plans.yaml` is the source of truth for plan status, order, dependencies, and execution prompts.'
    # shellcheck disable=SC2016 # Literal Markdown backticks, not command substitutions.
    printf '%s\n' 'Plans live under `plans/`; every plan is a directory containing'
    # shellcheck disable=SC2016 # Literal Markdown backticks, not command substitutions.
    printf '%s\n' 'round files and an inner `queue-rounds.yaml`.'
    printf '\n'
    printf '%s\n' "Execute one round at a time. Status lives in YAML; files and directories do not move between states."
  } >"$readme" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write implementation plans README" "path: ${readme}" "" "check permissions"
}

__cog_plan_init_build_json() {
  local repo_root="$1" ok=true reason="" legacy=false
  local plan_root plans_dir root_readme root_queue
  local -a created=() existing=()
  plan_root="${repo_root}/.implementation-plans"
  plans_dir="${plan_root}/plans"
  root_readme="${plan_root}/README.md"
  root_queue="${plan_root}/queue-plans.yaml"

  if [[ ! -d $repo_root ]]; then
    ok=false
    reason="repo root is not a directory"
  else
    [[ -d ${repo_root}/.plan ]] && legacy=true
    if [[ -d $plan_root ]]; then
      existing+=("$plan_root")
    else
      mkdir -p "$plan_root" || cog::fn::error_raise "TempDirCreateFailed" \
        "could not create plan root" "path: ${plan_root}" "" "check permissions"
      created+=("$plan_root")
    fi

    if [[ -d $plans_dir ]]; then
      existing+=("$plans_dir")
    else
      mkdir -p "$plans_dir" || cog::fn::error_raise "TempDirCreateFailed" \
        "could not create plans dir" "path: ${plans_dir}" "" "check permissions"
      created+=("$plans_dir")
    fi

    # Plan directories must be flat siblings under plans/; fail closed on any nested plan.
    cog::fn::plans_revision_assert_flat "$repo_root"

    if [[ -e $root_readme ]]; then
      existing+=("$root_readme")
    else
      __cog_plan_init_write_root_readme "$root_readme"
      created+=("$root_readme")
    fi

    [[ -e $root_queue ]] && existing+=("$root_queue")
    cog::fn::queue_bootstrap_file "$root_queue" plans
    cog::fn::queue_validate_file "$root_queue" plans
    [[ " ${existing[*]} " == *" $root_queue "* ]] || created+=("$root_queue")
  fi

  jq -n \
    --argjson ok "$ok" \
    --arg repo_root "$repo_root" \
    --arg plan_root "$plan_root" \
    --arg plans_dir "$plans_dir" \
    --arg queue_path "$root_queue" \
    --argjson created "$(__cog_plan_init_json_array "${created[@]}")" \
    --argjson existing "$(__cog_plan_init_json_array "${existing[@]}")" \
    --argjson legacy_plan_dir "$legacy" \
    --arg reason "$reason" \
    '{ok: $ok, repo_root: $repo_root, plan_root: $plan_root, plans_dir: $plans_dir,
      queue_path: $queue_path, created: $created, existing: $existing,
      legacy_plan_dir: $legacy_plan_dir, reason: (if $ok then null else $reason end)}'
}

cog::cmd::plan_init() {
  local repo_root="" mode="" out="" json
  repo_root="$(pwd -P)"

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_init_usage
        return 0
        ;;
      --repo-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing repo root" "option: --repo-root" "" "run 'cog plan-init --help'"
        repo_root="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate plan-init output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown plan-init option" "option: $1" "" "run 'cog plan-init --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many plan-init output paths" "argument: $1" "" "run 'cog plan-init --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan-init output mode" "usage: cog plan-init [--repo-root <dir>] (<out.json>|--json)" "" \
    "run 'cog plan-init --help'"
  [[ -n $mode ]] || mode=json

  json="$(__cog_plan_init_build_json "$repo_root")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plan_init_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_plan_init_self_check" "$json"
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
