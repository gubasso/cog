# shellcheck shell=bash
#
# Generic durable long-running job engine.
#
# `cog` owns long-running processes instead of the caller's foreground tool
# call. A job is launched DETACHED in its own session/process group (via
# `setsid`) so a tool-host timeout that SIGTERMs the launching process tree
# never reaches it. All job state lives in an atomically-updated JSON file, so
# an observer that is killed mid-run loses nothing: `finalize` reconstructs the
# outcome purely from durable artifacts (exit-code file, done-marker, captured
# stdout/stderr).
#
# Duration is never a signal: `wait` returns inside a bounded wall-clock window
# and a still-`running` return is success, not failure. Callers poll again.
#
# This engine is engine-agnostic. `cog codex-runner` is one strategy that builds
# a Codex argv and layers Codex classification on top; `cog longrun` exposes the
# generic surface for wrapping any one-off command in the same protocol.

__cog_longrun_state_self_check='(.schema=="cog.longrun.v1") and (.label|type=="string") and (.state|type=="string") and (.pid|type=="number") and (.pgid|type=="number") and (.artifacts|type=="object")'

cog::fn::longrun::state_self_check() {
  printf '%s\n' "$__cog_longrun_state_self_check"
}

# GR4 single source of truth: map a finalize disposition to its process exit
# code so callers branch on $? without parsing the body. Identical for every
# durable-job command. `ok` -> 0, `running` -> EX_TEMPFAIL (retry), anything
# else (failed/cancelled/unrecoverable-lost) -> 1.
cog::fn::longrun::signal_code() {
  case "${1:-}" in
    ok) printf '%s\n' "${EX_OK:-0}" ;;
    running) printf '%s\n' "${EX_TEMPFAIL:-75}" ;;
    *) printf '%s\n' 1 ;;
  esac
}

