# shellcheck shell=bash
#
# Claude invocation source of truth:
# this file is the only layer that builds claude-session-rs command lines.
# Skills and commands above it must invoke Claude through
# `cog claude-runner run-exec`.
#
# Two provider facts shape everything below, and both were measured rather than
# read from documentation:
#
#   1. The wrapper owns no exec verb. Every token after its own flags reaches
#      `claude` verbatim, so the argv is a wrapper prefix plus a child suffix
#      separated by `--`, not a subcommand.
#   2. `claude` has no --output-last-message. The final message arrives inside
#      the event stream, so the runner extracts it and writes the output
#      artifact itself. That is the one place a cog runner produces an artifact
#      rather than letting the job write it.
#
# There is deliberately no stderr-prose classifier here. The wrapper execs its
# child, so wrapper and agent status ranges overlap and the only discriminator
# lives in provider-owned prose. ADR-0031 resolves that by checking
# preconditions before launch, which leaves the exit code meaning exactly one
# thing and makes prose parsing unnecessary.

__cog_claude_require_arg() {
  local value="${1:-}"
  local name="$2"
  local fn="$3"

  [[ -n $value ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing ${name}" "function: ${fn}" "expected <${name}>" ""
}

__cog_claude_require_prompt() {
  local prompt_file="${1:-}"
  local fn="$2"

  __cog_claude_require_arg "$prompt_file" "prompt_file" "$fn"
  [[ -r $prompt_file ]] || cog::helpers::die "$EX_NOINPUT" "InputUnreadable" \
    "prompt file is not readable" "path: ${prompt_file}" "" "check the prompt path"
}

cog::fn::claude_binary() {
  printf '%s\n' "${COG_CLAUDE_SESSION_BIN:-claude-session-rs}"
}

__cog_claude_validate_access() {
  case "${1:-}" in
    read-only | write)
      return 0
      ;;
    *)
      cog::helpers::die "$EX_USAGE" "InvalidInput" \
        "invalid claude access" "access: ${1:-}" \
        "expected read-only or write" ""
      ;;
  esac
}

# Validate a claude effort value against the `claude --effort` vocabulary.
# `none` is an omission, not a value: `claude --effort none` is rejected with a
# warning and the default effort is used silently, so `none` is dispatched by
# passing no --effort flag at all. Emitting nothing here is what expresses that.
__cog_claude_map_effort() {
  local effort="${1:-}"

  case "$effort" in
    none)
      return 0
      ;;
    low | medium | high | xhigh | max)
      printf '%s\n' "$effort"
      ;;
    *)
      cog::helpers::die "$EX_USAGE" "InvalidInput" \
        "invalid claude effort" "effort: ${effort}" \
        "expected none, low, medium, high, xhigh, or max" ""
      ;;
  esac
}

# Emit the access posture flags for the child `claude` invocation.
#
# read-only denies the mutating tools outright and never prompts. It is
# deliberately not --permission-mode plan: plan mode changes what the agent
# does, steering it toward ExitPlanMode instead of answering, which is wrong for
# a review or consult lane that must produce a result. It is deliberately not
# manual either, because a headless durable job has nobody to answer a prompt.
__cog_claude_access_args() {
  case "$1" in
    write) printf '%s\n' --dangerously-skip-permissions ;;
    *)
      printf '%s\n' --permission-mode
      printf '%s\n' dontAsk
      printf '%s\n' --disallowedTools
      printf '%s\n' "Edit,Write,NotebookEdit"
      ;;
  esac
}

__cog_claude_read_prompt() {
  local prompt_file="$1"
  cat "$prompt_file"
}

# Build the claude exec argv (program + args, no shell redirection) into the
# caller-named array. The durable-job launcher redirects stdin from /dev/null,
# stdout (the stream-json event stream) to the events file, and stderr to the
# stderr file. Unlike codex there is no --output-last-message: the output
# artifact is written afterwards by cog::fn::claude_extract_result.
cog::fn::claude_exec_argv() {
  local account="${1:-}"
  local profile="${2:-}"
  local access="${3:-}"
  local effort="${4:-}"
  local model="${5:-}"
  local prompt_file="${6:-}"
  local outvar="${7:-}"
  local claude_effort prompt bin
  local -a access_args=()

  __cog_claude_require_arg "$access" "access" "cog::fn::claude_exec_argv"
  __cog_claude_validate_access "$access"
  __cog_claude_require_arg "$effort" "effort" "cog::fn::claude_exec_argv"
  __cog_claude_require_prompt "$prompt_file" "cog::fn::claude_exec_argv"
  __cog_claude_require_arg "$outvar" "outvar" "cog::fn::claude_exec_argv"
  claude_effort="$(__cog_claude_map_effort "$effort")" || return $?
  prompt="$(__cog_claude_read_prompt "$prompt_file")"
  bin="$(cog::fn::claude_binary)"
  mapfile -t access_args < <(__cog_claude_access_args "$access")

  # shellcheck disable=SC2178 # Nameref to the caller's array; assigned as an array below.
  local -n __argv="$outvar"
  __argv=("$bin")
  [[ -n $account ]] && __argv+=(--account "$account")
  [[ -n $profile ]] && __argv+=(--profile "$profile")
  __argv+=(-- -p)
  [[ -n $model ]] && __argv+=(--model "$model")
  [[ -n $claude_effort ]] && __argv+=(--effort "$claude_effort")
  __argv+=(--output-format stream-json --verbose)
  __argv+=("${access_args[@]}")
  __argv+=("$prompt")
  return 0
}

