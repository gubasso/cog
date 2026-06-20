# shellcheck shell=bash
#
# Codex invocation source of truth:
# this file is the only layer that builds or runs direct codex-session exec
# and resume command lines. Skills and commands above it must invoke Codex
# through `cog codex-runner run-exec` or `cog codex-runner run-resume`.

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

__cog_codex_map_effort() {
  local effort="${1:-}"

  # Round 1 maps legacy profile names to native Codex reasoning effort as a
  # judgment call grounded in docs/reference/model-effort-policy.md escalation
  # guidance and the existing low-effort codex_sandbox_probe precedent.
  case "$effort" in
    minimal | low | medium | high)
      printf '%s\n' "$effort"
      ;;
    quick)
      printf '%s\n' low
      ;;
    deep)
      printf '%s\n' high
      ;;
    *)
      cog::helpers::die "$EX_USAGE" "InvalidInput" \
        "invalid codex effort" "effort: ${effort}" \
        "expected minimal, low, medium, high, quick, or deep" ""
      ;;
  esac
}

__cog_codex_read_prompt() {
  local prompt_file="$1"
  cat "$prompt_file"
}

cog::fn::codex_exec_command() {
  local mode="${1:-}"
  local effort="${2:-}"
  local prompt_file="${3:-}"
  local output_file="${4:-}"
  local events_file="${5:-}"
  local stderr_file="${6:-}"
  local codex_effort

  __cog_codex_require_arg "$mode" "mode" "cog::fn::codex_exec_command"
  __cog_codex_validate_mode "$mode"
  __cog_codex_require_arg "$effort" "effort" "cog::fn::codex_exec_command"
  __cog_codex_require_arg "$prompt_file" "prompt_file" "cog::fn::codex_exec_command"
  __cog_codex_require_arg "$output_file" "output_file" "cog::fn::codex_exec_command"
  __cog_codex_require_arg "$events_file" "events_file" "cog::fn::codex_exec_command"
  codex_effort="$(__cog_codex_map_effort "$effort")"

  case "$mode" in
    native)
      __cog_codex_require_arg "$stderr_file" "stderr_file" "cog::fn::codex_exec_command"
      cat <<EOF
codex-session exec -c model_reasoning_effort=$codex_effort --sandbox read-only --json \\
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
codex-session exec -c model_reasoning_effort=$codex_effort \\
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
codex-session --account auto exec -c model_reasoning_effort=$codex_effort --sandbox read-only --json \\
  --output-last-message "$output_file" \\
  "\$(cat "$prompt_file")" \\
  > "$events_file"
EOF
      ;;
    danger)
      cat <<EOF
codex-session exec -c model_reasoning_effort=$codex_effort \\
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
  local effort="${2:-}"
  local thread_id="${3:-}"
  local prompt_file="${4:-}"
  local output_file="${5:-}"
  local events_file="${6:-}"
  local codex_effort

  __cog_codex_require_arg "$account" "account" "cog::fn::codex_resume_command"
  __cog_codex_require_arg "$effort" "effort" "cog::fn::codex_resume_command"
  __cog_codex_require_arg "$thread_id" "thread_id" "cog::fn::codex_resume_command"
  __cog_codex_require_arg "$prompt_file" "prompt_file" "cog::fn::codex_resume_command"
  __cog_codex_require_arg "$output_file" "output_file" "cog::fn::codex_resume_command"
  __cog_codex_require_arg "$events_file" "events_file" "cog::fn::codex_resume_command"
  codex_effort="$(__cog_codex_map_effort "$effort")"

  cat <<EOF
codex-session --account "$account" exec -c model_reasoning_effort=$codex_effort resume "$thread_id" \\
  --dangerously-bypass-approvals-and-sandbox --json \\
  --output-last-message "$output_file" \\
  "\$(cat "$prompt_file")" \\
  < /dev/null > "$events_file"
EOF
}

