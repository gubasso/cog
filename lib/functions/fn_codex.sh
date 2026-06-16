# shellcheck shell=bash

__cog_codex_require_arg() {
  local value="${1:-}"
  local name="$2"
  local fn="$3"

  [[ -n $value ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing ${name}" "function: ${fn}" "expected <${name}>" ""
}

__cog_codex_require_cmd() {
  local cmd="$1"
  __have "$cmd" || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
    "required command not found" "command: ${cmd}" "" "install ${cmd} and retry"
}

__cog_codex_require_prompt() {
  local prompt_file="${1:-}"
  local fn="$2"

  __cog_codex_require_arg "$prompt_file" "prompt_file" "$fn"
  [[ -r $prompt_file ]] || cog::helpers::die "$EX_NOINPUT" "InputUnreadable" \
    "prompt file is not readable" "path: ${prompt_file}" "" "check the prompt path"
}

__cog_codex_validate_mode() {
  case "${1:-}" in
    native | fallback | quick-auto | danger)
      return 0
      ;;
    *)
      cog::helpers::die "$EX_USAGE" "InvalidInput" \
        "invalid codex exec mode" "mode: ${1:-}" \
        "expected native, fallback, quick-auto, or danger" ""
      ;;
  esac
}

__cog_codex_read_prompt() {
  local prompt_file="$1"
  cat "$prompt_file"
}

cog::fn::codex_exec_command() {
  local mode="${1:-}"
  local profile="${2:-}"
  local prompt_file="${3:-}"
  local output_file="${4:-}"
  local events_file="${5:-}"
  local stderr_file="${6:-}"

  __cog_codex_require_arg "$mode" "mode" "cog::fn::codex_exec_command"
  __cog_codex_validate_mode "$mode"
  __cog_codex_require_arg "$profile" "profile" "cog::fn::codex_exec_command"
  __cog_codex_require_arg "$prompt_file" "prompt_file" "cog::fn::codex_exec_command"
  __cog_codex_require_arg "$output_file" "output_file" "cog::fn::codex_exec_command"
  __cog_codex_require_arg "$events_file" "events_file" "cog::fn::codex_exec_command"

  case "$mode" in
    native)
      __cog_codex_require_arg "$stderr_file" "stderr_file" "cog::fn::codex_exec_command"
      cat <<EOF
codex-session exec --profile $profile --sandbox read-only --json \\
  --output-last-message "$output_file" \\
  "\$(cat "$prompt_file")" \\
  < /dev/null \\
  > "$events_file" \\
  2> "$stderr_file"
EOF
      ;;
    fallback)
      __cog_codex_require_arg "$stderr_file" "stderr_file" "cog::fn::codex_exec_command"
      cat <<EOF
codex-session exec --profile $profile \\
  -c 'sandbox_permissions=["disk-full-read-access"]' --json \\
  --output-last-message "$output_file" \\
  "\$(cat "$prompt_file")" \\
  < /dev/null \\
  > "$events_file" \\
  2> "$stderr_file"
EOF
      ;;
    quick-auto)
      cat <<EOF
codex-session --account auto exec --profile $profile --sandbox read-only --json \\
  --output-last-message "$output_file" \\
  "\$(cat "$prompt_file")" \\
  > "$events_file"
EOF
      ;;
    danger)
      cat <<EOF
codex-session exec --profile $profile \\
  --dangerously-bypass-approvals-and-sandbox --json \\
  --output-last-message "$output_file" \\
  "\$(cat "$prompt_file")" \\
  < /dev/null > "$events_file"
EOF
      ;;
  esac
}

cog::fn::codex_resume_command() {
  local account="${1:-}"
  local profile="${2:-}"
  local thread_id="${3:-}"
  local prompt_file="${4:-}"
  local output_file="${5:-}"
  local events_file="${6:-}"

  __cog_codex_require_arg "$account" "account" "cog::fn::codex_resume_command"
  __cog_codex_require_arg "$profile" "profile" "cog::fn::codex_resume_command"
  __cog_codex_require_arg "$thread_id" "thread_id" "cog::fn::codex_resume_command"
  __cog_codex_require_arg "$prompt_file" "prompt_file" "cog::fn::codex_resume_command"
  __cog_codex_require_arg "$output_file" "output_file" "cog::fn::codex_resume_command"
  __cog_codex_require_arg "$events_file" "events_file" "cog::fn::codex_resume_command"

  cat <<EOF
codex-session --account "$account" exec --profile $profile resume "$thread_id" \\
  --dangerously-bypass-approvals-and-sandbox --json \\
  --output-last-message "$output_file" \\
  "\$(cat "$prompt_file")" \\
  < /dev/null > "$events_file"
EOF
}