# The argv equivalent above, rendered as a human-readable shell string for
# the engine_meta.command record.
cog::fn::claude_exec_command() {
  local account="${1:-}"
  local profile="${2:-}"
  local access="${3:-}"
  local effort="${4:-}"
  local model="${5:-}"
  local prompt_file="${6:-}"
  local events_file="${7:-}"
  local stderr_file="${8:-}"
  local claude_effort bin prefix child

  __cog_claude_require_arg "$access" "access" "cog::fn::claude_exec_command"
  __cog_claude_validate_access "$access"
  __cog_claude_require_arg "$effort" "effort" "cog::fn::claude_exec_command"
  __cog_claude_require_arg "$prompt_file" "prompt_file" "cog::fn::claude_exec_command"
  __cog_claude_require_arg "$events_file" "events_file" "cog::fn::claude_exec_command"
  claude_effort="$(__cog_claude_map_effort "$effort")" || return $?
  bin="$(cog::fn::claude_binary)"

  prefix="$bin"
  [[ -n $account ]] && prefix+=" --account ${account}"
  [[ -n $profile ]] && prefix+=" --profile ${profile}"

  child="-p"
  [[ -n $model ]] && child+=" --model ${model}"
  [[ -n $claude_effort ]] && child+=" --effort ${claude_effort}"
  child+=" --output-format stream-json --verbose"
  if [[ $access == write ]]; then
    child+=" --dangerously-skip-permissions"
  else
    child+=' --permission-mode dontAsk --disallowedTools "Edit,Write,NotebookEdit"'
  fi

  cat <<EOF
${prefix} -- ${child} \\
  "\$(cat "$prompt_file")" \\
  < /dev/null \\
  > "$events_file"${stderr_file:+ \\
  2> \"$stderr_file\"}
EOF
}

# Write the agent's final message into the output artifact.
#
# This is the one place a runner produces an artifact rather than letting the
# job write it: claude emits its result inside the stream, so finalize reads the
# terminal result envelope and materializes the file the caller was promised.
# Reads only durable artifacts, so it works even when the launching observer
# died. Returns non-zero and writes nothing when no result envelope is present.
cog::fn::claude_extract_result() {
  local events_file="${1:-}"
  local output_file="${2:-}"
  local result

  [[ -r $events_file ]] || return 1
  result="$(jq -r 'select(.type == "result") | .result // empty' "$events_file" 2>/dev/null | tail -1 || true)"
  [[ -n $result ]] || return 1
  printf '%s\n' "$result" >"$output_file"
}

# The session id, read from the event stream. This is the claude analogue of a
# codex thread id: the identity a later resume would need. Captured now because
# only the stream carries it and the stream is durable.
cog::fn::claude_extract_session() {
  local events_file="${1:-}"
  [[ -r $events_file ]] || return 0
  jq -r 'select(.session_id) | .session_id' "$events_file" 2>/dev/null | tail -1 || true
}

# Classify a finished job from its exit code and its output artifact alone.
#
# Deliberately shorter than the codex classifier, which reads stderr prose to
# separate launch failures from agent failures. Here the preflight already ruled
# out every precondition failure before the job existed, so a status that
# arrives is the agent's and the exit code means one thing.
cog::fn::claude_classify_status() {
  local exit_code="${1:-}"
  local output_file="${2:-}"

  case "$exit_code" in
    0)
      [[ -s $output_file ]] && printf '%s\n' "ok" || printf '%s\n' "empty-output"
      ;;
    124) printf '%s\n' "timeout-124" ;;
    130 | 137 | 143) printf '%s\n' "sigterm" ;;
    *) printf '%s\n' "nonzero" ;;
  esac
}

# Best-effort status when the exit code could not be recovered (the detached
# wrapper was lost before recording it — host reboot, OOM kill). Reads only
# durable artifacts: the terminal stream envelope and the output artifact.
cog::fn::claude_reconstruct_status() {
  local events_file="${1:-}"
  local output_file="${2:-}"
  local last=""

  if [[ ! -s $output_file ]]; then
    printf '%s\n' "empty-output"
    return 0
  fi
  if [[ -r $events_file ]]; then
    last="$(jq -r 'select(.type) | .type' "$events_file" 2>/dev/null | tail -1 || true)"
  fi
  case "$last" in
    result) printf '%s\n' "ok" ;;
    error) printf '%s\n' "nonzero" ;;
    *) printf '%s\n' "sigterm" ;;
  esac
}