__cog_longrun_require_arg() {
  local value="${1:-}"
  local name="$2"
  local fn="$3"

  [[ -n $value ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing ${name}" "function: ${fn}" "expected <${name}>" ""
}

__cog_longrun_require_jq() {
  __have jq || cog::fn::error_raise "MissingRequirement" \
    "required command not found" "command: jq" "" "install jq and retry"
}

__cog_longrun_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Host boot id pins pid/pgid identity to this boot, defeating stale-pid reuse:
# after a reboot the recorded pid may belong to an unrelated process, so we
# never trust (let alone signal) a pid whose recorded boot id no longer matches.
# Empty string on platforms without the proc entry (liveness-only fallback).
cog::fn::longrun::boot_id() {
  local path=/proc/sys/kernel/random/boot_id
  if [[ -r $path ]]; then
    tr -d '[:space:]' <"$path" 2>/dev/null || true
  fi
}

# True when any process in the group is still alive. A negative pid targets the
# whole process group; signal 0 only probes, it delivers nothing.
cog::fn::longrun::is_alive() {
  local pgid="${1:-}"
  [[ $pgid =~ ^[0-9]+$ && $pgid -gt 1 ]] || return 1
  kill -0 -"$pgid" 2>/dev/null
}

__cog_longrun_field() {
  local state_file="$1" filter="$2"
  jq -r "$filter" "$state_file" 2>/dev/null || true
}

# Atomic, self-checked state write (mktemp in target dir -> validate -> mv).
__cog_longrun_write_state() {
  local state_file="$1" json="$2"
  local dir tmp
  dir="$(dirname -- "$state_file")"
  mkdir -p -- "$dir" 2>/dev/null || true
  tmp="$(mktemp "${state_file}.tmp.XXXXXX")" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create longrun state temp file" "path: ${state_file}" "" "check permissions"
  printf '%s\n' "$json" >"$tmp" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write longrun state" "path: ${tmp}" "" "check permissions"
  if ! jq -e "$__cog_longrun_state_self_check" "$tmp" >/dev/null 2>&1; then
    rm -f -- "$tmp"
    cog::fn::error_raise "InvalidJsonOutput" \
      "wrote invalid longrun state" "path: ${state_file}" \
      "fragment failed self-check" "report this cog bug"
  fi
  mv -f -- "$tmp" "$state_file" || cog::fn::error_raise "JsonWriteFailed" \
    "could not replace longrun state" "path: ${state_file}" "" "check permissions"
}

cog::fn::longrun::state_read() {
  local state_file="${1:-}"
  __cog_longrun_require_arg "$state_file" "state_file" "cog::fn::longrun::state_read"
  [[ -r $state_file ]] || cog::fn::error_raise "InputNotFound" \
    "longrun state file not found" "path: ${state_file}" "" "check the --state path"
  cat -- "$state_file"
}

# Apply a jq transform to the state file and write the result atomically.
__cog_longrun_update() {
  local state_file="$1"
  local filter="$2"
  shift 2
  local json
  json="$(jq -c "$@" "$filter" "$state_file")" || cog::fn::error_raise "InvalidJsonOutput" \
    "could not transform longrun state" "path: ${state_file}" "filter: ${filter}" "report this cog bug"
  __cog_longrun_write_state "$state_file" "$json"
}

cog::fn::longrun::start() {
  __cog_longrun_require_jq
  local state_file="" label="" cwd="" stdout_file="" stderr_file="" output_file="" engine="generic" engine_meta="{}"
  local -a cmd=()
  while (($# > 0)); do
    case "$1" in
      --state)
        state_file="${2:-}"
        shift 2
        ;;
      --label)
        label="${2:-}"
        shift 2
        ;;
      --cwd)
        cwd="${2:-}"
        shift 2
        ;;
      --stdout)
        stdout_file="${2:-}"
        shift 2
        ;;
      --stderr)
        stderr_file="${2:-}"
        shift 2
        ;;
      --output)
        output_file="${2:-}"
        shift 2
        ;;
      --engine)
        engine="${2:-}"
        shift 2
        ;;
      --engine-meta)
        engine_meta="${2:-}"
        shift 2
        ;;
      --)
        shift
        cmd=("$@")
        break
        ;;
      *) cog::fn::error_raise "InvalidInput" "invalid longrun start argument" "argument: $1" "" "place the command after --" ;;
    esac
  done

  __cog_longrun_require_arg "$state_file" "--state" "cog::fn::longrun::start"
  __cog_longrun_require_arg "$label" "--label" "cog::fn::longrun::start"
  [[ ${#cmd[@]} -ge 1 ]] || cog::fn::error_raise "MissingArgument" \
    "missing command to launch" "usage: cog::fn::longrun::start --state F --label L -- <cmd> [args...]" "" ""
  [[ -n $engine_meta ]] || engine_meta="{}"
  jq -e . >/dev/null 2>&1 <<<"$engine_meta" || cog::fn::error_raise "InvalidJsonInput" \
    "engine-meta is not valid JSON" "value: ${engine_meta}" "" "pass a JSON object"

  local run_dir
  run_dir="$(dirname -- "$state_file")"
  mkdir -p -- "$run_dir" 2>/dev/null || true
  [[ -n $cwd ]] || cwd="$PWD"
  [[ -n $stdout_file ]] || stdout_file="${run_dir}/${label}.stdout.log"
  [[ -n $stderr_file ]] || stderr_file="${run_dir}/${label}.stderr.log"
  [[ -n $output_file ]] || output_file="$stdout_file"

  local pidmeta exit_file done_marker
  pidmeta="${run_dir}/${label}.pidmeta"
  exit_file="${run_dir}/${label}.exit"
  done_marker="${run_dir}/${label}.done"
  rm -f -- "$pidmeta" "$exit_file" "$done_marker"

  local boot_id started
  boot_id="$(cog::fn::longrun::boot_id)"
  started="$(__cog_longrun_now)"

  # Launch detached: setsid gives the wrapper its own session (pid == pgid), so
  # a SIGTERM to the launching process tree cannot reach it. The wrapper records
  # its own pid (the durable pgid), runs the command, then writes the exit code
  # and the done-marker LAST — so "marker present" implies the exit code is
  # already durable. The inner stdio is fully redirected to the artifact files,
  # so the detached job needs no controlling terminal.
  # shellcheck disable=SC2016 # The single-quoted body is the DETACHED shell's own program; its $$/$@/$COG_LR_* must expand there, not here.
  COG_LR_PIDMETA="$pidmeta" \
    COG_LR_EXIT="$exit_file" \
    COG_LR_DONE="$done_marker" \
    COG_LR_STDOUT="$stdout_file" \
    COG_LR_STDERR="$stderr_file" \
    COG_LR_CWD="$cwd" \
    setsid bash -c '
      printf "%s\n" "$$" >"$COG_LR_PIDMETA.tmp" && mv -f "$COG_LR_PIDMETA.tmp" "$COG_LR_PIDMETA"
      cd "$COG_LR_CWD" 2>/dev/null || true
      "$@" </dev/null >>"$COG_LR_STDOUT" 2>>"$COG_LR_STDERR"
      rc=$?
      printf "%s\n" "$rc" >"$COG_LR_EXIT.tmp" && mv -f "$COG_LR_EXIT.tmp" "$COG_LR_EXIT"
      : >"$COG_LR_DONE"
    ' _ "${cmd[@]}" >/dev/null 2>&1 &
  local launcher_pid=$!
  disown "$launcher_pid" 2>/dev/null || true

  # The leader pid (== pgid) is whatever the wrapper recorded as $$, robust to
  # whether setsid forked. Read it back with a short bounded poll.
  local pid="" tries=0
  while ((tries < 250)); do
    if [[ -s $pidmeta ]]; then
      pid="$(tr -d '[:space:]' <"$pidmeta" 2>/dev/null || true)"
      [[ $pid =~ ^[0-9]+$ ]] && break
      pid=""
    fi
    sleep 0.02
    tries=$((tries + 1))
  done
  [[ $pid =~ ^[0-9]+$ ]] || pid="$launcher_pid"
  rm -f -- "$pidmeta"

  # Serialize argv to a JSON array via --arg (NUL-safe and newline-safe: a
  # prompt element carries embedded newlines, so per-line/NUL tricks are wrong).
  local cmd_json='[]' el
  for el in "${cmd[@]}"; do
    cmd_json="$(jq -c --arg e "$el" '. + [$e]' <<<"$cmd_json")"
  done

  local json
  json="$(jq -cn \
    --arg schema cog.longrun.v1 \
    --arg label "$label" \
    --arg state running \
    --argjson cmd "$cmd_json" \
    --arg cwd "$cwd" \
    --argjson pid "$pid" \
    --argjson pgid "$pid" \
    --arg boot_id "$boot_id" \
    --arg started_at "$started" \
    --arg stdout "$stdout_file" \
    --arg stderr "$stderr_file" \
    --arg output "$output_file" \
    --arg exit_code_file "$exit_file" \
    --arg done_marker "$done_marker" \
    --arg engine "$engine" \
    --argjson engine_meta "$engine_meta" \
    '{schema: $schema, label: $label, state: $state, cmd: $cmd, cwd: $cwd,
      pid: $pid, pgid: $pgid, host_boot_id: $boot_id,
      started_at: $started_at, exited_at: null, finalized_at: null,
      exit_code: null, exit_source: null,
      artifacts: {stdout: $stdout, stderr: $stderr, output: $output,
                  exit_code_file: $exit_code_file, done_marker: $done_marker},
      engine: $engine, engine_meta: $engine_meta}')"
  __cog_longrun_write_state "$state_file" "$json"
}

# Refresh the durable lifecycle fact and persist any transition. Never judges
# duration; only records observable facts (done-marker, group liveness, reboot).
# Echoes the current state. Terminal states (finalized-*, cancelled, lost) are
# immutable here; only finalize/cancel write them.
cog::fn::longrun::observe() {
  local state_file="${1:-}"
  __cog_longrun_require_arg "$state_file" "state_file" "cog::fn::longrun::observe"
  [[ -r $state_file ]] || cog::fn::error_raise "InputNotFound" \
    "longrun state file not found" "path: ${state_file}" "" "check the --state path"

  local state
  state="$(__cog_longrun_field "$state_file" '.state')"
  case "$state" in
    finalized-ok | finalized-failed | cancelled | lost)
      printf '%s\n' "$state"
      return 0
      ;;
  esac

  local done_marker pgid recorded_boot current_boot new_state="$state"
  done_marker="$(__cog_longrun_field "$state_file" '.artifacts.done_marker')"
  pgid="$(__cog_longrun_field "$state_file" '.pgid')"
  recorded_boot="$(__cog_longrun_field "$state_file" '.host_boot_id')"
  current_boot="$(cog::fn::longrun::boot_id)"

  if [[ -n $done_marker && -e $done_marker ]]; then
    new_state="exited"
  elif [[ -n $recorded_boot && -n $current_boot && $recorded_boot != "$current_boot" ]]; then
    new_state="lost"
  elif cog::fn::longrun::is_alive "$pgid"; then
    new_state="running"
  else
    new_state="lost"
  fi

  if [[ $new_state != "$state" ]]; then
    if [[ $new_state == exited ]]; then
      # shellcheck disable=SC2016 # jq filter; $s/$t are jq vars bound via --arg, not shell expansion.
      __cog_longrun_update "$state_file" '.state=$s | .exited_at=$t' \
        --arg s "$new_state" --arg t "$(__cog_longrun_now)"
    else
      # shellcheck disable=SC2016 # jq filter; $s is a jq var bound via --arg.
      __cog_longrun_update "$state_file" '.state=$s' --arg s "$new_state"
    fi
  fi
  printf '%s\n' "$new_state"
}