cog::fn::codex_exec_run() {
  local mode="${1:-}"
  local profile="${2:-}"
  local prompt_file="${3:-}"
  local output_file="${4:-}"
  local events_file="${5:-}"
  local stderr_file="${6:-}"
  local prompt

  __cog_codex_require_cmd codex-session
  __cog_codex_require_arg "$mode" "mode" "cog::fn::codex_exec_run"
  __cog_codex_validate_mode "$mode"
  __cog_codex_require_arg "$profile" "profile" "cog::fn::codex_exec_run"
  __cog_codex_require_prompt "$prompt_file" "cog::fn::codex_exec_run"
  __cog_codex_require_arg "$output_file" "output_file" "cog::fn::codex_exec_run"
  __cog_codex_require_arg "$events_file" "events_file" "cog::fn::codex_exec_run"
  prompt="$(__cog_codex_read_prompt "$prompt_file")"

  case "$mode" in
    native)
      __cog_codex_require_arg "$stderr_file" "stderr_file" "cog::fn::codex_exec_run"
      codex-session exec --profile "$profile" --sandbox read-only --json \
        --output-last-message "$output_file" \
        "$prompt" \
        </dev/null >"$events_file" 2>"$stderr_file"
      ;;
    fallback)
      __cog_codex_require_arg "$stderr_file" "stderr_file" "cog::fn::codex_exec_run"
      codex-session exec --profile "$profile" \
        -c 'sandbox_permissions=["disk-full-read-access"]' --json \
        --output-last-message "$output_file" \
        "$prompt" \
        </dev/null >"$events_file" 2>"$stderr_file"
      ;;
    quick-auto)
      codex-session --account auto exec --profile "$profile" --sandbox read-only --json \
        --output-last-message "$output_file" \
        "$prompt" \
        >"$events_file"
      ;;
    danger)
      if [[ -n $stderr_file ]]; then
        codex-session exec --profile "$profile" \
          --dangerously-bypass-approvals-and-sandbox --json \
          --output-last-message "$output_file" \
          "$prompt" \
          </dev/null >"$events_file" 2>"$stderr_file"
      else
        codex-session exec --profile "$profile" \
          --dangerously-bypass-approvals-and-sandbox --json \
          --output-last-message "$output_file" \
          "$prompt" \
          </dev/null >"$events_file"
      fi
      ;;
  esac
}

cog::fn::codex_sandbox_probe() {
  local out_file="${1:-}"
  local last_file="${2:-}"
  local timeout_s="${3:-30}"

  __cog_codex_require_arg "$out_file" "out_file" "cog::fn::codex_sandbox_probe"
  __cog_codex_require_arg "$last_file" "last_file" "cog::fn::codex_sandbox_probe"
  __cog_codex_require_cmd timeout
  __cog_codex_require_cmd codex-session
  timeout "$timeout_s" codex-session exec --sandbox read-only --json \
    -c model=gpt-5.4-mini \
    -c model_reasoning_effort=low \
    --output-last-message "$last_file" \
    "echo sandbox-probe" </dev/null >"$out_file" 2>&1
}

cog::fn::codex_resume_run() {
  local account="${1:-}"
  local profile="${2:-}"
  local thread_id="${3:-}"
  local prompt_file="${4:-}"
  local output_file="${5:-}"
  local events_file="${6:-}"
  local stderr_file="${7:-}"
  local prompt

  __cog_codex_require_cmd codex-session
  __cog_codex_require_arg "$account" "account" "cog::fn::codex_resume_run"
  __cog_codex_require_arg "$profile" "profile" "cog::fn::codex_resume_run"
  __cog_codex_require_arg "$thread_id" "thread_id" "cog::fn::codex_resume_run"
  __cog_codex_require_prompt "$prompt_file" "cog::fn::codex_resume_run"
  __cog_codex_require_arg "$output_file" "output_file" "cog::fn::codex_resume_run"
  __cog_codex_require_arg "$events_file" "events_file" "cog::fn::codex_resume_run"
  prompt="$(__cog_codex_read_prompt "$prompt_file")"

  if [[ -n $stderr_file ]]; then
    codex-session --account "$account" exec --profile "$profile" resume "$thread_id" \
      --dangerously-bypass-approvals-and-sandbox --json \
      --output-last-message "$output_file" \
      "$prompt" \
      </dev/null >"$events_file" 2>"$stderr_file"
  else
    codex-session --account "$account" exec --profile "$profile" resume "$thread_id" \
      --dangerously-bypass-approvals-and-sandbox --json \
      --output-last-message "$output_file" \
      "$prompt" \
      </dev/null >"$events_file"
  fi
}

