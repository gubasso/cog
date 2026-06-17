# shellcheck shell=bash
: 'desc: Partition session files by owning repo and run safety scan.'

__cog_gc_plan_self_check='(.ok|type=="boolean") and (.repos|type=="array") and (.undeclared_dirty|type=="array") and (.declared_no_change|type=="array") and (.escapes|type=="array") and (.invalid_repos|type=="array") and (.surprises|type=="array")'

__cog_gc_plan_usage() {
  cog::fn::ui_data "Usage: cog gc-plan --session-files <file> [--repo <dir>]... [--repo-set <file>] (<out.json>|--json)"
}

__cog_gc_plan_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
    return 0
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
}

__cog_gc_plan_json_objects() {
  if (($# == 0)); then
    jq -cn '[]'
    return 0
  fi
  printf '%s\n' "$@" | jq -s .
}

__cog_gc_plan_read_session_paths() {
  local out_name="$1"
  local file="$2"
  local -n __out_ref="$out_name"
  local line
  __out_ref=()

  [[ -r $file ]] || cog::fn::error_raise "InputUnreadable" \
    "session files file is not readable" "path: ${file}" "" "check the file path"
  if od -An -tx1 "$file" | grep -q ' 00'; then
    cog::fn::error_raise "InvalidInput" \
      "session files file contains NUL bytes" "path: ${file}" "" "write newline-delimited paths"
  fi
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -n $line ]] || continue
    __out_ref+=("$line")
  done <"$file"
  ((${#__out_ref[@]} > 0)) || cog::fn::error_raise "InvalidInput" \
    "session files list is empty" "path: ${file}" "" "write at least one path"
  return 0
}

__cog_gc_plan_nearest_existing_dir() {
  local d="$1"
  while [[ -n $d && $d != "/" && ! -d $d ]]; do
    d="$(dirname -- "$d")"
  done
  printf '%s\n' "$d"
}

__cog_gc_plan_owning_root() {
  local abs="$1" d
  d="$(__cog_gc_plan_nearest_existing_dir "$(dirname -- "$abs")")"
  [[ -n $d ]] || return 1
  git -C "$d" rev-parse --show-toplevel 2>/dev/null
}

__cog_gc_plan_repo_changed_paths() {
  local root="$1" line payload
  git -C "$root" status --porcelain=v1 -uall 2>/dev/null | while IFS= read -r line; do
    [[ -n $line ]] || continue
    payload="${line:3}"
    [[ $payload == *" -> "* ]] && payload="${payload#* -> }"
    printf '%s\n' "$payload"
  done
}

__cog_gc_plan_in_list() {
  case $'\n'"$2"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

__cog_gc_plan_build_json() {
  local session_file="$1" repo_set_file="$2"
  shift 2
  local -a repo_flags=("$@")

  local -a session=()
  __cog_gc_plan_read_session_paths session "$session_file"

  local cwd_root explicit_allowlist=0
  cwd_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

  local -a declared_order=() explicit_declared=() invalid_repos=()
  local -A declared_set=() explicit_set=()
  local d r

  if [[ -n $cwd_root ]]; then
    declared_set["$cwd_root"]=1
    declared_order+=("$cwd_root")
  fi

  for d in "${repo_flags[@]}"; do
    explicit_allowlist=1
    if r="$(cog::fn::git_root_for "$d")" && [[ -n $r ]]; then
      if [[ -z ${declared_set[$r]:-} ]]; then
        declared_set["$r"]=1
        declared_order+=("$r")
      fi
      if [[ -z ${explicit_set[$r]:-} ]]; then
        explicit_set["$r"]=1
        explicit_declared+=("$r")
      fi
    else
      invalid_repos+=("$d")
    fi
  done

  if [[ -n $repo_set_file ]]; then
    explicit_allowlist=1
    [[ -r $repo_set_file ]] || cog::fn::error_raise "InputUnreadable" \
      "repo-set file is not readable" "path: ${repo_set_file}" "" "check the file path"
    while IFS= read -r d || [[ -n $d ]]; do
      [[ -n $d ]] || continue
      if r="$(cog::fn::git_root_for "$d")" && [[ -n $r ]]; then
        if [[ -z ${declared_set[$r]:-} ]]; then
          declared_set["$r"]=1
          declared_order+=("$r")
        fi
        if [[ -z ${explicit_set[$r]:-} ]]; then
          explicit_set["$r"]=1
          explicit_declared+=("$r")
        fi
      else
        invalid_repos+=("$d")
      fi
    done <"$repo_set_file"
  fi

  local -a owning_order=() escapes=()
  local -A root_paths=()
  local p abs root rel
  for p in "${session[@]}"; do
    abs="$(realpath -m -- "$p")"
    if ! root="$(__cog_gc_plan_owning_root "$abs")" || [[ -z $root ]]; then
      escapes+=("$abs")
      continue
    fi
    rel="$(realpath -m --relative-to="$root" -- "$abs")"
    if [[ -z ${root_paths[$root]:-} ]]; then
      owning_order+=("$root")
      root_paths["$root"]="$rel"
    elif ! __cog_gc_plan_in_list "$rel" "${root_paths[$root]}"; then
      root_paths["$root"]+=$'\n'"$rel"
    fi
  done

  local -a accepted=() undeclared=()
  local -A accepted_set=()
  for root in "${declared_order[@]}"; do
    if [[ -n ${root_paths[$root]:-} ]]; then
      accepted+=("$root")
      accepted_set["$root"]=1
    fi
  done
  for root in "${owning_order[@]}"; do
    [[ -n ${declared_set[$root]:-} ]] && continue
    if [[ $explicit_allowlist -eq 1 ]]; then
      undeclared+=("$root")
    elif [[ -z ${accepted_set[$root]:-} ]]; then
      accepted+=("$root")
      accepted_set["$root"]=1
    fi
  done

  local -a repo_objs=() rels=() changed=() extra=()
  local c
  for root in "${accepted[@]}"; do
    mapfile -t rels <<<"${root_paths[$root]}"
    changed=()
    extra=()
    mapfile -t changed < <(__cog_gc_plan_repo_changed_paths "$root")
    for c in "${changed[@]}"; do
      [[ -n $c ]] || continue
      __cog_gc_plan_in_list "$c" "${root_paths[$root]}" || extra+=("$c")
    done
    repo_objs+=("$(jq -cn --arg root "$root" \
      --argjson paths "$(__cog_gc_plan_json_array "${rels[@]}")" \
      --argjson extra_dirty "$(__cog_gc_plan_json_array "${extra[@]}")" \
      '{root: $root, paths: $paths, extra_dirty: $extra_dirty}')")
  done

  local -a undeclared_objs=()
  for root in "${undeclared[@]}"; do
    mapfile -t rels <<<"${root_paths[$root]}"
    undeclared_objs+=("$(jq -cn --arg root "$root" \
      --argjson paths "$(__cog_gc_plan_json_array "${rels[@]}")" \
      '{root: $root, paths: $paths}')")
  done

  local -a no_change=()
  for root in "${explicit_declared[@]}"; do
    [[ -n ${root_paths[$root]:-} ]] && continue
    [[ -z "$(git -C "$root" status --porcelain=v1 2>/dev/null)" ]] && no_change+=("$root")
  done

  local -a surprises=()
  local x
  for x in "${escapes[@]}"; do surprises+=("escape:$x"); done
  for x in "${undeclared[@]}"; do surprises+=("undeclared-repo:$x"); done
  for x in "${invalid_repos[@]}"; do surprises+=("invalid-repo:$x"); done

  local ok=true
  [[ ${#escapes[@]} -eq 0 ]] || ok=false

  jq -n \
    --argjson ok "$ok" \
    --argjson repos "$(__cog_gc_plan_json_objects "${repo_objs[@]}")" \
    --argjson undeclared_dirty "$(__cog_gc_plan_json_objects "${undeclared_objs[@]}")" \
    --argjson declared_no_change "$(__cog_gc_plan_json_array "${no_change[@]}")" \
    --argjson escapes "$(__cog_gc_plan_json_array "${escapes[@]}")" \
    --argjson invalid_repos "$(__cog_gc_plan_json_array "${invalid_repos[@]}")" \
    --argjson surprises "$(__cog_gc_plan_json_array "${surprises[@]}")" \
    '{
      ok: $ok,
      repos: $repos,
      undeclared_dirty: $undeclared_dirty,
      declared_no_change: $declared_no_change,
      escapes: $escapes,
      invalid_repos: $invalid_repos,
      surprises: $surprises
    }'
}

cog::cmd::gc_plan() {
  local session_file="" repo_set_file="" mode="" out="" json
  local -a repo_flags=()

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gc_plan_usage
        return 0
        ;;
      --session-files)
        [[ $# -ge 2 && -n ${2:-} && -z $session_file ]] || cog::fn::error_raise "MissingArgument" \
          "missing session files path" "option: --session-files" "" "run 'cog gc-plan --help'"
        session_file="$2"
        shift 2
        ;;
      --repo)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing repo path" "option: --repo" "" "run 'cog gc-plan --help'"
        repo_flags+=("$2")
        shift 2
        ;;
      --repo-set)
        [[ $# -ge 2 && -n ${2:-} && -z $repo_set_file ]] || cog::fn::error_raise "MissingArgument" \
          "missing repo-set path" "option: --repo-set" "" "run 'cog gc-plan --help'"
        repo_set_file="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate gc-plan output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown gc-plan option" "option: $1" "" "run 'cog gc-plan --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many gc-plan output paths" "argument: $1" "" "run 'cog gc-plan --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $session_file && -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing gc-plan argument" "usage: cog gc-plan --session-files <file> [--repo <dir>]... [--repo-set <file>] (<out.json>|--json)" "" \
    "run 'cog gc-plan --help'"

  json="$(__cog_gc_plan_build_json "$session_file" "$repo_set_file" "${repo_flags[@]}")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_gc_plan_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_gc_plan_self_check" "$json"
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
