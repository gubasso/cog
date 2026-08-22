# shellcheck shell=bash
: 'desc: Create a review run directory and resolve output paths.'

__cog_review_init_usage() {
  cog::fn::ui_data "Usage: cog review-init <prefix> [--json]"
}

__cog_review_init_paths_json() {
  local run_dir="$1"
  local paths_env="$2"
  jq -cn \
    --arg run_dir "$run_dir" \
    --arg paths_env "$paths_env" \
    --arg scope "${run_dir}/scope.json" \
    --arg tech_scope "${run_dir}/tech-scope.json" \
    --arg findings "${run_dir}/findings.json" \
    '{
      run_dir: $run_dir,
      paths_env: $paths_env,
      paths: {
        scope: $scope,
        tech_scope: $tech_scope,
        findings: $findings
      }
    }'
}

# Every name this fragment binds carries the REVIEW_ prefix. A sourceable
# fragment runs in the caller's shell, so an unprefixed generic name silently
# rebinds whatever the caller already holds under it: `RUN_DIR` here used to
# repoint the sourcing skill's own run directory at this review directory, and
# every consumer paid for it with a save-and-restore dance around the `.` line.
# Prefixing every name, rather than only the one that collided today, is what
# makes the rule checkable without judging which names are ambient.
__cog_review_init_write_paths_env() {
  local run_dir="$1"
  local paths_env="$2"

  {
    printf 'REVIEW_RUN_DIR=%q\n' "$run_dir"
    printf 'REVIEW_SCOPE_JSON=%q\n' "${run_dir}/scope.json"
    printf 'REVIEW_TECH_SCOPE_JSON=%q\n' "${run_dir}/tech-scope.json"
    printf 'REVIEW_FINDINGS_JSON=%q\n' "${run_dir}/findings.json"
  } >"$paths_env" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write review paths env" "path: ${paths_env}" "" "check run directory permissions"
}

cog::cmd::review_init() {
  local prefix="" json_mode="${COG_UI_JSON:-false}"
  local run_dir paths_env json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_init_usage
        return 0
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-init option" "option: $1" "" "run 'cog review-init --help'"
        ;;
      *)
        [[ -z $prefix ]] || cog::fn::error_raise "TooManyArguments" \
          "too many review-init prefixes" "argument: $1" "" "run 'cog review-init --help'"
        prefix="$1"
        shift
        ;;
    esac
  done

  [[ -n $prefix ]] || cog::fn::error_raise "MissingArgument" \
    "missing review-init prefix" "usage: cog review-init <prefix> [--json]" "" "run 'cog review-init --help'"

  run_dir="$(cog::fn::rundir_create "$prefix")"
  paths_env="${run_dir}/paths.env"
  __cog_review_init_write_paths_env "$run_dir" "$paths_env"

  if [[ $json_mode == true ]]; then
    json="$(__cog_review_init_paths_json "$run_dir" "$paths_env")"
    cog::fn::json_emit '(.run_dir | type == "string") and (.paths | type == "object")' "$json"
  else
    # Same vocabulary as paths.env: the command reports one set of names, so a
    # caller that parses these lines and a caller that sources the fragment
    # cannot end up holding the same directory under two different names.
    cog::fn::ui_data "REVIEW_RUN_DIR=${run_dir}"
    cog::fn::ui_data "REVIEW_SCOPE_JSON=${run_dir}/scope.json"
    cog::fn::ui_data "REVIEW_TECH_SCOPE_JSON=${run_dir}/tech-scope.json"
    cog::fn::ui_data "REVIEW_FINDINGS_JSON=${run_dir}/findings.json"
  fi
}
