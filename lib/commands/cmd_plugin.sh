# shellcheck shell=bash
: 'desc: Inspect external cog-* command plugins.'

__cog_plugin_list_self_check='(.schema == "cog.plugin.list.v1") and (.ok|type=="boolean") and (.plugins|type=="array")'
__cog_plugin_info_self_check='(.schema == "cog.plugin.info.v1") and (.ok|type=="boolean") and (.name|type=="string") and (.path|type=="string") and (.state|type=="string") and (.candidates|type=="array") and (.environment|type=="object") and ((.environment|keys|length) == 4)'
__cog_plugin_validate_self_check='(.schema == "cog.plugin.validate.v1") and (.ok|type=="boolean") and (.path|type=="string") and (.name|type=="string") and (.checks|type=="object") and (.failures|type=="array") and (has("requires_cog")) and (has("requires_cog_satisfied"))'
__cog_plugin_host_info_self_check='(.schema == "cog.plugin.host-info.v1") and (.ok == true) and (.protocol|type=="number") and (.host_version|type=="string") and (.exported_environment|type=="array") and ((.exported_environment|length) == 4)'

__cog_plugin_usage() {
  cog::fn::ui_data "Usage: cog plugin <verb> [args]"
  cog::fn::ui_data ""
  cog::fn::ui_data "Verbs:"
  cog::fn::ui_data "  list [--names] [--json]              List every cog-* candidate with its resolved path and state"
  cog::fn::ui_data "  info <name> [--json]                 Report one plugin's path, metadata, and environment"
  cog::fn::ui_data "  validate <path-or-name> [--json]     Run every protocol conformance check"
  cog::fn::ui_data "  host-info [--json]                   Report the protocol this cog implements"
}

# The four exported variables as a JSON object. Built by value in fn_plugin.sh
# rather than by reparsing NAME=VALUE text, so a value containing `=` or a
# newline survives intact.
__cog_plugin_env_json() {
  local name="$1"
  cog::fn::plugin_env_json "$name"
}

# `requires_cog` is advisory: cog reports a mismatch and never blocks execution,
# because only the plugin knows which cog behavior it depends on. The supported
# grammar is a bare version or one of >=, >, <=, <, = followed by a version.
__cog_plugin_requires_satisfied() {
  local constraint="$1" host="$2"
  local op="" want="" cmp

  [[ -n $constraint ]] || {
    printf 'null\n'
    return 0
  }

  if [[ $constraint =~ ^[[:space:]]*(\>=|\<=|\>|\<|=)?[[:space:]]*(.+)$ ]]; then
    op="${BASH_REMATCH[1]:-=}"
    want="${BASH_REMATCH[2]}"
  else
    printf 'null\n'
    return 0
  fi
  want="${want%"${want##*[![:space:]]}"}"

  # Numeric dotted comparison via sort -V, which the devShell declares through
  # coreutils and which handles unequal component counts.
  if [[ $host == "$want" ]]; then
    cmp=0
  elif [[ "$(printf '%s\n%s\n' "$host" "$want" | LC_ALL=C sort -V | head -n 1)" == "$host" ]]; then
    cmp=-1
  else
    cmp=1
  fi

  case "$op" in
    '>=') ((cmp >= 0)) && printf 'true\n' || printf 'false\n' ;;
    '>') ((cmp > 0)) && printf 'true\n' || printf 'false\n' ;;
    '<=') ((cmp <= 0)) && printf 'true\n' || printf 'false\n' ;;
    '<') ((cmp < 0)) && printf 'true\n' || printf 'false\n' ;;
    *) ((cmp == 0)) && printf 'true\n' || printf 'false\n' ;;
  esac
  return 0
}