cog::fn::codex_exec_run() {
  local mode="${1:-}"
  local effort="${2:-}"
  local prompt_file="${3:-}"
  local output_file="${4:-}"
  local events_file="${5:-}"
  local stderr_file="${6:-}"
  local codex_effort
  local prompt

  __cog_codex_require_cmd codex-session
  __cog_codex_require_arg "$mode" "mode" "cog::fn::codex_exec_run"
  __cog_codex_validate_mode "$mode"
  __cog_codex_require_arg "$effort" "effort" "cog::fn::codex_exec_run"
  __cog_codex_require_prompt "$prompt_file" "cog::fn::codex_exec_run"
  __cog_codex_require_arg "$output_file" "output_file" "cog::fn::codex_exec_run"
  __cog_codex_require_arg "$events_file" "events_file" "cog::fn::codex_exec_run"
  codex_effort="$(__cog_codex_map_effort "$effort")"
  prompt="$(__cog_codex_read_prompt "$prompt_file")"

  case "$mode" in
    native)
      __cog_codex_require_arg "$stderr_file" "stderr_file" "cog::fn::codex_exec_run"
      codex-session exec -c "model_reasoning_effort=$codex_effort" --sandbox read-only --json \
        --output-last-message "$output_file" \
        "$prompt" \
        </dev/null >"$events_file" 2>"$stderr_file"
      ;;
    fallback)
      __cog_codex_require_arg "$stderr_file" "stderr_file" "cog::fn::codex_exec_run"
      codex-session exec -c "model_reasoning_effort=$codex_effort" \
        -c 'sandbox_permissions=["disk-full-read-access"]' --json \
        --output-last-message "$output_file" \
        "$prompt" \
        </dev/null >"$events_file" 2>"$stderr_file"
      ;;
    quick-auto)
      codex-session --account auto exec -c "model_reasoning_effort=$codex_effort" --sandbox read-only --json \
        --output-last-message "$output_file" \
        "$prompt" \
        >"$events_file"
      ;;
    danger)
      if [[ -n $stderr_file ]]; then
        codex-session exec -c "model_reasoning_effort=$codex_effort" \
          --dangerously-bypass-approvals-and-sandbox --json \
          --output-last-message "$output_file" \
          "$prompt" \
          </dev/null >"$events_file" 2>"$stderr_file"
      else
        codex-session exec -c "model_reasoning_effort=$codex_effort" \
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
  local effort="${2:-}"
  local thread_id="${3:-}"
  local prompt_file="${4:-}"
  local output_file="${5:-}"
  local events_file="${6:-}"
  local stderr_file="${7:-}"
  local codex_effort
  local prompt

  __cog_codex_require_cmd codex-session
  __cog_codex_require_arg "$account" "account" "cog::fn::codex_resume_run"
  __cog_codex_require_arg "$effort" "effort" "cog::fn::codex_resume_run"
  __cog_codex_require_arg "$thread_id" "thread_id" "cog::fn::codex_resume_run"
  __cog_codex_require_prompt "$prompt_file" "cog::fn::codex_resume_run"
  __cog_codex_require_arg "$output_file" "output_file" "cog::fn::codex_resume_run"
  __cog_codex_require_arg "$events_file" "events_file" "cog::fn::codex_resume_run"
  codex_effort="$(__cog_codex_map_effort "$effort")"
  prompt="$(__cog_codex_read_prompt "$prompt_file")"

  if [[ -n $stderr_file ]]; then
    codex-session --account "$account" exec -c "model_reasoning_effort=$codex_effort" resume "$thread_id" \
      --dangerously-bypass-approvals-and-sandbox --json \
      --output-last-message "$output_file" \
      "$prompt" \
      </dev/null >"$events_file" 2>"$stderr_file"
  else
    codex-session --account "$account" exec -c "model_reasoning_effort=$codex_effort" resume "$thread_id" \
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

cog::fn::codex_orientation() {
  local mode="${1:-}"
  case "$mode" in
    read-only)
      cat <<'EOF'
=== STRICT READ-ONLY MODE ===
You are operating in READ-ONLY mode. This is a hard constraint.
PROHIBITED actions — any of these is a critical violation:
- Creating, modifying, or deleting any file
- Writing to any path on disk
- Running git commands (commit, add, push, reset, checkout, etc.)
- Executing any command that mutates system state
PERMITTED actions:
- Reading files, analyzing code, producing text output
- Running read-only shell commands (cat, grep, find, ls, etc.)
Produce your plan as text output only.
===
EOF
      ;;
    write)
      cat <<'EOF'