# Resolve the terminal outcome from durable artifacts only. Echoes a JSON
# object {state, exit_code, exit_source}. exit_code is null when it cannot be
# recovered. The exit-code file wins over liveness: if it exists the job
# exited (state=exited) even if the done-marker write or the wrapper was lost.
cog::fn::longrun::resolve_exit() {
  local state_file="${1:-}"
  __cog_longrun_require_arg "$state_file" "state_file" "cog::fn::longrun::resolve_exit"
  local state exit_file exit_code="" exit_source=""
  state="$(cog::fn::longrun::observe "$state_file")"
  exit_file="$(__cog_longrun_field "$state_file" '.artifacts.exit_code_file')"

  if [[ -n $exit_file && -s $exit_file ]]; then
    exit_code="$(tr -d '[:space:]' <"$exit_file" 2>/dev/null || true)"
    [[ $exit_code =~ ^-?[0-9]+$ ]] || exit_code=""
    if [[ -n $exit_code ]]; then
      exit_source="wrapper"
      case "$state" in running | lost) state="exited" ;; esac
    fi
  fi
  if [[ -z $exit_code && $state == lost ]]; then
    exit_source="reconstructed"
  fi

  jq -cn \
    --arg state "$state" \
    --arg exit_source "$exit_source" \
    --argjson exit_code "${exit_code:-null}" \
    '{state: $state, exit_code: $exit_code,
      exit_source: (if $exit_source == "" then null else $exit_source end)}'
}