__cog_plugin_row_json() {
  local name="$1" path="$2"
  local state winner metadata shadowed_by

  # The winning candidate, not the target it resolves to: `shadowed_by` answers
  # "which candidate beat this one", and links pointing at one binary would
  # otherwise report the shared target instead of the row that wins.
  winner="$(cog::fn::plugin_winner "$name" 2>/dev/null || true)"
  # State and metadata from one probe, so the row cannot report a state that a
  # second, differently-behaving probe then contradicts.
  {
    IFS= read -r state || true
    IFS= read -r metadata || true
  } < <(cog::fn::plugin_inspect "$name" "$path")
  [[ -n $metadata ]] || metadata='null'

  shadowed_by=""
  case "$state" in
    shadowed-by-core) shadowed_by="lib/commands/cmd_${name//-/_}.sh" ;;
    shadowed-by-path) shadowed_by="$winner" ;;
  esac

  jq -n \
    --arg name "$name" \
    --arg path "$path" \
    --arg state "$state" \
    --arg shadowed_by "$shadowed_by" \
    --argjson metadata "$metadata" \
    '{
      name: $name,
      path: (if $path == "" then null else $path end),
      state: $state,
      version: ($metadata.version // null),
      protocol: ($metadata.protocol // null),
      shadowed_by: (if $shadowed_by == "" then null else $shadowed_by end),
      summary: ($metadata.summary // null)
    }'
}

__cog_plugin_verb_list() {
  local names_only=false json rows name path
  local -a fragments=()

  while (($# > 0)); do
    case "$1" in
      --names)
        names_only=true
        shift
        ;;
      --json)
        shift
        ;;
      -h | --help)
        __cog_plugin_usage
        return 0
        ;;
      *)
        cog::fn::error_raise "InvalidInput" "unknown plugin list option" "option: $1" "" "run 'cog plugin --help'"
        ;;
    esac
  done

  if [[ $names_only == true ]]; then
    cog::fn::plugin_discover
    return 0
  fi

  # One row per candidate, not per name: a losing or unusable candidate is the
  # thing a user needs to see, and `shadowed-by-path` has nowhere else to be
  # reported.
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    while IFS= read -r path; do
      [[ -n $path ]] || continue
      fragments+=("$(__cog_plugin_row_json "$name" "$path")")
    done < <(cog::fn::plugin_candidates "$name")
  done < <(cog::fn::plugin_discover)

  if ((${#fragments[@]})); then
    rows="$(printf '%s\n' "${fragments[@]}" | jq -s .)"
  else
    rows='[]'
  fi

  json="$(jq -n --argjson plugins "$rows" '{schema: "cog.plugin.list.v1", ok: true, plugins: $plugins}')"
  cog::fn::json_emit "$__cog_plugin_list_self_check" "$json"
  return 0
}

__cog_plugin_verb_info() {
  local name="" json path state metadata candidates env_json requires satisfied host

  while (($# > 0)); do
    case "$1" in
      --json)
        shift
        ;;
      -h | --help)
        __cog_plugin_usage
        return 0
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown plugin info option" "option: $1" "" "run 'cog plugin --help'"
        ;;
      *)
        [[ -z $name ]] || cog::fn::error_raise "TooManyArguments" "too many plugin info names" "argument: $1" "" "run 'cog plugin --help'"
        name="$1"
        shift
        ;;
    esac
  done

  [[ -n $name ]] || cog::fn::error_raise "MissingArgument" "missing plugin name" "usage: cog plugin info <name> [--json]" "" "run 'cog plugin --help'"
  cog::fn::plugin_name_valid "$name" || cog::fn::error_raise "BadCommandName" \
    "invalid plugin name" "name: ${name}" "plugin names must match [a-z][a-z0-9_-]*" ""

  # The winning candidate, not the target it resolves to. `plugin_state` compares
  # candidate identity and `plugin_check` reads the filename, so handing either
  # one a resolved target would misreport a symlinked plugin as shadowed by
  # itself and fail `name_matches_filename` on the target's name.
  path="$(cog::fn::plugin_winner "$name" 2>/dev/null || true)"
  [[ -n $path ]] || path="$(cog::fn::plugin_candidates "$name" 2>/dev/null | head -n 1 || true)"
  [[ -n $path ]] || cog::fn::error_raise "UnknownPlugin" \
    "no plugin found" "name: ${name}" \
    "no executable cog-${name} on \$COG_PLUGIN_DIR or \$PATH" \
    "install the plugin that provides it, or run 'cog plugin list'"

  # One probe decides both, for the same reason as the list row.
  {
    IFS= read -r state || true
    IFS= read -r metadata || true
  } < <(cog::fn::plugin_inspect "$name" "$path")
  [[ -n $metadata ]] || metadata='null'
  candidates="$(cog::fn::plugin_candidates "$name" | jq -R -s 'split("\n") | map(select(length > 0))')"
  env_json="$(__cog_plugin_env_json "$name")"
  host="$(printf '%s' "$env_json" | jq -r '.COG_HOST_VERSION')"
  requires="$(printf '%s' "$metadata" | jq -r '.requires_cog // ""')"
  satisfied="$(__cog_plugin_requires_satisfied "$requires" "$host")"

  json="$(jq -n \
    --arg name "$name" \
    --arg path "$path" \
    --arg state "$state" \
    --argjson metadata "$metadata" \
    --argjson satisfied "$satisfied" \
    --argjson candidates "$candidates" \
    --argjson environment "$env_json" \
    '{
      schema: "cog.plugin.info.v1",
      # `ok` reports that the inspection succeeded, not that the plugin is
      # healthy — the same meaning `list` gives it, and the meaning that agrees
      # with this command exiting 0. Plugin health is `state`, which is the
      # field that can say *how* a plugin is unhealthy and still dispatches.
      # Conflating the two made `info noprobe --json` print ok:false and exit 0,
      # handing automation two opposite answers to one question.
      ok: true,
      name: $name,
      path: $path,
      state: $state,
      metadata: $metadata,
      requires_cog_satisfied: $satisfied,
      candidates: $candidates,
      environment: $environment
    }')"
  cog::fn::json_emit "$__cog_plugin_info_self_check" "$json"
  return 0
}

