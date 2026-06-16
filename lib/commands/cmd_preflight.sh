# shellcheck shell=bash
: 'desc: Run centralized orchestrator preflight checks.'

__cog_preflight_usage() {
  cog::fn::ui_data "Usage: cog preflight <codex|sandbox|git> <out.json>"
  cog::fn::ui_data "Usage: cog preflight agents <out.json> [--classification <file>] [--no-cache]"
}

__cog_preflight_write() {
  local out="$1"
  local check="$2"
  local json="$3"
  cog::fn::json_write_fragment "$out" "$check" "$json"
}

__cog_preflight_detect_codex() {
  local -n __available="$1"
  local -n __health="$2"

  if command -v codex-session >/dev/null 2>&1; then
    __available=true
    if codex-session version >/dev/null 2>&1; then
      __health=ok
    else
      __health=error
    fi
  else
    __available=false
    __health=n/a
  fi
}

__cog_preflight_codex() {
  local out="${1:-}"
  local available health json
  [[ -n $out ]] || cog::fn::error_raise "MissingArgument" \
    "missing output path" "usage: cog preflight codex <out.json>" "" "run 'cog preflight --help'"

  __cog_preflight_detect_codex available health
  json="$(jq -cn \
    --argjson available "$available" \
    --arg health "$health" \
    '{codex_session: {available: $available, health: $health, sandbox_mode: "skipped"}}')"
  __cog_preflight_write "$out" '.codex_session.available != null' "$json"
}

__cog_preflight_sandbox() {
  local out="${1:-}"
  local available health sandbox_mode="n/a" probe_exit="" probe_output="" probe_json="null" json
  local probe_out probe_last
  [[ -n $out ]] || cog::fn::error_raise "MissingArgument" \
    "missing output path" "usage: cog preflight sandbox <out.json>" "" "run 'cog preflight --help'"

  __cog_preflight_detect_codex available health
  if [[ $available == true && $health == ok ]]; then
    probe_out="$(mktemp)"
    probe_last="$(mktemp)"
    probe_exit=0
    cog::fn::codex_sandbox_probe "$probe_out" "$probe_last" 30 || probe_exit=$?
    probe_output="$(<"$probe_out")"
    if [[ $probe_exit -eq 0 ]]; then
      sandbox_mode="native"
    else
      sandbox_mode="fallback"
    fi
    if grep -q "No permissions to create a new namespace" "$probe_out" 2>/dev/null; then
      sandbox_mode="fallback"
    fi
    rm -f "$probe_out" "$probe_last"
    probe_json="$(jq -cn \
      --argjson exit "$probe_exit" \
      --arg output "$probe_output" \
      '{exit: $exit, output: $output}')"
  fi

  json="$(jq -cn \
    --argjson available "$available" \
    --arg health "$health" \
    --arg sandbox "$sandbox_mode" \
    --argjson probe "$probe_json" \
    '{codex_session: {available: $available, health: $health, sandbox_mode: $sandbox, sandbox_probe: $probe}}')"
  __cog_preflight_write "$out" '.codex_session.sandbox_mode != null' "$json"
}

__cog_preflight_git() {
  local out="${1:-}"
  local available=false path="" json
  [[ -n $out ]] || cog::fn::error_raise "MissingArgument" \
    "missing output path" "usage: cog preflight git <out.json>" "" "run 'cog preflight --help'"

  if path="$(cog::fn::git_root 2>/dev/null)"; then
    available=true
  else
    path=""
  fi
  json="$(jq -cn \
    --argjson available "$available" \
    --arg path "$path" \
    '{git_root: {available: $available, path: $path}}')"
  __cog_preflight_write "$out" '.git_root.available != null' "$json"
}

__cog_preflight_cache_dir() {
  printf '%s/preflight-cache\n' "${XDG_STATE_HOME:-$HOME/.local/state}/cog"
}

__cog_preflight_agents_cache_path() {
  local sid="${CLAUDE_CODE_SESSION_ID:-}"
  local root repohash
  [[ -n $sid ]] || return 0
  root="$(cog::fn::git_root 2>/dev/null)" || return 0
  repohash="$(printf '%s' "$root" | sha256sum | cut -c1-12)"
  printf '%s/agents-%s-%s.json\n' "$(__cog_preflight_cache_dir)" "$repohash" "$sid"
}

__cog_preflight_cache_stamp() {
  local head dirty
  head="$(git rev-parse HEAD 2>/dev/null || printf 'no-head')"
  dirty="$(git status --porcelain 2>/dev/null | sha256sum | cut -c1-12)"
  printf '%s:%s\n' "$head" "$dirty"
}

__cog_preflight_cache_fresh() {
  local file="$1"
  local now mtime age
  [[ -f $file ]] || return 1
  now="$(date +%s)"
  mtime="$(stat -c %Y "$file" 2>/dev/null || printf '0')"
  age=$((now - mtime))
  [[ $age -le 3600 ]] || return 1
  [[ $(jq -r '._cache_stamp // empty' "$file" 2>/dev/null) == "$(__cog_preflight_cache_stamp)" ]]
}

