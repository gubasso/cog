# shellcheck shell=bash
: 'desc: Check, apply, and build a suckless patch.'

__cog_suckless_apply_self_check='(.ok|type=="boolean") and (.patch|type=="string") and (.method|type=="string") and (.check|type=="object") and (.apply|type=="object") and (.build|type=="object") and (.needs_conflict_resolution|type=="boolean")'

__cog_suckless_apply_usage() {
  cog::fn::ui_data "Usage: cog suckless-apply --patch <file> (<out.json>|--json)"
}

__cog_suckless_apply_resolve_patch() {
  local input="$1"
  [[ -r $input && -f $input ]] || return 1
  if __have realpath; then
    realpath -e -- "$input"
  else
    readlink -f -- "$input"
  fi
  return 0
}

__cog_suckless_apply_phase_json() {
  local ok="$1" exit_code="$2" log_file="$3"
  jq -cn \
    --argjson ok "$ok" \
    --arg exit_code "$exit_code" \
    --arg log "$log_file" \
    '{
      ok: $ok,
      exit_code: (if $exit_code == "" then null else ($exit_code | tonumber) end),
      log: $log
    }'
  return 0
}

__cog_suckless_apply_bool_for_exit() {
  if [[ $1 == "0" ]]; then
    printf '%s\n' true
  else
    printf '%s\n' false
  fi
  return 0
}

__cog_suckless_apply_build_json() {
  local patch="$1"
  local repo_root log_dir check_log three_way_log apply_log build_log
  local check_exit three_way_exit apply_exit build_exit ok method needs_conflict_resolution reason
  local check_json three_way_json apply_json build_json

  patch="$(__cog_suckless_apply_resolve_patch "$patch")" || cog::fn::error_raise "InputUnreadable" "patch is not a readable file" "path: ${patch}" "" "check the patch path and retry"
  __have git || cog::fn::error_raise "MissingRequirement" "required command not found" "command: git" "" "install git and retry"
  __have make || cog::fn::error_raise "MissingRequirement" "required command not found" "command: make" "" "install make and retry"
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n $repo_root ]] || cog::fn::error_raise "InputNotFound" "not a git work tree" "command: git rev-parse --show-toplevel" "" "run from inside a git work tree"
  log_dir="$(mktemp -d "${TMPDIR:-/tmp}/cog-suckless-apply.XXXXXX")" || cog::fn::error_raise "TempDirCreateFailed" "could not create log directory" "operation: mktemp -d" "" "check TMPDIR and retry"
  check_log="$log_dir/check.log"
  three_way_log="$log_dir/three_way_check.log"
  apply_log="$log_dir/apply.log"
  build_log="$log_dir/build.log"
  : >"$three_way_log"
  : >"$apply_log"
  : >"$build_log"

  check_exit=0
  if git apply --check "$patch" >"$check_log" 2>&1; then
    method="git-apply"
    apply_exit=0
    if git apply "$patch" >"$apply_log" 2>&1; then
      :
    else
      apply_exit=$?
    fi
    three_way_exit=""
  else
    check_exit=$?
    three_way_exit=0
    if git apply --check --3way "$patch" >"$three_way_log" 2>&1; then
      method="git-apply-3way"
      apply_exit=0
      if git apply --3way "$patch" >"$apply_log" 2>&1; then
        :
      else
        apply_exit=$?
      fi
    else
      three_way_exit=$?
      method="none"
      apply_exit=""
    fi
  fi

  ok=false
  needs_conflict_resolution=true
  reason="patch needs conflict resolution"
  build_exit=""

  if [[ $method != "none" && ${apply_exit:-} == "0" ]]; then
    needs_conflict_resolution=false
    build_exit=0
    if make clean >"$build_log" 2>&1 && make >>"$build_log" 2>&1; then
      ok=true
      reason=""
    else
      build_exit=$?
      ok=false
      reason="build failed"
    fi
  elif [[ $method != "none" ]]; then
    needs_conflict_resolution=true
    reason="patch apply failed after passing check"
  fi

  check_json="$(__cog_suckless_apply_phase_json "$(__cog_suckless_apply_bool_for_exit "$check_exit")" "$check_exit" "$check_log")"
  if [[ -z ${three_way_exit:-} ]]; then
    three_way_json="$(__cog_suckless_apply_phase_json false "" "$three_way_log")"
  else
    three_way_json="$(__cog_suckless_apply_phase_json "$(__cog_suckless_apply_bool_for_exit "$three_way_exit")" "$three_way_exit" "$three_way_log")"
  fi
  if [[ -z ${apply_exit:-} ]]; then
    apply_json="$(__cog_suckless_apply_phase_json false "" "$apply_log")"
  else
    apply_json="$(__cog_suckless_apply_phase_json "$(__cog_suckless_apply_bool_for_exit "$apply_exit")" "$apply_exit" "$apply_log")"
  fi
  if [[ -z ${build_exit:-} ]]; then
    build_json="$(__cog_suckless_apply_phase_json false "" "$build_log")"
  else
    build_json="$(__cog_suckless_apply_phase_json "$(__cog_suckless_apply_bool_for_exit "$build_exit")" "$build_exit" "$build_log")"
  fi

  jq -n \
    --argjson ok "$ok" \
    --arg repo_root "$repo_root" \
    --arg patch "$patch" \
    --arg method "$method" \
    --argjson check "$check_json" \
    --argjson three_way_check "$three_way_json" \
    --argjson apply "$apply_json" \
    --argjson build "$build_json" \
    --argjson needs_conflict_resolution "$needs_conflict_resolution" \
    --arg reason "$reason" \
    '{
      ok: $ok,
      repo_root: $repo_root,
      patch: $patch,
      method: $method,
      check: $check,
      three_way_check: $three_way_check,
      apply: $apply,
      build: $build,
      needs_conflict_resolution: $needs_conflict_resolution,
      reason: (if $ok then null else $reason end)
    }'
  return 0
}

cog::cmd::suckless_apply() {
  local patch="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_suckless_apply_usage
        return 0
        ;;
      --patch)
        [[ $# -ge 2 && -z $patch ]] || cog::fn::error_raise "MissingArgument" "missing patch file" "option: --patch" "" "run 'cog suckless-apply --help'"
        patch="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate suckless-apply output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown suckless-apply option" "option: $1" "" "run 'cog suckless-apply --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many suckless-apply output paths" "argument: $1" "" "run 'cog suckless-apply --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $patch && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing suckless-apply argument" "usage: cog suckless-apply --patch <file> (<out.json>|--json)" "" "run 'cog suckless-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_suckless_apply_build_json "$patch")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_suckless_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_suckless_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
