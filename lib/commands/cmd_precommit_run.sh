# shellcheck shell=bash
: 'desc: Run pre-commit hooks across stages and collect failures.'

__cog_precommit_run_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.installed|type=="boolean") and (.stages|type=="array") and (.failed_hooks|type=="array") and (.log|type=="string")'

__cog_precommit_run_usage() {
  cog::fn::ui_data "Usage: cog precommit-run [--project-root <dir>] [-s|--stage <stage>]... [--log <file>] (<out.json>|--json)"
}

# Known git hook types pre-commit can install a stage into. A stage outside this
# set (e.g. manual) is still runnable but is not a git hook, so it is never
# installed.
__cog_precommit_run_is_hook_type() {
  case "$1" in
    pre-commit | pre-push | commit-msg | prepare-commit-msg | post-commit | \
      post-checkout | post-merge | post-rewrite | pre-merge-commit | pre-rebase) return 0 ;;
    *) return 1 ;;
  esac
}

# Emit one stage per line: the explicit --stage list when given, else the union
# of default_stages and per-hook stages from the config, minus the manual stage,
# falling back to pre-commit when nothing else is configured.
__cog_precommit_run_resolve_stages() {
  local config="$1"
  shift
  local -a requested=("$@")
  if [[ ${#requested[@]} -gt 0 ]]; then
    printf '%s\n' "${requested[@]}"
    return 0
  fi
  local -a stages=()
  if [[ -f $config ]] && __have yq; then
    mapfile -t stages < <(yq '[(.default_stages // [])[], (.repos // [])[].hooks[]?.stages[]?] | unique | .[]' "$config" 2>/dev/null | grep -v '^manual$')
  fi
  [[ ${#stages[@]} -gt 0 ]] || stages=("pre-commit")
  printf '%s\n' "${stages[@]}"
}

# Cheap check for whether pre-commit's git hook scripts are already installed.
__cog_precommit_run_hooks_installed() {
  local project_root="$1" hook_path
  hook_path="$(cd "$project_root" 2>/dev/null && git rev-parse --git-path hooks/pre-commit 2>/dev/null)" || return 1
  [[ -n $hook_path ]] || return 1
  [[ $hook_path == /* ]] || hook_path="$project_root/$hook_path"
  [[ -f $hook_path ]] && grep -q 'pre-commit' "$hook_path"
}

# Ensure pre-commit hook scripts exist; install the hook types matching the
# resolved stages when missing. Echoes true when installed (already or now),
# false when the install failed.
__cog_precommit_run_ensure_installed() {
  local project_root="$1"
  shift
  if __cog_precommit_run_hooks_installed "$project_root"; then
    printf 'true\n'
    return 0
  fi
  local stage
  local -a install_args=()
  for stage in "$@"; do
    __cog_precommit_run_is_hook_type "$stage" && install_args+=(-t "$stage")
  done
  [[ ${#install_args[@]} -gt 0 ]] || install_args=(-t pre-commit)
  if (cd "$project_root" && pre-commit install "${install_args[@]}") >/dev/null 2>&1; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

__cog_precommit_run_string_array() {
  [[ $# -gt 0 ]] || {
    printf '[]\n'
    return 0
  }
  printf '%s\n' "$@" | jq -R . | jq -cs .
}

__cog_precommit_run_build_json() {
  local project_root="$1" log="$2"
  shift 2
  local -a requested=("$@")

  local ok=true installed=false reason="" config="$project_root/.pre-commit-config.yaml"
  local -a stages=()
  local failed_hooks='[]' classification='null'

  : >"$log"

  if [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  elif ! (cd "$project_root" && git rev-parse --git-dir >/dev/null 2>&1); then
    ok=false
    reason="not a git repository"
  elif [[ ! -f $config ]]; then
    ok=false
    reason="no .pre-commit-config.yaml (run bootstrap-precommit first)"
  fi

  if [[ $ok == true ]]; then
    mapfile -t stages < <(__cog_precommit_run_resolve_stages "$config" "${requested[@]}")
    installed="$(__cog_precommit_run_ensure_installed "$project_root" "${stages[@]}")"

    local stage status=0
    for stage in "${stages[@]}"; do
      printf '=== pre-commit --hook-stage %s ===\n' "$stage" >>"$log"
      (cd "$project_root" && pre-commit run --all-files --hook-stage "$stage") >>"$log" 2>&1 || status=1
    done
    if [[ $status -ne 0 ]]; then
      ok=false
      reason="pre-commit hooks failed"
      failed_hooks="$(cog::fn::git_loop_signatures "$log")"
      classification="$(cog::fn::git_classify_failure_log "$log")"
    fi
  fi

  jq -n \
    --argjson ok "$ok" \
    --arg project_root "$project_root" \
    --argjson installed "$installed" \
    --argjson stages "$(__cog_precommit_run_string_array "${stages[@]}")" \
    --argjson failed_hooks "$failed_hooks" \
    --argjson classification "$classification" \
    --arg log "$log" \
    --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, installed: $installed, stages: $stages,
      failed_hooks: $failed_hooks, classification: $classification, log: $log,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::precommit_run() {
  __have pre-commit || cog::fn::error_raise "MissingRequirement" \
    "required command not found" "command: pre-commit" "" "install pre-commit (https://pre-commit.com) and retry"

  local project_root mode="" out="" log="" json
  local -a stages=()
  project_root="$(pwd -P)"

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_precommit_run_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog precommit-run --help'"
        project_root="$2"
        shift 2
        ;;
      -s | --stage)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing stage" "option: $1" "" "run 'cog precommit-run --help'"
        stages+=("$2")
        shift 2
        ;;
      --log)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing log path" "option: --log" "" "run 'cog precommit-run --help'"
        log="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate precommit-run output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown precommit-run option" "option: $1" "" "run 'cog precommit-run --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many precommit-run output paths" "argument: $1" "" "run 'cog precommit-run --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing precommit-run output mode" "usage: cog precommit-run ... (<out.json>|--json)" "" "run 'cog precommit-run --help'"
  [[ -n $mode ]] || mode=json
  [[ -n $log ]] || log="$(mktemp "${TMPDIR:-/tmp}/cog-precommit-run.XXXXXX")"

  json="$(__cog_precommit_run_build_json "$project_root" "$log" "${stages[@]}")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_precommit_run_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_precommit_run_self_check" "$json"
  fi

  jq -e '.ok == true' <<<"$json" >/dev/null
}
