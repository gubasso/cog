# shellcheck shell=bash
: 'desc: Run centralized orchestrator preflight checks.'

__cog_preflight_usage() {
  cog::fn::ui_data "Usage: cog preflight <codex|claude|sandbox|git|claude-env> <out.json>"
}

__cog_preflight_write() {
  local out="$1"
  local check="$2"
  local json="$3"
  cog::fn::json_write_fragment "$out" "$check" "$json"
}

# Probe the codex wrapper's launch preconditions. `health` covers the binary and
# the version it reports; `auth` is the separate credential question, because a
# wrapper that runs happily with no bound account still cannot launch, and
# ADR-0031 requires that failure be reported before the durable job exists
# rather than surfacing later as an agent exit.
__cog_preflight_detect_codex() {
  local -n __available="$1"
  local -n __health="$2"
  local -n __auth="$3"

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
    __auth=n/a
    return 0
  fi

  if [[ $__health != ok ]]; then
    __auth=error
    return 0
  fi
  if codex-session account current >/dev/null 2>&1; then
    __auth=ok
  else
    __auth=missing
  fi
}

__cog_preflight_codex() {
  local out="${1:-}"
  local available health auth json
  [[ -n $out ]] || cog::fn::error_raise "MissingArgument" \
    "missing output path" "usage: cog preflight codex <out.json>" "" "run 'cog preflight --help'"

  __cog_preflight_detect_codex available health auth
  json="$(jq -cn \
    --argjson available "$available" \
    --arg health "$health" \
    --arg auth "$auth" \
    '{codex_session: {available: $available, health: $health, auth: $auth, sandbox_mode: "skipped"}}')"
  __cog_preflight_write "$out" '.codex_session.available != null' "$json"
}

# Probe the claude wrapper's launch preconditions: the binary is present, it
# runs, and an account is bound. Every one of these is a standing condition that
# a retry reproduces, and every one is knowable before anything is spawned —
# which is the whole point of ADR-0031. The wrapper execs its child, so a
# precondition failure observed after launch would be indistinguishable from an
# agent failure.
__cog_preflight_detect_claude() {
  local -n __available="$1"
  local -n __health="$2"
  local -n __version="$3"
  local -n __auth="$4"
  local bin

  bin="$(cog::fn::claude_binary)"
  __version=""
  if command -v "$bin" >/dev/null 2>&1; then
    __available=true
    if __version="$("$bin" version 2>/dev/null)"; then
      __health=ok
    else
      __health=error
      __version=""
    fi
  else
    __available=false
    __health=n/a
    __auth=n/a
    return 0
  fi

  if [[ $__health != ok ]]; then
    __auth=error
    return 0
  fi
  if "$bin" account status >/dev/null 2>&1; then
    __auth=ok
  else
    __auth=missing
  fi
}

__cog_preflight_claude() {
  local out="${1:-}"
  local available health version auth json
  [[ -n $out ]] || cog::fn::error_raise "MissingArgument" \
    "missing output path" "usage: cog preflight claude <out.json>" "" "run 'cog preflight --help'"

  __cog_preflight_detect_claude available health version auth
  json="$(jq -cn \
    --argjson available "$available" \
    --arg health "$health" \
    --arg version "$version" \
    --arg auth "$auth" \
    '{claude_session: {available: $available, health: $health, version: $version, auth: $auth}}')"
  __cog_preflight_write "$out" '.claude_session.available != null' "$json"
}

__cog_preflight_sandbox() {
  local out="${1:-}"
  local available health sandbox_mode="n/a" probe_exit="" probe_output="" probe_json="null" json
  local probe_out probe_last
  # The sandbox fragment reports sandbox capability, not credentials, so the
  # auth reading is discarded rather than published here.
  # shellcheck disable=SC2034 # assigned through the detector's nameref
  local auth_discard
  [[ -n $out ]] || cog::fn::error_raise "MissingArgument" \
    "missing output path" "usage: cog preflight sandbox <out.json>" "" "run 'cog preflight --help'"

  __cog_preflight_detect_codex available health auth_discard
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

__cog_preflight_uint_ge() {
  local value="$1"
  local min="$2"
  [[ $value =~ ^[0-9]+$ && $value -ge $min ]]
}

__cog_preflight_claude_env_json() {
  local ok="$1"
  local advisory="$2"
  local reason="$3"
  local disable_bg="${CLAUDE_CODE_DISABLE_BACKGROUND_TASKS-}"
  local default_timeout="${BASH_DEFAULT_TIMEOUT_MS-}"
  local max_timeout="${BASH_MAX_TIMEOUT_MS-}"
  local auto_background="${CLAUDE_AUTO_BACKGROUND_TASKS-}"
  local default_timeout_ok=false max_timeout_ok=false auto_background_set=false

  __cog_preflight_uint_ge "$default_timeout" 600000 && default_timeout_ok=true
  __cog_preflight_uint_ge "$max_timeout" 600000 && max_timeout_ok=true
  [[ -n $auto_background ]] && auto_background_set=true

  jq -cn \
    --argjson ok "$ok" \
    --argjson advisory "$advisory" \
    --arg reason "$reason" \
    --arg disable_bg "$disable_bg" \
    --arg default_timeout "$default_timeout" \
    --arg max_timeout "$max_timeout" \
    --arg auto_background "$auto_background" \
    --argjson default_timeout_ok "$default_timeout_ok" \
    --argjson max_timeout_ok "$max_timeout_ok" \
    --argjson auto_background_set "$auto_background_set" \
    '{
      claude_env: {
        ok: $ok,
        advisory: $advisory,
        reason: $reason,
        observed: {
          CLAUDE_CODE_DISABLE_BACKGROUND_TASKS: $disable_bg,
          BASH_DEFAULT_TIMEOUT_MS: $default_timeout,
          BASH_MAX_TIMEOUT_MS: $max_timeout,
          CLAUDE_AUTO_BACKGROUND_TASKS: $auto_background
        },
        checks: {
          background_tasks_disabled: ($disable_bg == "1"),
          bash_default_timeout_ge_600000: $default_timeout_ok,
          bash_max_timeout_ge_600000: $max_timeout_ok,
          auto_background_tasks_set: $auto_background_set
        }
      }
    }'
}

__cog_preflight_claude_env() {
  local out=""

  while (($# > 0)); do
    case "$1" in
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown preflight claude-env option" "option: $1" "" "run 'cog preflight --help'"
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
    "missing output path" "usage: cog preflight claude-env <out.json>" "" \
    "run 'cog preflight --help'"

  if [[ ${CLAUDE_CODE_DISABLE_BACKGROUND_TASKS-} == "1" ]]; then
    __cog_preflight_write "$out" '.claude_env.ok != null' \
      "$(__cog_preflight_claude_env_json true false "CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 is in force")"
    return 0
  fi

  __cog_preflight_write "$out" '.claude_env.ok != null' \
    "$(__cog_preflight_claude_env_json false false "CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 is required to disable auto-backgrounding")"
  cog::fn::error_raise "ClaudeEnvMissing" \
    "CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 is not in force" \
    "path: ${out}" \
    "BASH timeout env vars are diagnostic only and do not disable auto-backgrounding" \
    "restart claude-session after updating the base env layer"
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
    claude)
      shift
      [[ $# -eq 1 ]] || cog::fn::error_raise "InvalidInput" \
        "invalid preflight claude arguments" "usage: cog preflight claude <out.json>" "" "run 'cog preflight --help'"
      __cog_preflight_claude "$1"
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
    claude-env)
      shift
      __cog_preflight_claude_env "$@"
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