cog::fn::codex_extract_thread() {
  local events_file="${1:-}"
  local selection="${2:-}"

  [[ -r $events_file ]] || return 0
  __cog_codex_require_cmd jq

  case "$selection" in
    first)
      jq -r 'select(.type == "thread.started") | .thread_id' "$events_file" 2>/dev/null | head -1
      ;;
    last)
      jq -r 'select(.type == "thread.started") | .thread_id' "$events_file" 2>/dev/null | tail -1
      ;;
    *)
      cog::helpers::die "$EX_USAGE" "InvalidInput" \
        "invalid thread selection" "selection: ${selection}" "expected first or last" ""
      ;;
  esac
}

cog::fn::codex_lookup_thread_account() {
  local thread_id="${1:-}"
  local tidx account

  [[ -n $thread_id ]] || return 0
  __cog_codex_require_cmd jq
  tidx="${XDG_STATE_HOME:-$HOME/.local/state}/codex-session/thread-index.jsonl"
  if [[ -r $tidx ]]; then
    account="$(jq -r --arg tid "$thread_id" 'select(."thread-id" == $tid) | .account' "$tidx" 2>/dev/null | tail -1)"
    if [[ -n $account && $account != "null" ]]; then
      printf '%s\n' "$account"
      return 0
    fi
  fi

  __cog_codex_require_cmd codex-session
  codex-session account current --format json 2>/dev/null | jq -r '.name // empty' 2>/dev/null || true
}

cog::fn::codex_check_output() {
  local output_file="${1:-}"
  local stderr_file="${2:-}"

  if [[ ! -s $output_file ]]; then
    printf '%s\n' "empty-output"
  elif [[ -n $stderr_file ]] && grep -q "terminated due to a signal" "$stderr_file" 2>/dev/null; then
    printf '%s\n' "sigterm"
  else
    printf '%s\n' "ok"
  fi
}

cog::fn::codex_extract_reset_eta() {
  local stderr_file="${1:-}"
  [[ -r $stderr_file ]] || return 0
  grep -Eo 'earliest available: .+' "$stderr_file" 2>/dev/null | tail -1 || true
}

cog::fn::codex_resume_warning() {
  local stderr_file="${1:-}"
  local content=""

  [[ -r $stderr_file ]] && content="$(<"$stderr_file")"
  if grep -Eq 'warning:.*recovered owner|recovered owner' <<<"$content"; then
    printf '%s\n' "recovered-owner"
  elif grep -Eq "warning: --account .* ignored for resume|owned by" <<<"$content"; then
    printf '%s\n' "account-mismatch"
  fi
}

cog::fn::codex_classify_error() {
  local exit_code="${1:-}"
  local stderr_file="${2:-}"
  local content=""

  [[ -n $exit_code ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing exit code" "function: cog::fn::codex_classify_error" "" ""
  [[ -r $stderr_file ]] && content="$(<"$stderr_file")"

  if [[ $exit_code -eq 0 ]]; then
    printf '%s\n' "ok"
  elif grep -Eq 'ResumeBlocked|account: resume blocked' <<<"$content"; then
    printf '%s\n' "resume-blocked"
  elif grep -Eq 'ResumeOwnerMissing|account: no rollout for thread|no rollout for thread' <<<"$content"; then
    printf '%s\n' "resume-owner-missing"
  elif grep -Eq "warning: --account .* ignored for resume|owned by" <<<"$content"; then
    printf '%s\n' "account-mismatch"
  elif grep -Eq 'warning:.*recovered owner|recovered owner' <<<"$content"; then
    printf '%s\n' "recovered-owner"
  elif grep -Eq 'ResumeNoRollout|resume failed for thread|sandbox-mismatch|sandbox mismatch' <<<"$content"; then
    printf '%s\n' "resume-no-rollout"
  elif [[ $exit_code -eq 124 ]]; then
    printf '%s\n' "timeout-124"
  elif [[ $exit_code -eq 75 ]] && grep -Eq 'AutoExhausted|no eligible account|earliest available' <<<"$content"; then
    printf '%s\n' "quota-75"
  elif grep -q "terminated due to a signal" <<<"$content"; then
    printf '%s\n' "sigterm"
  else
    printf '%s\n' "nonzero"
  fi
}