# Persist a terminal state with its exit code/source and finalized_at.
cog::fn::longrun::persist_final() {
  local state_file="$1" final_state="$2" exit_code="${3:-}" exit_source="${4:-}"
  __cog_longrun_require_arg "$state_file" "state_file" "cog::fn::longrun::persist_final"
  __cog_longrun_require_arg "$final_state" "final_state" "cog::fn::longrun::persist_final"
  # shellcheck disable=SC2016 # jq filter; $s/$c/$src/$t are jq vars bound via --arg/--argjson.
  __cog_longrun_update "$state_file" \
    '.state=$s | .exit_code=$c | .exit_source=(if $src=="" then null else $src end) | .finalized_at=$t' \
    --arg s "$final_state" \
    --argjson c "${exit_code:-null}" \
    --arg src "$exit_source" \
    --arg t "$(__cog_longrun_now)"
  cat -- "$state_file"
}

# Bounded poll. Returns as soon as the job leaves `running`, OR when max_wall
# seconds elapse — whichever first. A still-`running` echo is normal: the caller
# simply waits again. The call therefore always returns inside max_wall,
# independent of how long the job runs.
cog::fn::longrun::wait() {
  local state_file="${1:-}" max_wall="${2:-300}" poll="${3:-3}"
  __cog_longrun_require_arg "$state_file" "state_file" "cog::fn::longrun::wait"
  [[ $max_wall =~ ^[0-9]+$ ]] || max_wall=300
  [[ $poll =~ ^[0-9]+$ && $poll -ge 1 ]] || poll=3
  ((poll > max_wall)) && poll=$max_wall
  ((poll < 1)) && poll=1

  local start=$SECONDS state
  while :; do
    state="$(cog::fn::longrun::observe "$state_file")"
    [[ $state == running ]] || break
    ((SECONDS - start >= max_wall)) && break
    sleep "$poll"
  done
  printf '%s\n' "$state"
}