__cog_plugin_verb_validate() {
  local target="" json path name checks failures ok
  local meta_file metadata env_json host requires satisfied

  while (($# > 0)); do
    case "$1" in
      --json)
        shift
        ;;
      -h | --help)
        __cog_plugin_usage
        return 0
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown plugin validate option" "option: $1" "" "run 'cog plugin --help'"
        ;;
      *)
        [[ -z $target ]] || cog::fn::error_raise "TooManyArguments" "too many plugin validate targets" "argument: $1" "" "run 'cog plugin --help'"
        target="$1"
        shift
        ;;
    esac
  done

  [[ -n $target ]] || cog::fn::error_raise "MissingArgument" "missing plugin target" "usage: cog plugin validate <path-or-name> [--json]" "" "run 'cog plugin --help'"

  # A path or a resolved name, and nothing else. Accepting a source would make
  # cog responsible for fetching it, which is the installation this command
  # deliberately does not do.
  if [[ $target == */* || -e $target ]]; then
    path="$target"
    name=""
  else
    name="${target#cog-}"
    cog::fn::plugin_name_valid "$name" || cog::fn::error_raise "BadCommandName" \
      "invalid plugin name" "name: ${target}" "plugin names must match [a-z][a-z0-9_-]*" ""
    # The winning candidate, for the same reason `info` uses it: the filename
    # `name_matches_filename` checks is the candidate's, not the target's.
    path="$(cog::fn::plugin_winner "$name" 2>/dev/null || true)"
    [[ -n $path ]] || path="$(cog::fn::plugin_candidates "$name" 2>/dev/null | head -n 1 || true)"
    [[ -n $path ]] || cog::fn::error_raise "UnknownPlugin" \
      "no plugin found" "name: ${target}" \
      "no cog-${name} on \$COG_PLUGIN_DIR or \$PATH" \
      "pass a path, or run 'cog plugin list'"
  fi

  [[ -e $path || -L $path ]] || cog::fn::error_raise "InputNotFound" \
    "plugin path not found" "path: ${path}" "" "check the path and retry"

  [[ -n $name ]] || {
    name="${path##*/}"
    name="${name#cog-}"
  }

  meta_file="$(mktemp 2>/dev/null)" || meta_file=""
  checks="$(cog::fn::plugin_check "$path" "$name" "$meta_file" | jq -R -s '
    split("\n")
    | map(select(length > 0))
    | map(split(" ") | {key: .[0], value: .[1]})
    | from_entries
  ')"
  failures="$(printf '%s' "$checks" | jq -c '[to_entries[] | select(.value == "fail") | .key]')"

  # `requires_cog` is advisory: the reference promises validate *reports* a
  # mismatch, and equally that cog does not block on one. So it is reported
  # beside the checks rather than as one, and it never moves `ok`. The metadata
  # comes from the check run's own probe, not a second one.
  metadata='null'
  [[ -n $meta_file && -s $meta_file ]] && metadata="$(<"$meta_file")"
  [[ -n $meta_file ]] && rm -f -- "$meta_file"
  env_json="$(__cog_plugin_env_json "$name")"
  host="$(printf '%s' "$env_json" | jq -r '.COG_HOST_VERSION')"
  requires="$(printf '%s' "$metadata" | jq -r '.requires_cog // ""' 2>/dev/null || printf '')"
  satisfied="$(__cog_plugin_requires_satisfied "$requires" "$host")"
  # Conformance is every check passing, not merely no check failing. A `skip`
  # left behind by a host-side failure — an unwritable TMPDIR aborting the probe
  # setup — would otherwise certify a plugin nothing ever inspected.
  ok=true
  [[ "$(printf '%s' "$checks" | jq '[to_entries[] | select(.value != "pass")] | length')" == 0 ]] || ok=false

  json="$(jq -n \
    --argjson ok "$ok" \
    --arg path "$path" \
    --arg name "$name" \
    --argjson checks "$checks" \
    --argjson failures "$failures" \
    --arg requires "$requires" \
    --argjson satisfied "$satisfied" \
    '{
      schema: "cog.plugin.validate.v1",
      ok: $ok,
      path: $path,
      name: $name,
      checks: $checks,
      failures: $failures,
      requires_cog: (if $requires == "" then null else $requires end),
      requires_cog_satisfied: $satisfied
    }')"
  cog::fn::json_emit "$__cog_plugin_validate_self_check" "$json"
  [[ $ok == true ]] || return "$EX_DATAERR"
  return 0
}

