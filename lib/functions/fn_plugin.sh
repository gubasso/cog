# shellcheck shell=bash
#
# External command plugins. Cog inspects and executes `cog-<name>` executables;
# it never installs, downloads, updates, or catalogues them. The published
# contract is docs/reference/plugin-protocol.md.
#
# Nothing in this file dies on plugin input. A malformed, hostile, or hanging
# plugin degrades to a state token, because a failed probe must never stop an
# otherwise valid plugin from running.

# Structural constants. These are also published in data/plugin-protocol/, which
# is the document a third party reads; test/unit/fn_plugin.bats pins the two
# copies together. They are literals here so that dispatching a plugin costs no
# YAML read and carries no jq/yq dependency — the same mirrored-surface-plus-
# drift-test shape the help, completion, and man surfaces already use.
__COG_PLUGIN_PROTOCOL_VERSION=1
__COG_PLUGIN_PREFIX="cog-"
__COG_PLUGIN_RESERVED_SUBCOMMAND="cog-plugin-metadata"
__COG_PLUGIN_NAME_PATTERN='^[a-z][a-z0-9_-]*$'
__COG_PLUGIN_PROBE_TIMEOUT=2
__COG_PLUGIN_PROBE_CAP=65536
# The grace interval between the TERM `timeout` sends at the deadline and the
# KILL it sends after it. Not a protocol constant and deliberately not published
# in data/plugin-protocol/: a plugin is promised only that it must answer within
# probe_timeout_seconds, and how cog enforces that is cog's business. TERM alone
# is not enforcement — a plugin that traps or blocks it would keep `list`, `info`,
# and `validate` waiting forever, which is exactly the third-party bug this file
# promises never to turn into a cog outage.
__COG_PLUGIN_PROBE_KILL_AFTER=1

# Order matters: `validate` reports checks in this order, and the first failure
# short-circuits the checks that depend on it to `skip`.
__COG_PLUGIN_CHECKS=(
  executable
  regular_file
  name_matches_filename
  no_firstparty_collision
  metadata_exit
  metadata_json
  metadata_required_fields
  protocol_supported
  probe_within_timeout
  probe_within_cap
  probe_side_effect_free
)

cog::fn::plugin_protocol_version() {
  printf '%s\n' "$__COG_PLUGIN_PROTOCOL_VERSION"
}

cog::fn::plugin_probe_timeout() {
  printf '%s\n' "$__COG_PLUGIN_PROBE_TIMEOUT"
}

cog::fn::plugin_probe_cap() {
  printf '%s\n' "$__COG_PLUGIN_PROBE_CAP"
}

cog::fn::plugin_reserved_subcommand() {
  printf '%s\n' "$__COG_PLUGIN_RESERVED_SUBCOMMAND"
}

cog::fn::plugin_check_names() {
  printf '%s\n' "${__COG_PLUGIN_CHECKS[@]}"
}

cog::fn::plugin_name_valid() {
  local name="${1:-}"
  [[ -n $name ]] || return 1
  [[ $name =~ $__COG_PLUGIN_NAME_PATTERN ]]
}

# Absolute path of <path>, with its directory normalized. Does not follow the
# final component, so a dangling symlink still yields a usable path to report.
__cog_plugin_abs() {
  local path="$1" dir base resolved
  dir="${path%/*}"
  base="${path##*/}"
  [[ $dir != "$path" ]] || dir="."
  [[ -n $dir ]] || dir="/"
  resolved="$(cd -P "$dir" 2>/dev/null && pwd)" || return 1
  [[ $resolved == */ ]] && resolved="${resolved%/}"
  printf '%s\n' "${resolved}/${base}"
}

