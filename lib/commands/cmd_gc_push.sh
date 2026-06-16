# shellcheck shell=bash
: 'desc: Run git push without force support.'

__cog_gc_push_self_check='.ok != null and (.repo_root | type == "string") and (.log | type == "string") and (.exit_code | type == "number") and (.failure_class == null or (.failure_class | type == "string"))'

__cog_gc_push_usage() {
  cog::fn::ui_data "Usage: cog gc-push (<out.json>|--json)"
}

__cog_gc_push_log_dir() {
  printf '%s/cog/skill-runs\n' "${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}"
}

__cog_gc_push_new_log_file() {
  local dir="$1"
  local n=1
  mkdir -p "$dir" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create git push log directory" "path: ${dir}" "" "check permissions"
  while [[ -e $dir/push-$$-$n.log ]]; do
    n=$((n + 1))
  done
  printf '%s/push-%s-%s.log\n' "$dir" "$$" "$n"
}

__cog_gc_push_build_json() {
  local root sha log_file ok exit_code classification failure_class="" reason=""
  root="$(cog::fn::git_root)"
  sha="$(git rev-parse --short HEAD 2>/dev/null || true)"
  log_file="$(__cog_gc_push_new_log_file "$(__cog_gc_push_log_dir)")"

  if git push >"$log_file" 2>&1; then
    ok=true
    exit_code=0
  else
    ok=false
    exit_code=1
    classification="$(cog::fn::git_classify_failure_log "$log_file")"
    failure_class="$(jq -r '.class' <<<"$classification")"
    reason="$(jq -r '.reason' <<<"$classification")"
  fi

  jq -n \
    --argjson ok "$ok" \
    --arg repo_root "$root" \
    --arg sha "$sha" \
    --arg log "$log_file" \
    --argjson exit_code "$exit_code" \
    --arg failure_class "$failure_class" \
    --arg reason "$reason" \
    '{
      ok: $ok,
      repo_root: $repo_root,
      sha: (if $sha == "" then null else $sha end),
      log: $log,
      exit_code: $exit_code,
      failure_class: (if $ok then null else $failure_class end),
      reason: (if $ok then null else $reason end)
    }'
}

cog::cmd::gc_push() {
  local mode="" out="" json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gc_push_usage
        return 0
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate gc-push output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown gc-push option" "option: $1" "" "run 'cog gc-push --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many gc-push output paths" "argument: $1" "" "run 'cog gc-push --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing gc-push output mode" "usage: cog gc-push (<out.json>|--json)" "" "run 'cog gc-push --help'"

  json="$(__cog_gc_push_build_json)"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_gc_push_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_gc_push_self_check" "$json"
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
