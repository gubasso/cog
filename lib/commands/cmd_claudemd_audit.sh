# shellcheck shell=bash
: 'desc: Audit CLAUDE.md deterministic signals.'

__cog_claudemd_audit_self_check='(.ok|type=="boolean") and (.path|type=="string") and (.line_count|type=="number") and (.estimated_tokens|type=="number") and (.git_history|type=="object") and (.line_map|type=="array") and (.stale_probes|type=="array") and (.lint|type=="object")'

__cog_claudemd_audit_usage() {
  cog::fn::ui_data "Usage: cog claudemd-audit --path <CLAUDE.md> (<out.json>|--json)"
}

__cog_claudemd_audit_json_string_array() {
  if [[ $# -eq 0 ]]; then jq -cn '[]'; else printf '%s\n' "$@" | jq -R . | jq -s .; fi
}

__cog_claudemd_audit_json_object_array() {
  if [[ $# -eq 0 ]]; then jq -cn '[]'; else printf '%s\n' "$@" | jq -s .; fi
}

__cog_claudemd_audit_resolve_path() {
  local input="$1"
  [[ -r $input && -f $input ]] || return 1
  realpath -e -- "$input"
}

__cog_claudemd_audit_line_count_for() {
  awk 'END {print NR}' "$1"
}

__cog_claudemd_audit_repo_relative_path_for() {
  local root="$1" path="$2"
  if [[ $path == "$root"/* ]]; then printf '%s\n' "${path#"$root"/}"; else printf '%s\n' "$path"; fi
}

__cog_claudemd_audit_history_json() {
  local repo_root="$1" rel_path="$2" log_short log_full commit_count oldest_short oldest_full oldest_date oldest_subject conservative
  if [[ -z $repo_root || -z $rel_path ]]; then
    jq -cn '{available: false, commit_count: 0, initial_commit: null, conservative_mode: true, initial_full_sha: null}'
    return 0
  fi
  log_short="$(git -C "$repo_root" log --follow --format='%h%x09%ad%x09%s' --date=iso -- "$rel_path" 2>/dev/null || true)"
  if [[ -z $log_short ]]; then
    jq -cn '{available: false, commit_count: 0, initial_commit: null, conservative_mode: true, initial_full_sha: null}'
    return 0
  fi
  log_full="$(git -C "$repo_root" log --follow --format='%H' -- "$rel_path" 2>/dev/null || true)"
  commit_count="$(printf '%s\n' "$log_short" | awk 'NF {count++} END {print count + 0}')"
  IFS=$'\t' read -r oldest_short oldest_date oldest_subject < <(printf '%s\n' "$log_short" | tail -n 1)
  oldest_full="$(printf '%s\n' "$log_full" | tail -n 1)"
  conservative=true
  [[ $commit_count -gt 1 ]] && conservative=false
  jq -cn --argjson available true --argjson commit_count "$commit_count" --arg sha "$oldest_short" \
    --arg full_sha "$oldest_full" --arg date "${oldest_date:-}" --arg subject "${oldest_subject:-}" \
    --argjson conservative_mode "$conservative" \
    '{available: $available, commit_count: $commit_count,
      initial_commit: {sha: $sha, date: $date, subject: $subject},
      conservative_mode: $conservative_mode,
      initial_full_sha: (if $full_sha == "" then null else $full_sha end)}'
}

__cog_claudemd_audit_line_map_json() {
  local path="$1" repo_root="$2" rel_path="$3" history="$4"
  local available commit_count initial_full blame_tmp line_no text sha origin commit
  local -a objects=()
  available="$(jq -r '.available' <<<"$history")"
  commit_count="$(jq -r '.commit_count' <<<"$history")"
  initial_full="$(jq -r '.initial_full_sha // ""' <<<"$history")"
  if [[ $available != true || $commit_count -le 1 || -z $initial_full ]]; then
    line_no=0
    while IFS= read -r text || [[ -n $text ]]; do
      line_no=$((line_no + 1))
      objects+=("$(jq -cn --argjson line "$line_no" --arg text "$text" '{line: $line, text: $text, origin: "unknown", commit: null}')")
    done <"$path"
    __cog_claudemd_audit_json_object_array "${objects[@]}"
    return 0
  fi
  blame_tmp="$(mktemp)"
  if ! git -C "$repo_root" blame --line-porcelain -- "$rel_path" >"$blame_tmp" 2>/dev/null; then
    rm -f "$blame_tmp"
    __cog_claudemd_audit_line_map_json "$path" "" "" "$(jq -cn '{available:false, commit_count:0}')"
    return 0
  fi
  line_no=0
  while IFS=$'\t' read -r sha text || [[ -n ${sha:-} ]]; do
    [[ -n ${sha:-} ]] || continue
    line_no=$((line_no + 1))
    origin=user-added
    [[ $sha == "$initial_full" ]] && origin=baseline
    commit="${sha:0:12}"
    objects+=("$(jq -cn --argjson line "$line_no" --arg text "${text:-}" --arg origin "$origin" --arg commit "$commit" \
      '{line: $line, text: $text, origin: $origin, commit: $commit}')")
  done < <(awk '/^[0-9a-f]{40} / {sha = $1} /^\t/ {sub(/^\t/, ""); print sha "\t" $0}' "$blame_tmp")
  rm -f "$blame_tmp"
  __cog_claudemd_audit_json_object_array "${objects[@]}"
}

__cog_claudemd_audit_stale_probes_json() {
  local path="$1" repo_root="$2" file_dir token clean exists confidence
  local -a tokens=() objects=()
  file_dir="$(dirname -- "$path")"
  # shellcheck disable=SC2016 # grep pattern in the loop redirection uses literal backticks; must stay unexpanded.
  while IFS= read -r token || [[ -n $token ]]; do
    clean="${token#\`}"
    clean="${clean%\`}"
    clean="${clean%\"}"
    clean="${clean#\"}"
    clean="${clean%\'}"
    clean="${clean#\'}"
    clean="${clean%,}"
    clean="${clean%;}"
    clean="${clean%:}"
    [[ $clean == *"://"* || $clean == -* || $clean == *"*"* ]] && continue
    [[ $clean == */* ]] || continue
    [[ $clean =~ ^[A-Za-z0-9._~/-]+$ ]] || continue
    tokens+=("$clean")
  done < <(grep -Eo '`[^`]+`|[A-Za-z0-9._~/-]+/[A-Za-z0-9._~/-]+' "$path" 2>/dev/null || true)
  [[ ${#tokens[@]} -gt 0 ]] || {
    jq -cn '[]'
    return 0
  }
  mapfile -t tokens < <(printf '%s\n' "${tokens[@]}" | LC_ALL=C sort -u)
  for token in "${tokens[@]}"; do
    exists=false
    if [[ $token == /* && -e $token ]]; then
      exists=true
    elif [[ -n $repo_root && -e $repo_root/$token ]]; then
      exists=true
    elif [[ -e $file_dir/$token ]]; then
      exists=true
    fi
    confidence=high
    [[ $token == /* ]] && confidence=medium
    objects+=("$(jq -cn --arg reference "$token" --arg kind path --argjson exists "$exists" --arg confidence "$confidence" \
      '{reference: $reference, kind: $kind, exists: $exists, confidence: $confidence}')")
  done
  __cog_claudemd_audit_json_object_array "${objects[@]}"
}

__cog_claudemd_audit_lint_json() {
  local path="$1" line line_no in_fence=false fence_lang inventory_heading=false inventory_run=0
  local -a no_lang=() inventory=() runnable=()
  line_no=0
  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))
    if [[ $line =~ ^[[:space:]]*\`\`\`(.*)$ ]]; then
      if [[ $in_fence == false ]]; then
        fence_lang="${BASH_REMATCH[1]}"
        [[ -z ${fence_lang//[[:space:]]/} ]] && no_lang+=("$line_no")
        in_fence=true
      else
        in_fence=false
      fi
      continue
    fi
    if [[ $line =~ ^#{1,6}[[:space:]].*(Files|File|Structure|Layout|Tree|Inventory|Directories) ]]; then
      inventory_heading=true
      inventory_run=0
      continue
    fi
    if [[ $inventory_heading == true ]]; then
      if [[ $line =~ ^[[:space:]]*[-*]?[[:space:]]*[A-Za-z0-9._/-]+[[:space:]]+[-—:] || $line =~ ^[[:space:]]*[├└│] ]]; then
        inventory_run=$((inventory_run + 1))
        inventory+=("$line_no")
      elif [[ -z ${line//[[:space:]]/} ]]; then
        :
      else
        inventory_heading=false
        inventory_run=0
      fi
    fi
    if [[ $in_fence == true && ($line == *"<"*">"* || $line =~ ^[[:space:]]*\$[[:space:]]+) ]]; then
      runnable+=("$line_no")
    fi
  done <"$path"
  jq -n --argjson no_lang "$(__cog_claudemd_audit_json_string_array "${no_lang[@]}")" \
    --argjson inventory "$(__cog_claudemd_audit_json_string_array "${inventory[@]}")" \
    --argjson runnable "$(__cog_claudemd_audit_json_string_array "${runnable[@]}")" \
    '{fenced_code_blocks_without_language: ($no_lang | map(tonumber)),
      file_inventory_candidates: ($inventory | map(tonumber)),
      runnable_command_candidates: ($runnable | map(tonumber))}'
}

__cog_claudemd_audit_build_json() {
  local input_path="$1" path repo_root="" repo_relative_path="" line_count estimated_tokens over_200 history line_map stale_probes lint
  path="$(__cog_claudemd_audit_resolve_path "$input_path")" || cog::fn::error_raise "InputUnreadable" "path is not a readable file" "path: ${input_path}" "" "check the path"
  repo_root="$(git -C "$(dirname -- "$path")" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n $repo_root ]] && repo_relative_path="$(__cog_claudemd_audit_repo_relative_path_for "$repo_root" "$path")"
  line_count="$(__cog_claudemd_audit_line_count_for "$path")"
  estimated_tokens=$((line_count * 5))
  over_200=false
  [[ $line_count -gt 200 ]] && over_200=true
  history="$(__cog_claudemd_audit_history_json "$repo_root" "$repo_relative_path")"
  line_map="$(__cog_claudemd_audit_line_map_json "$path" "$repo_root" "$repo_relative_path" "$history")"
  stale_probes="$(__cog_claudemd_audit_stale_probes_json "$path" "$repo_root")"
  lint="$(__cog_claudemd_audit_lint_json "$path")"
  history="$(jq 'del(.initial_full_sha)' <<<"$history")"
  jq -n --argjson ok true \
    --argjson repo_root "$(jq -cn --arg value "$repo_root" 'if $value == "" then null else $value end')" \
    --arg path "$path" \
    --argjson repo_relative_path "$(jq -cn --arg value "$repo_relative_path" 'if $value == "" then null else $value end')" \
    --argjson line_count "$line_count" --argjson estimated_tokens "$estimated_tokens" --argjson over_200_lines "$over_200" \
    --argjson git_history "$history" --argjson line_map "$line_map" --argjson stale_probes "$stale_probes" --argjson lint "$lint" \
    '{ok: $ok, repo_root: $repo_root, path: $path, repo_relative_path: $repo_relative_path,
      line_count: $line_count, estimated_tokens: $estimated_tokens, over_200_lines: $over_200_lines,
      git_history: $git_history, line_map: $line_map, stale_probes: $stale_probes, lint: $lint}'
}

cog::cmd::claudemd_audit() {
  local claude_path="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_claudemd_audit_usage
        return 0
        ;;
      --path)
        [[ $# -ge 2 && -z $claude_path ]] || cog::fn::error_raise "MissingArgument" "missing CLAUDE.md path" "option: --path" "" "run 'cog claudemd-audit --help'"
        claude_path="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate claudemd-audit output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown claudemd-audit option" "option: $1" "" "run 'cog claudemd-audit --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many claudemd-audit output paths" "argument: $1" "" "run 'cog claudemd-audit --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $claude_path && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing claudemd-audit argument" "usage: cog claudemd-audit --path <CLAUDE.md> (<out.json>|--json)" "" "run 'cog claudemd-audit --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_claudemd_audit_build_json "$claude_path")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_claudemd_audit_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_claudemd_audit_self_check" "$json"; fi
}
