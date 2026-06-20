# shellcheck shell=bash

__cog_rundir_require_arg() {
  local value="${1:-}"
  local name="$2"
  local fn="$3"

  [[ -n $value ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing ${name}" "function: ${fn}" "expected <${name}>" ""
}

__cog_rundir_mkdir() {
  local path="$1"
  local context="$2"

  mkdir -p -- "$path" || cog::helpers::die "$EX_IOERR" "TempDirCreateFailed" \
    "could not create directory" "path: ${path}" "$context" \
    "check permissions and retry"
}

cog::fn::rundir_base() {
  local subdir="${1:-cog/runs}"
  printf '%s/%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}" "$subdir"
}

cog::fn::rundir_create() {
  local prefix="${1:-}"
  __cog_rundir_require_arg "$prefix" "prefix" "cog::fn::rundir_create"

  local base run_dir
  base="$(cog::fn::rundir_base)"
  __cog_rundir_mkdir "$base" "creating run base"
  run_dir="${base}/${prefix}-$(date -u +%Y%m%dT%H%M%S)-$$"
  __cog_rundir_mkdir "$run_dir" "creating run directory"
  printf '%s\n' "$run_dir"
}

cog::fn::rundir_path() {
  local run_dir="${1:-}"
  local name="${2:-}"

  __cog_rundir_require_arg "$run_dir" "run_dir" "cog::fn::rundir_path"
  __cog_rundir_require_arg "$name" "name" "cog::fn::rundir_path"
  printf '%s/%s\n' "$run_dir" "$name"
}

cog::fn::rundir_lock_dir() {
  printf '%s\n' "${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/cog/runs}"
}

cog::fn::rundir_lock_name() {
  printf '%s\n' "prex-active"
}

cog::fn::rundir_lock_path() {
  local run_dir="${1:-}"
  local name="${2:-}"
  local lock_dir

  __cog_rundir_require_arg "$run_dir" "run_dir" "cog::fn::rundir_lock_path"
  [[ -n $name ]] || name="$(cog::fn::rundir_lock_name)"
  lock_dir="$(cog::fn::rundir_lock_dir)"
  printf '%s/%s-%s.lock\n' "$lock_dir" "$name" "${run_dir##*-}"
}

__cog_rundir_write_lock() {
  local tmp="$1"
  local run_dir="$2"
  local owner_pid="$3"

  printf '%s\n%s\n' "$run_dir" "$owner_pid" >"$tmp" || cog::helpers::die "$EX_IOERR" "RunDirLockWriteFailed" \
    "could not write run lock" "path: ${tmp}" "" "check runtime directory permissions"
}

cog::fn::rundir_lock_acquire() {
  local run_dir="${1:-}"
  local owner_pid="${2:-}"
  local lock_file="${3:-}"
  local lock_dir tmp

  __cog_rundir_require_arg "$run_dir" "run_dir" "cog::fn::rundir_lock_acquire"
  __cog_rundir_require_arg "$owner_pid" "owner_pid" "cog::fn::rundir_lock_acquire"
  [[ -n $lock_file ]] || lock_file="$(cog::fn::rundir_lock_path "$run_dir")"
  lock_dir="$(dirname -- "$lock_file")"
  __cog_rundir_mkdir "$lock_dir" "creating lock directory"
  tmp="${lock_file}.tmp.$$"
  __cog_rundir_write_lock "$tmp" "$run_dir" "$owner_pid"

  if ! ln -- "$tmp" "$lock_file" 2>/dev/null; then
    rm -f -- "$tmp"
    cog::helpers::die "$EX_IOERR" "RunDirLockExists" \
      "run lock already exists" "path: ${lock_file}" "" \
      "wait for the active run to finish or remove a stale lock"
  fi

  rm -f -- "$tmp"
  printf '%s\n' "$lock_file"
}

cog::fn::rundir_lock_release() {
  local lock_file="${1:-}"
  __cog_rundir_require_arg "$lock_file" "lock_file" "cog::fn::rundir_lock_release"
  rm -f -- "$lock_file"
}

cog::fn::rundir_snapshot() {
  local run_dir="${1:-}"
  local out="${2:-}"

  __cog_rundir_require_arg "$run_dir" "run_dir" "cog::fn::rundir_snapshot"
  __cog_rundir_require_arg "$out" "out.snap" "cog::fn::rundir_snapshot"
  [[ -d $run_dir ]] || cog::helpers::die "$EX_NOINPUT" "InputNotFound" \
    "run directory not found" "path: ${run_dir}" "" "check the run directory"

  find "$run_dir" -type f -printf '%p %T@\n' 2>/dev/null | sort >"$out" \
    || cog::helpers::die "$EX_IOERR" "RunDirSnapshotWriteFailed" \
      "could not write run directory snapshot" "path: ${out}" "" \
      "check output path permissions"
}

cog::fn::rundir_snapshot_diff() {
  local pre="${1:-}"
  local post="${2:-}"
  local out="${3:-}"

  __cog_rundir_require_arg "$pre" "pre.snap" "cog::fn::rundir_snapshot_diff"
  __cog_rundir_require_arg "$post" "post.snap" "cog::fn::rundir_snapshot_diff"
  __cog_rundir_require_arg "$out" "out.diff" "cog::fn::rundir_snapshot_diff"
  diff -u "$pre" "$post" >"$out" || true
}

cog::fn::rundir_snapshot_children() {
  local prefix="${1:-}"
  local out="${2:-}"
  local base="${3:-}"

  __cog_rundir_require_arg "$prefix" "prefix" "cog::fn::rundir_snapshot_children"
  __cog_rundir_require_arg "$out" "out.snap" "cog::fn::rundir_snapshot_children"
  [[ -n $base ]] || base="$(cog::fn::rundir_base)"
  __cog_rundir_mkdir "$base" "creating run base"

  # Pin LC_ALL=C so the snapshot collation is deterministic regardless of the
  # caller's locale; rundir_locate_child's comm depends on a stable, matching order.
  find "$base" -maxdepth 1 -type d -name "${prefix}-*" -printf '%p\n' 2>/dev/null \
    | LC_ALL=C sort >"$out" \
    || cog::helpers::die "$EX_IOERR" "RunDirSnapshotWriteFailed" \
      "could not write child run directory snapshot" "path: ${out}" "" \
      "check output path permissions"
}

cog::fn::rundir_locate_child() {
  local pre="${1:-}"
  local post="${2:-}"
  local new count

  __cog_rundir_require_arg "$pre" "pre.snap" "cog::fn::rundir_locate_child"
  __cog_rundir_require_arg "$post" "post.snap" "cog::fn::rundir_locate_child"
  [[ -f $pre ]] || cog::fn::error_raise "InputNotFound" \
    "pre snapshot not found" "path: ${pre}" "" "check the snapshot path"
  [[ -f $post ]] || cog::fn::error_raise "InputNotFound" \
    "post snapshot not found" "path: ${post}" "" "check the snapshot path"

  new="$(LC_ALL=C comm -13 "$pre" "$post")"
  count="$(printf '%s\n' "$new" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  if [[ $count == 0 ]]; then
    cog::fn::error_raise "InputNotFound" \
      "no new child run directory" "pre: ${pre}, post: ${post}" \
      "delegation produced no review-loop-* directory" "confirm the delegated call ran"
  fi
  if [[ $count != 1 ]]; then
    cog::fn::error_raise "InvalidInput" \
      "ambiguous child run directory" "found: ${count}" \
      "multiple new review-loop-* dirs between snapshots; cannot pick deterministically" \
      "re-run with isolated snapshots"
  fi

  printf '%s\n' "$new"
}

cog::fn::rundir_require_file() {
  local path="${1:-}"
  local label="${2:-file}"

  __cog_rundir_require_arg "$path" "path" "cog::fn::rundir_require_file"
  [[ -f $path && -r $path && -s $path ]] || cog::helpers::die "$EX_NOINPUT" "InputUnreadable" \
    "${label} is missing or empty" "path: ${path}" "" "check the file and retry"
}