__cog_plugin_verb_host_info() {
  local json env_json executable

  while (($# > 0)); do
    case "$1" in
      --json) shift ;;
      -h | --help)
        __cog_plugin_usage
        return 0
        ;;
      *)
        cog::fn::error_raise "InvalidInput" "unknown plugin host-info option" "option: $1" "" "run 'cog plugin --help'"
        ;;
    esac
  done

  env_json="$(__cog_plugin_env_json "")"
  executable="$(printf '%s' "$env_json" | jq -r '.COG_EXECUTABLE')"

  json="$(jq -n \
    --argjson protocol "$(cog::fn::plugin_protocol_version)" \
    --arg host_version "$(printf '%s' "$env_json" | jq -r '.COG_HOST_VERSION')" \
    --arg executable "$executable" \
    --arg reserved "$(cog::fn::plugin_reserved_subcommand)" \
    --argjson timeout "$(cog::fn::plugin_probe_timeout)" \
    --argjson cap "$(cog::fn::plugin_probe_cap)" \
    '{
      schema: "cog.plugin.host-info.v1",
      ok: true,
      protocol: $protocol,
      host_version: $host_version,
      executable: $executable,
      exported_environment: ["COG_PLUGIN_PROTOCOL", "COG_HOST_VERSION", "COG_PLUGIN_NAME", "COG_EXECUTABLE"],
      resolution_order: ["$COG_PLUGIN_DIR", "$PATH"],
      executable_prefix: "cog-",
      reserved_subcommand: $reserved,
      probe_timeout_seconds: $timeout,
      probe_output_cap_bytes: $cap
    }')"
  cog::fn::json_emit "$__cog_plugin_host_info_self_check" "$json"
  return 0
}

cog::cmd::plugin() {
  local verb="${1:-}"
  shift || true

  case "$verb" in
    "" | -h | --help)
      __cog_plugin_usage
      return 0
      ;;
    list) __cog_plugin_verb_list "$@" ;;
    info) __cog_plugin_verb_info "$@" ;;
    validate) __cog_plugin_verb_validate "$@" ;;
    host-info) __cog_plugin_verb_host_info "$@" ;;
    *)
      cog::fn::error_raise "InvalidInput" "unknown plugin verb" "verb: ${verb}" \
        "" "run 'cog plugin --help'"
      ;;
  esac
}