=== WRITE MODE ACTIVE ===
The prior READ-ONLY restriction no longer applies. You now have WRITE access.
PERMITTED actions:
- Creating, modifying, and deleting files within the workspace
- Running build/lint/test commands
STILL PROHIBITED:
- Running any git commands (commit, add, push, reset, checkout, etc.)
- Writing outside the workspace directory
Implement the plan below exactly. Report all files changed and any deviations.
===
EOF
      ;;
    *)
      cog::helpers::die "$EX_USAGE" "InvalidInput" \
        "invalid codex orientation mode" "mode: ${mode}" \
        "expected read-only or write" ""
      ;;
  esac
}

cog::fn::codex_known_statuses() {
  printf '%s\n' \
    ok empty-output resume-blocked resume-owner-missing account-mismatch \
    recovered-owner resume-no-rollout timeout-124 quota-75 sigterm nonzero
}

cog::fn::codex_explain_status() {
  local status="${1:-}"
  case "$status" in
    ok)
      cat <<'EOF'
ok: the call completed successfully with usable output. Proceed.
EOF
      ;;
    empty-output)
      cat <<'EOF'
empty-output: the process exited cleanly but produced no output-last-message
content. Treat as a failed run; inspect the events log and retry.
EOF
      ;;
    quota-75)
      cat <<'EOF'
quota-75 (AutoExhausted, exit 75): true depletion — accounts were tried and all
failed with 401/429, or no eligible account exists. Wait until the earliest
availability ETA in stderr, then retry. Only clear cooldowns when stderr shows
the block is cooldown-only; for pure quota-window exhaustion, wait for the reset.
EOF
      ;;
    resume-blocked)
      cat <<'EOF'
resume-blocked (ResumeBlocked, exit 75): exec resume can run only on the account
that owns the thread, and that owner is quota-limited. This is a quota state, not
a missing-thread error. Recover by waiting until the owner's reset time and
re-running the resume, OR start a fresh exec on an available account (new thread,
no continuity). The fresh-exec fallback is a deliberate continuity-losing choice.
EOF
      ;;
    resume-owner-missing)
      cat <<'EOF'
resume-owner-missing: the owning account/rollout for the thread is unavailable.
Start a fresh exec (new thread) rather than resuming.
EOF
      ;;
    account-mismatch)
      cat <<'EOF'
account-mismatch: --account was ignored for resume because the thread is owned by
a different account. The resume ran (or would run) on the owning account; do not
assume the requested account was used.
EOF
      ;;
    recovered-owner)
      cat <<'EOF'
recovered-owner: the wrapper recovered the owning account for the resume. The run
proceeded on the recovered owner; note the account actually used.
EOF
      ;;
    resume-no-rollout)
      cat <<'EOF'
resume-no-rollout: no rollout/thread found to resume (or a sandbox mismatch).
Start a fresh exec; do not retry the resume as-is.
EOF
      ;;
    timeout-124)
      cat <<'EOF'
timeout-124 (exit 124): the call hit the wrapper/orchestration timeout. Retry only
after reducing scope or increasing the timeout at the orchestration level.
EOF
      ;;
    sigterm)
      cat <<'EOF'
sigterm: the process was terminated by a signal. This is an interruption, not a
model failure — do not treat it as a quota or content error. Re-run when ready.
EOF
      ;;
    nonzero)
      cat <<'EOF'
nonzero: a non-zero exit that did not match a known quota/resume/timeout/signal
class. Inspect stderr and the events log to diagnose before retrying.
EOF
      ;;
    *)
      cog::helpers::die "$EX_DATAERR" "InvalidInput" \
        "unknown codex status" "status: ${status}" \
        "known statuses: $(cog::fn::codex_known_statuses | tr '\n' ' ')" \
        "pass one of the known status classes"
      ;;
  esac
}