__cog_preflight_json_array_from_lines() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

__cog_preflight_agents() {
  local out="" classification_file="" no_cache=false cache_file="" classification
  local is_cli docs_path="" docs_available=false refs_json="[]" json stamp
  local -a langs=() refs=()

  while (($# > 0)); do
    case "$1" in
      --classification)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing classification file" "option: --classification" "" "run 'cog preflight --help'"
        classification_file="$2"
        shift 2
        ;;
      --no-cache)
        no_cache=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown preflight agents option" "option: $1" "" "run 'cog preflight --help'"
        ;;
      *)
        [[ -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many output paths" "argument: $1" "" "run 'cog preflight --help'"
        out="$1"
        shift
        ;;
    esac
  done

  [[ -n $out ]] || cog::fn::error_raise "MissingArgument" \
    "missing output path" "usage: cog preflight agents <out.json>" "" "run 'cog preflight --help'"

  cache_file="$(__cog_preflight_agents_cache_path || true)"
  if [[ -z $classification_file ]]; then
    if [[ $no_cache == false && -n $cache_file ]] && __cog_preflight_cache_fresh "$cache_file"; then
      jq 'del(._cache_stamp)' "$cache_file" >"$out" || cog::fn::error_raise "JsonWriteFailed" \
        "could not materialize cached preflight fragment" "path: ${out}" "" "check output path permissions"
      jq -e '.docs_notes_repo != null' "$out" >/dev/null 2>&1 || cog::fn::error_raise "InvalidJsonOutput" \
        "cached preflight fragment failed validation" "path: ${cache_file}" "" "rerun without cache"
      cog::fn::ui_data "RESOLVED ${out}"
      return 0
    fi
    cog::fn::ui_data "NEEDS-CLASSIFICATION"
    return 0
  fi

  [[ -r $classification_file ]] || cog::fn::error_raise "InputUnreadable" \
    "classification file is not readable" "path: ${classification_file}" "" "check the file path"
  classification="$(jq -c . "$classification_file" 2>/dev/null)" || cog::fn::error_raise "InvalidJsonInput" \
    "classification file is not valid JSON" "path: ${classification_file}" "" "check the file contents"
  is_cli="$(jq -r 'if .is_cli == true then "true" else "false" end' <<<"$classification")"
  mapfile -t langs < <(jq -r '(.languages // [])[]? | .lang // empty' <<<"$classification")

  if docs_path="$(cog::fn::refs_resolve_docs_path)"; then
    docs_available=true
    mapfile -t refs < <(cog::fn::refs_compute "$docs_path" "$is_cli" "${langs[@]}")
  fi
  refs_json="$(__cog_preflight_json_array_from_lines "${refs[@]}")"
  json="$(jq -cn \
    --argjson classification "$classification" \
    --argjson available "$docs_available" \
    --arg path "$docs_path" \
    --argjson refs "$refs_json" \
    '{classification: $classification, docs_notes_repo: {available: $available, path: $path, relevant_agents_md: $refs}}')"
  __cog_preflight_write "$out" '.docs_notes_repo != null' "$json"

  if [[ $no_cache == false && -n $cache_file ]]; then
    mkdir -p "$(dirname "$cache_file")"
    stamp="$(__cog_preflight_cache_stamp)"
    jq --arg stamp "$stamp" '. + {_cache_stamp: $stamp}' "$out" >"${cache_file}.tmp" 2>/dev/null &&
      mv "${cache_file}.tmp" "$cache_file" || rm -f "${cache_file}.tmp"
  fi
}

cog::cmd::preflight() {
  local mode="${1:-}"

  case "$mode" in
    -h | --help)
      __cog_preflight_usage
      ;;
    codex)
      shift
      [[ $# -eq 1 ]] || cog::fn::error_raise "InvalidInput" \
        "invalid preflight codex arguments" "usage: cog preflight codex <out.json>" "" "run 'cog preflight --help'"
      __cog_preflight_codex "$1"
      ;;
    sandbox)
      shift
      [[ $# -eq 1 ]] || cog::fn::error_raise "InvalidInput" \
        "invalid preflight sandbox arguments" "usage: cog preflight sandbox <out.json>" "" "run 'cog preflight --help'"
      __cog_preflight_sandbox "$1"
      ;;
    git)
      shift
      [[ $# -eq 1 ]] || cog::fn::error_raise "InvalidInput" \
        "invalid preflight git arguments" "usage: cog preflight git <out.json>" "" "run 'cog preflight --help'"
      __cog_preflight_git "$1"
      ;;
    agents)
      shift
      __cog_preflight_agents "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" \
        "missing preflight check" "usage: cog preflight <check> <out.json>" "" "run 'cog preflight --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown preflight check" "check: ${mode}" "" "run 'cog preflight --help'"
      ;;
  esac
}