# Follow symlinks to the final target, absolutely. Returns non-zero when the
# chain dangles or loops, which is what makes a dangling symlink a state token
# rather than a crash.
__cog_plugin_realpath() {
  local path="$1" dir hops=0
  path="$(__cog_plugin_abs "$path")" || return 1
  while [[ -L $path ]]; do
    ((hops += 1))
    ((hops <= 40)) || return 1
    dir="${path%/*}"
    path="$(readlink "$path")" || return 1
    [[ $path == /* ]] || path="${dir}/${path}"
    path="$(__cog_plugin_abs "$path")" || return 1
  done
  [[ -e $path ]] || return 1
  printf '%s\n' "$path"
}

# True when a first-party command module owns <name>.
__cog_plugin_firstparty() {
  local name="${1:-}"
  local derived="${name//-/_}"
  [[ -r "${LIB_DIR}/commands/cmd_${derived}.sh" ]]
}

# The search path, in resolution order — $COG_PLUGIN_DIR first, then $PATH —
# appended to the array named by <array-name>.
#
# Split on ':' in the shell rather than by translating ':' to newline. A
# translation destroys the evidence the caller needs: a component containing a
# newline would arrive as two ordinary-looking directories, and the
# newline rejection in each caller could never fire, so cog would search a
# directory $PATH never named. Splitting here keeps each component intact and
# leaves that rejection meaningful.
#
# An empty $PATH component means the current directory to execvp, and cog
# deliberately does not follow it there: a `cog-<name>` dropped in any
# directory the user happens to cd into would otherwise become a subcommand.
# docs/reference/plugin-protocol.md states this deviation.
__cog_plugin_search_dirs() {
  local -n __dirs="$1"
  local rest="${PATH:-}" dir

  [[ -n ${COG_PLUGIN_DIR:-} ]] && __dirs+=("$COG_PLUGIN_DIR")
  while [[ -n $rest ]]; do
    dir="${rest%%:*}"
    if [[ $rest == *:* ]]; then
      rest="${rest#*:}"
    else
      rest=""
    fi
    [[ -n $dir ]] && __dirs+=("$dir")
  done
  return 0
}

# Every candidate for <name>, one absolute path per line, in resolution order:
# $COG_PLUGIN_DIR first, then $PATH. Existence only — a candidate that is not
# executable is still a candidate, so `list` can say why it is not a plugin.
cog::fn::plugin_candidates() {
  local name="${1:-}"
  cog::fn::plugin_name_valid "$name" || return 1

  local file="${__COG_PLUGIN_PREFIX}${name}"
  local -a dirs=()
  local -A seen=()
  local dir candidate abs

  __cog_plugin_search_dirs dirs

  for dir in "${dirs[@]}"; do
    # Candidate streams are newline-delimited, so a directory containing a
    # newline cannot be represented in one. Skipped rather than emitted as two
    # broken fragments, which is what the reference documents.
    [[ $dir == *$'\n'* ]] && continue
    candidate="${dir}/${file}"
    [[ -e $candidate || -L $candidate ]] || continue
    abs="$(__cog_plugin_abs "$candidate")" || continue
    [[ -n ${seen[$abs]:-} ]] && continue
    seen[$abs]=1
    printf '%s\n' "$abs"
  done
  return 0
}

# The path cog would execute for <name>, resolved through symlinks. Non-zero and
# silent when nothing resolves. A candidate that is not a regular executable file
# is skipped here, so callers can distinguish it through plugin_state.
cog::fn::plugin_resolve() {
  local name="${1:-}"
  local candidate target
  cog::fn::plugin_name_valid "$name" || return 1

  while IFS= read -r candidate; do
    target="$(__cog_plugin_realpath "$candidate")" || continue
    [[ -f $target && -x $target ]] || continue
    printf '%s\n' "$target"
    return 0
  done < <(cog::fn::plugin_candidates "$name")
  return 1
}

# The candidate path cog would execute for <name> — the candidate itself, not the
# target it resolves to. `plugin_resolve` answers "what runs"; this answers "which
# candidate won", and the two differ whenever several candidates are links to one
# target. Only the latter can decide `shadowed-by-path`, and only it is the path
# a `shadowed_by` row should name.
cog::fn::plugin_winner() {
  local name="${1:-}"
  local candidate target
  cog::fn::plugin_name_valid "$name" || return 1

  while IFS= read -r candidate; do
    target="$(__cog_plugin_realpath "$candidate")" || continue
    [[ -f $target && -x $target ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done < <(cog::fn::plugin_candidates "$name")
  return 1
}

# Every plugin name discoverable in $COG_PLUGIN_DIR and $PATH, deduplicated and
# sorted. Names that fail the slug rule are not plugins and are not reported.
cog::fn::plugin_discover() {
  local -a dirs=()
  local dir entry base name
  local -A seen=()

  __cog_plugin_search_dirs dirs

  for dir in "${dirs[@]}"; do
    # Same exclusion as plugin_candidates: a name discovered here would resolve
    # to nothing, so reporting it would be a row no verb could act on.
    [[ $dir == *$'\n'* ]] && continue
    [[ -d $dir ]] || continue
    for entry in "$dir/${__COG_PLUGIN_PREFIX}"*; do
      [[ -e $entry || -L $entry ]] || continue
      base="${entry##*/}"
      name="${base#"$__COG_PLUGIN_PREFIX"}"
      cog::fn::plugin_name_valid "$name" || continue
      [[ -n ${seen[$name]:-} ]] && continue
      seen[$name]=1
    done
  done

  ((${#seen[@]})) || return 0
  printf '%s\n' "${!seen[@]}" | LC_ALL=C sort
}

# One state token from data/plugin-protocol/meta.yaml for <name> at <path>.
# <path> is a candidate path, not necessarily the winning one.
cog::fn::plugin_state() {
  local state
  { IFS= read -r state || true; } < <(cog::fn::plugin_inspect "$@")
  printf '%s\n' "$state"
}

# The state token for <name> at <path> on line 1, and the metadata object that
# decided it on line 2 — compact JSON for `ok` and `protocol-newer`, `null`
# otherwise, because those are the only states whose metadata a caller may show.
#
# Both answers come from ONE probe. Deriving them from two probes let a plugin
# return conformant metadata to the state probe and malformed output to the
# metadata probe, so a row could read `state: "ok"` with null fields; it also
# paid the bounded probe cost twice for every inspected winner.
cog::fn::plugin_inspect() {
  local name="${1:-}" path="${2:-}"
  local winner self target json expected

  if __cog_plugin_firstparty "$name"; then
    printf '%s\nnull\n' "shadowed-by-core"
    return 0
  fi

  # Compare candidates, not the targets they resolve to: two links to one binary
  # are still an earlier candidate and a later one, and only the earlier runs.
  winner="$(cog::fn::plugin_winner "$name" 2>/dev/null || true)"
  self="$(__cog_plugin_abs "$path" 2>/dev/null || true)"
  target="$(__cog_plugin_realpath "$path" 2>/dev/null || true)"

  if [[ -z $target || ! -f $target || ! -x $target ]]; then
    printf '%s\nnull\n' "not-executable"
    return 0
  fi
  if [[ -n $winner && $self != "$winner" ]]; then
    printf '%s\nnull\n' "shadowed-by-path"
    return 0
  fi

  # The one probe. Every state below is decided from this `json` alone.
  if ! json="$(cog::fn::plugin_probe "$target")"; then
    printf '%s\nnull\n' "metadata-unavailable"
    return 0
  fi

  # `ok` promises the metadata satisfies the protocol, so the same field
  # predicate and filename agreement `validate` applies are applied here. Only
  # `probe_side_effect_free` stays a `validate`-only assertion, and the state
  # table says so. Quoted as a string: a non-integer `protocol` must not reach
  # (( )), where it would be a fatal arithmetic syntax error rather than the
  # degraded state token this file promises never to escape.
  printf '%s' "$json" | jq -e "$__COG_PLUGIN_FIELDS_PREDICATE" >/dev/null 2>&1 || {
    printf '%s\nnull\n' "metadata-unavailable"
    return 0
  }

  expected="${path##*/}"
  expected="${expected#"$__COG_PLUGIN_PREFIX"}"
  printf '%s' "$json" | jq -e --arg name "$expected" '.name == $name' >/dev/null 2>&1 || {
    printf '%s\nnull\n' "metadata-unavailable"
    return 0
  }

  # Compared in jq, never in (( )). A JSON integer may exceed Bash's signed
  # 64-bit range, where it wraps silently and a far-future protocol would be
  # classified `ok` instead of `protocol-newer` — a plugin's number must not
  # decide cog's arithmetic.
  if printf '%s' "$json" | jq -e --argjson max "$__COG_PLUGIN_PROTOCOL_VERSION" \
    '.protocol > $max' >/dev/null 2>&1; then
    printf '%s\n%s\n' "protocol-newer" "$json"
    return 0
  fi
  printf '%s\n%s\n' "ok" "$json"
}

# Run the reserved subcommand in an empty working directory with no stdin, under
# the timeout and a hard file-size ceiling. Writes captured stdout to <outfile>
# and prints the raw exit status. Never dies.
__cog_plugin_probe_run() {
  local path="$1" workdir="$2" outfile="$3"
  local rc=0 start end elapsed

  # Microseconds, not $SECONDS: a one-second-granularity counter can report 2
  # for a 1.2-second run that straddles the right integer boundary, which would
  # read a plugin's own exit 124 as a timeout.
  start="${EPOCHREALTIME/./}"
  (
    # 512-byte blocks: bound a runaway plugin's stdout well above the reported
    # cap, so exceeding the cap is a measurement rather than a filled disk.
    ulimit -f 1024 2>/dev/null || true
    cd "$workdir" || exit 126
    exec timeout --kill-after="$__COG_PLUGIN_PROBE_KILL_AFTER" \
      "$__COG_PLUGIN_PROBE_TIMEOUT" "$path" "$__COG_PLUGIN_RESERVED_SUBCOMMAND"
  ) </dev/null >"$outfile" 2>/dev/null || rc=$?
  end="${EPOCHREALTIME/./}"
  elapsed=$((end - start))

  # `rc elapsed-microseconds`. See __cog_plugin_probe_timed_out for why the
  # status alone cannot decide whether this was a timeout.
  printf '%s %s\n' "$rc" "$elapsed"
}

# True when <rc> <elapsed-microseconds> describes a probe cog cut short.
#
# 124 is timeout(1)'s report that it sent TERM at the deadline; 137 is
# 128+SIGKILL, which is what it reports once --kill-after fires on a plugin that
# ignored TERM. Both are also exit statuses a plugin may choose for itself, so
# the status alone is ambiguous. Elapsed wall time is the independent signal that
# separates them: a plugin exiting 124 or 137 immediately is an exit failure,
# not a timeout.
__cog_plugin_probe_timed_out() {
  local rc="${1:-}" elapsed="${2:-0}"
  [[ $rc == 124 || $rc == 137 ]] || return 1
  ((elapsed >= __COG_PLUGIN_PROBE_TIMEOUT * 1000000))
}

# Read probe stdout and print the single metadata object it must be. Slurps, so
# a stream of two or more concatenated objects fails here rather than reaching a
# caller as multiple lines that would abort the next `jq --argjson`. `metadata_json`
# in data/plugin-protocol/meta.yaml promises exactly one object; this enforces it.
__cog_plugin_parse_metadata() {
  jq -e -c -s 'if length == 1 and (.[0] | type) == "object" then .[0] else error("not one object") end' 2>/dev/null
}

# The required/optional field contract from docs/reference/plugin-protocol.md:
# `protocol` is an integer, not merely a number, and an `requires_cog` that is
# present must be the documented string. Shared by `plugin_check` and
# `plugin_state` so an inventory row and a conformance verdict cannot disagree.
__COG_PLUGIN_FIELDS_PREDICATE='
  (.protocol | type) == "number" and (.protocol | floor) == .protocol
  and (.name | type) == "string" and (.name | length) > 0
  and (.version | type) == "string" and (.version | length) > 0
  and (.summary | type) == "string" and (.summary | length) > 0
  and (.summary | contains("\n") | not)
  and ((has("requires_cog") | not)
    or ((.requires_cog | type) == "string" and (.requires_cog | length) > 0))
'

# Emit `<check> <pass|fail|skip>` lines for every entry in
# data/plugin-protocol/meta.yaml's plugin-protocol-checks, for <path>. <name> is
# optional and defaults to the filename's <name>.
cog::fn::plugin_check() {
  local path="${1:-}" name="${2:-}" meta_out="${3:-}"
  local base expected target scratch workdir outfile rc elapsed size json
  local -A result=()
  local check

  # <metadata-outfile> is how a caller reads the metadata this probe already
  # parsed instead of probing a second time for it. `validate` needs the
  # metadata to report `requires_cog`, and a second probe would let one plugin
  # answer the checks and a differently-behaving run answer the report.
  [[ -n $meta_out ]] && printf 'null\n' >"$meta_out"

  for check in "${__COG_PLUGIN_CHECKS[@]}"; do
    result[$check]=skip
  done

  # The filename is half of `name_matches_filename`, so it is derived and
  # validated here rather than assumed. A file that is not named `cog-<slug>` is
  # not a plugin at all, however conformant its metadata: validating a path must
  # reach the same verdict as validating the name that resolves to it.
  base="${path##*/}"
  expected=""
  if [[ $base == "${__COG_PLUGIN_PREFIX}"* ]]; then
    expected="${base#"$__COG_PLUGIN_PREFIX"}"
    cog::fn::plugin_name_valid "$expected" || expected=""
  fi
  [[ -n $name ]] || name="$expected"

  target="$(__cog_plugin_realpath "$path" 2>/dev/null || true)"
  result[regular_file]=$([[ -n $target && -f $target ]] && printf 'pass' || printf 'fail')
  result[executable]=$([[ -n $target && -f $target && -x $target ]] && printf 'pass' || printf 'fail')
  result[no_firstparty_collision]=$(__cog_plugin_firstparty "$name" && printf 'fail' || printf 'pass')

  if [[ ${result[executable]} == pass ]]; then
    scratch="$(mktemp -d 2>/dev/null)" || scratch=""
  fi

  if [[ -n ${scratch:-} ]]; then
    workdir="${scratch}/cwd"
    outfile="${scratch}/stdout"
    mkdir -p "$workdir"
    read -r rc elapsed < <(__cog_plugin_probe_run "$target" "$workdir" "$outfile")
    size="$(LC_ALL=C wc -c <"$outfile" 2>/dev/null || printf '0')"
    size="${size//[[:space:]]/}"

    if __cog_plugin_probe_timed_out "$rc" "$elapsed"; then
      result[probe_within_timeout]=fail
    else
      result[probe_within_timeout]=pass
      result[metadata_exit]=$([[ $rc == 0 ]] && printf 'pass' || printf 'fail')
    fi

    if ((size <= __COG_PLUGIN_PROBE_CAP)); then
      result[probe_within_cap]=pass
    else
      result[probe_within_cap]=fail
    fi

    if [[ ${result[metadata_exit]} == pass && ${result[probe_within_cap]} == pass ]]; then
      if json="$(__cog_plugin_parse_metadata <"$outfile")"; then
        result[metadata_json]=pass
        [[ -n $meta_out ]] && printf '%s\n' "$json" >"$meta_out"
        result[metadata_required_fields]=$(
          printf '%s' "$json" | jq -e "$__COG_PLUGIN_FIELDS_PREDICATE" >/dev/null 2>&1 \
            && printf 'pass' || printf 'fail'
        )
        if [[ ${result[metadata_required_fields]} == pass ]]; then
          result[name_matches_filename]=$(
            [[ -n $expected ]] \
              && printf '%s' "$json" | jq -e --arg name "$expected" '.name == $name' >/dev/null 2>&1 \
              && printf 'pass' || printf 'fail'
          )
          result[protocol_supported]=$(
            printf '%s' "$json" | jq -e --argjson max "$__COG_PLUGIN_PROTOCOL_VERSION" '.protocol <= $max' >/dev/null 2>&1 \
              && printf 'pass' || printf 'fail'
          )
        fi
      else
        result[metadata_json]=fail
      fi
    fi

    result[probe_side_effect_free]=$([[ -z "$(find "$workdir" -mindepth 1 -print -quit 2>/dev/null)" ]] && printf 'pass' || printf 'fail')
    rm -rf -- "$scratch"
  fi

  for check in "${__COG_PLUGIN_CHECKS[@]}"; do
    printf '%s %s\n' "$check" "${result[$check]}"
  done
}

# The metadata object for <path>, or non-zero and silent on any failure.
cog::fn::plugin_probe() {
  local path="${1:-}"
  local scratch workdir outfile rc elapsed size json

  [[ -n $path && -f $path && -x $path ]] || return 1
  scratch="$(mktemp -d 2>/dev/null)" || return 1
  workdir="${scratch}/cwd"
  outfile="${scratch}/stdout"
  mkdir -p "$workdir"

  read -r rc elapsed < <(__cog_plugin_probe_run "$path" "$workdir" "$outfile")
  size="$(LC_ALL=C wc -c <"$outfile" 2>/dev/null || printf '0')"
  size="${size//[[:space:]]/}"

  if [[ $rc != 0 ]] || ((size > __COG_PLUGIN_PROBE_CAP)); then
    rm -rf -- "$scratch"
    return 1
  fi
  if ! json="$(__cog_plugin_parse_metadata <"$outfile")"; then
    rm -rf -- "$scratch"
    return 1
  fi
  rm -rf -- "$scratch"
  printf '%s\n' "$json"
}

# The absolute path of the cog entry point that is running, so a plugin can call
# back into this host rather than whichever cog is first on $PATH.
__cog_plugin_executable() {
  local dir
  if [[ -n ${SCRIPT_DIR:-} && -x ${SCRIPT_DIR}/cog ]]; then
    printf '%s\n' "${SCRIPT_DIR}/cog"
    return 0
  fi
  dir="$(cd -P "${LIB_DIR}/../bin" 2>/dev/null && pwd)" || return 1
  printf '%s\n' "${dir}/cog"
}

__cog_plugin_host_version() {
  local version_file="${LIB_DIR}/../VERSION"
  [[ -r $version_file ]] || return 1
  printf '%s\n' "$(<"$version_file")"
}

# The four exported variable names, in their stable order. Single source: every
# environment surface — the exec, the JSON block, the NAME=VALUE listing — walks
# this array, so "exactly four" is a property of one list rather than a
# coincidence three functions have to keep agreeing on.
__COG_PLUGIN_ENV_NAMES=(
  COG_PLUGIN_PROTOCOL
  COG_HOST_VERSION
  COG_PLUGIN_NAME
  COG_EXECUTABLE
)

cog::fn::plugin_env_names() {
  printf '%s\n' "${__COG_PLUGIN_ENV_NAMES[@]}"
}

# The value of one contract variable for <plugin-name>, printed without a
# trailing newline so a value that itself contains one survives the caller.
__cog_plugin_env_value() {
  local var="${1:-}" name="${2:-}"
  local value=""

  case "$var" in
    COG_PLUGIN_PROTOCOL) value="$__COG_PLUGIN_PROTOCOL_VERSION" ;;
    COG_HOST_VERSION) value="$(__cog_plugin_host_version)" || value="" ;;
    COG_PLUGIN_NAME) value="$name" ;;
    COG_EXECUTABLE) value="$(__cog_plugin_executable)" || value="" ;;
    *) return 1 ;;
  esac
  printf '%s' "$value"
}

