# shellcheck shell=bash
: 'desc: List suckless patch conflict artifacts.'

__cog_suckless_conflicts_self_check='(.ok|type=="boolean") and (.rejects|type=="array") and (.orig_files|type=="array") and (.count|type=="number")'

__cog_suckless_conflicts_usage() {
  cog::fn::ui_data "Usage: cog suckless-conflicts (<out.json>|--json)"
}

__cog_suckless_conflicts_json_string_array() {
  if (($# == 0)); then
    jq -cn '[]'
    return 0
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
  return 0
}

__cog_suckless_conflicts_json_object_array() {
  if (($# == 0)); then
    jq -cn '[]'
    return 0
  fi
  printf '%s\n' "$@" | jq -s .
  return 0
}

__cog_suckless_conflicts_relative_to_root() {
  local root="$1" path="$2"
  printf '%s\n' "${path#"$root"/}"
  return 0
}

__cog_suckless_conflicts_build_json() {
  local repo_root rel target lines file
  local -a rejects=()
  local -a orig_files=()

  __have git || cog::fn::error_raise "MissingRequirement" "required command not found" "command: git" "" "install git and retry"
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n $repo_root ]] || cog::fn::error_raise "InputNotFound" "not a git work tree" "command: git rev-parse --show-toplevel" "" "run from inside a git work tree"

  while IFS= read -r file || [[ -n $file ]]; do
    [[ -n $file ]] || continue
    rel="$(__cog_suckless_conflicts_relative_to_root "$repo_root" "$file")"
    target="${rel%.rej}"
    lines="$(awk 'END {print NR}' "$file")"
    rejects+=("$(jq -cn \
      --arg path "$rel" \
      --arg target "$target" \
      --argjson lines "$lines" \
      '{path: $path, target: $target, lines: $lines}')")
  done < <(find "$repo_root" -path "$repo_root/.git" -prune -o -type f -name '*.rej' -print | LC_ALL=C sort)

  while IFS= read -r file || [[ -n $file ]]; do
    [[ -n $file ]] || continue
    orig_files+=("$(__cog_suckless_conflicts_relative_to_root "$repo_root" "$file")")
  done < <(find "$repo_root" -path "$repo_root/.git" -prune -o -type f -name '*.orig' -print | LC_ALL=C sort)

  jq -n \
    --argjson ok true \
    --arg repo_root "$repo_root" \
    --argjson rejects "$(__cog_suckless_conflicts_json_object_array "${rejects[@]}")" \
    --argjson orig_files "$(__cog_suckless_conflicts_json_string_array "${orig_files[@]}")" \
    '{
      ok: $ok,
      repo_root: $repo_root,
      rejects: $rejects,
      orig_files: $orig_files,
      count: ($rejects | length)
    }'
  return 0
}

cog::cmd::suckless_conflicts() {
  local mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_suckless_conflicts_usage
        return 0
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate suckless-conflicts output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown suckless-conflicts option" "option: $1" "" "run 'cog suckless-conflicts --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many suckless-conflicts output paths" "argument: $1" "" "run 'cog suckless-conflicts --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing suckless-conflicts output mode" "usage: cog suckless-conflicts (<out.json>|--json)" "" "run 'cog suckless-conflicts --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_suckless_conflicts_build_json)"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_suckless_conflicts_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_suckless_conflicts_self_check" "$json"; fi
}