# Terminate the whole process group, then escalate to KILL after a short grace
# if it survives. Only signals a group we can prove is ours (boot-id match), so
# a reused pid is never targeted. Persists state=cancelled.
cog::fn::longrun::cancel() {
  local state_file="${1:-}" signal="${2:-TERM}"
  __cog_longrun_require_arg "$state_file" "state_file" "cog::fn::longrun::cancel"
  local state
  state="$(cog::fn::longrun::observe "$state_file")"
  case "$state" in
    running) ;;
    *)
      cat -- "$state_file"
      return 0
      ;;
  esac

  local pgid recorded_boot current_boot
  pgid="$(__cog_longrun_field "$state_file" '.pgid')"
  recorded_boot="$(__cog_longrun_field "$state_file" '.host_boot_id')"
  current_boot="$(cog::fn::longrun::boot_id)"
  if [[ -n $recorded_boot && -n $current_boot && $recorded_boot != "$current_boot" ]]; then
    cog::fn::longrun::persist_final "$state_file" "lost" "" "reconstructed" >/dev/null
    cat -- "$state_file"
    return 0
  fi

  if cog::fn::longrun::is_alive "$pgid"; then
    kill -"$signal" -"$pgid" 2>/dev/null || true
    if [[ $signal == TERM ]]; then
      local tries=0
      while ((tries < 50)) && cog::fn::longrun::is_alive "$pgid"; do
        sleep 0.1
        tries=$((tries + 1))
      done
      cog::fn::longrun::is_alive "$pgid" && kill -KILL -"$pgid" 2>/dev/null || true
    fi
  fi
  cog::fn::longrun::persist_final "$state_file" "cancelled" "" "cancelled" >/dev/null
  cat -- "$state_file"
}

# Enrich the live state with informational-only fields. idle_seconds is the
# staleness signal (seconds since the freshest artifact changed); it is reported
# for humans, never used to gate a decision.
cog::fn::longrun::status_json() {
  local state_file="${1:-}"
  __cog_longrun_require_arg "$state_file" "state_file" "cog::fn::longrun::status_json"
  local state pgid alive=false idle="null" newest=0 now f mtime
  state="$(cog::fn::longrun::observe "$state_file")"
  pgid="$(__cog_longrun_field "$state_file" '.pgid')"
  cog::fn::longrun::is_alive "$pgid" && alive=true
  now="$(date +%s)"
  for f in stdout stderr output; do
    local path
    path="$(__cog_longrun_field "$state_file" ".artifacts.${f}")"
    [[ -n $path && -e $path ]] || continue
    mtime="$(stat -c %Y -- "$path" 2>/dev/null || echo 0)"
    ((mtime > newest)) && newest=$mtime
  done
  ((newest > 0)) && idle=$((now - newest))

  jq -c \
    --argjson alive "$alive" \
    --argjson idle_seconds "$idle" \
    '. + {alive: $alive, idle_seconds: $idle_seconds}' "$state_file"
}

# Enumerate longrun state files under a base, refreshing each. Echoes a JSON
# array of {state_file, label, state, alive, started_at}.
cog::fn::longrun::list() {
  local base="${1:-}"
  [[ -n $base ]] || base="$(cog::fn::rundir_base)"
  local -a rows=()
  local f state label started pgid alive
  while IFS= read -r f; do
    [[ -n $f ]] || continue
    jq -e "$__cog_longrun_state_self_check" "$f" >/dev/null 2>&1 || continue
    state="$(cog::fn::longrun::observe "$f")"
    label="$(__cog_longrun_field "$f" '.label')"
    started="$(__cog_longrun_field "$f" '.started_at')"
    pgid="$(__cog_longrun_field "$f" '.pgid')"
    alive=false
    cog::fn::longrun::is_alive "$pgid" && alive=true
    rows+=("$(jq -cn --arg sf "$f" --arg label "$label" --arg state "$state" \
      --arg started "$started" --argjson alive "$alive" \
      '{state_file: $sf, label: $label, state: $state, started_at: $started, alive: $alive}')")
  done < <(find "$base" -type f -name '*.longrun.json' 2>/dev/null | sort)

  if ((${#rows[@]} == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "${rows[@]}" | jq -cs '.'
  fi
}