# The four exported variables, as NAME=VALUE lines, in a stable order. A display
# and drift-testing surface only: it is lossy for a value containing a newline,
# so `plugin_exec` and the JSON block read the values directly rather than
# parsing this back. Cog never hands a plugin a path into its own Bash sources:
# that omission is the ABI boundary.
cog::fn::plugin_env() {
  local name="${1:-}" var

  for var in "${__COG_PLUGIN_ENV_NAMES[@]}"; do
    printf '%s=%s\n' "$var" "$(__cog_plugin_env_value "$var" "$name")"
  done
}

# The same four variables as a JSON object, built by value rather than by
# reparsing text, so no value can be split or dropped on its way out.
cog::fn::plugin_env_json() {
  local name="${1:-}" var
  local -a pairs=()

  for var in "${__COG_PLUGIN_ENV_NAMES[@]}"; do
    pairs+=("$var" "$(__cog_plugin_env_value "$var" "$name")")
  done
  # Name/value positionals rather than a rendered object, so the key list stays
  # __COG_PLUGIN_ENV_NAMES alone and cannot drift from what the exec sets.
  jq -n --args '
    [range(0; ($ARGS.positional | length); 2)
      | {key: $ARGS.positional[.], value: $ARGS.positional[. + 1]}]
    | from_entries
  ' "${pairs[@]}"
}

# Replace this process with <path>, passing the remaining argv verbatim. Does not
# return: the plugin's stdout, stderr, and exit status are cog's, unmodified.
cog::fn::plugin_exec() {
  local name="${1:-}" path="${2:-}"
  shift 2 || true
  local var

  # Exported by value, never by parsing NAME=VALUE text back: a newline in
  # COG_EXECUTABLE would otherwise split into a second bogus assignment and
  # abort dispatch before the plugin ever ran.
  for var in "${__COG_PLUGIN_ENV_NAMES[@]}"; do
    printf -v "$var" '%s' "$(__cog_plugin_env_value "$var" "$name")"
    export "${var?}"
  done

  exec "$path" "$@"
}
