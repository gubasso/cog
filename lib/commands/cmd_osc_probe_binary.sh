# shellcheck shell=bash
: 'desc: Resolve a binary RPM to an OBS source package.'

__cog_osc_probe_binary_self_check='(.ok|type=="boolean") and (.api|type=="string") and (.binary|type=="string") and (.project|type=="string") and (.probe|type=="object") and (.probe.status|IN("pass","fail","skip")) and (.matches|type=="array") and ((.source_package == null) or (.source_package|type=="string")) and (.source_differs|type=="boolean")'

__cog_osc_probe_binary_usage() {
  cog::fn::ui_data "Usage: cog osc-probe-binary --binary <binary-rpm> --project <source-project> [--api <url>] (<out.json>|--json)"
}

__cog_osc_probe_binary_stderr_snippet() {
  local file="$1"
  if [[ ! -f $file ]]; then
    printf '%s\n' ""
    return 0
  fi
  LC_ALL=C head -c 1000 "$file"
  return 0
}

__cog_osc_probe_binary_xml_attr() {
  local line="$1" attr="$2"
  sed -n "s/.*${attr}=\"\\([^\"]*\\)\".*/\\1/p" <<<"$line"
  return 0
}

__cog_osc_probe_binary_urlencode() {
  local s="$1" out="" i c
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9._~-]) out+="$c" ;;
      *) out+="$(printf '%%%02X' "'$c")" ;;
    esac
  done
  printf '%s' "$out"
  return 0
}

__cog_osc_probe_binary_matches_json() {
  local xml_file="$1"
  local line name package project
  { grep -oE '<binary[^>]*>' "$xml_file" 2>/dev/null || true; } | while IFS= read -r line; do
    name="$(__cog_osc_probe_binary_xml_attr "$line" name)"
    package="$(__cog_osc_probe_binary_xml_attr "$line" package)"
    project="$(__cog_osc_probe_binary_xml_attr "$line" project)"
    [[ -n $package ]] || continue
    jq -cn \
      --arg binary "$name" \
      --arg package "$package" \
      --arg project "$project" \
      '{binary: $binary, package: $package, project: $project}'
  done | jq -s .
  return 0
}

__cog_osc_probe_binary_unique_package_count() {
  jq '[.[].package] | unique | length'
  return 0
}

__cog_osc_probe_binary_first_package() {
  jq -r '.[0].package // ""'
  return 0
}

__cog_osc_probe_binary_build_json() {
  local binary="$1" project="$2" api="$3"
  local query_path osc_path stdout_file stderr_file exit_code stderr_text matches source_package source_differs ok reason probe_status probe_reason
  local binary_enc project_enc
  binary_enc="$(__cog_osc_probe_binary_urlencode "$binary")"
  project_enc="$(__cog_osc_probe_binary_urlencode "$project")"
  query_path="/search/published/binary/id?match=@name=\"${binary_enc}\"+and+@project=\"${project_enc}\""
  osc_path=""
  ok=false
  reason=""
  source_package=""
  source_differs=false
  probe_status=skip
  probe_reason=""
  exit_code=null
  stderr_text=""
  matches="[]"

  if ! __have osc; then
    reason="osc binary missing"
    probe_status=skip
    probe_reason="$reason"
  elif ! __have timeout; then
    osc_path="$(command -v osc)"
    reason="timeout command missing"
    probe_status=fail
    probe_reason="$reason"
  else
    osc_path="$(command -v osc)"
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    if timeout "${OSC_PROBE_TIMEOUT:-15s}" osc -A "$api" api "$query_path" >"$stdout_file" 2>"$stderr_file"; then
      probe_status=pass
      exit_code=0
      matches="$(__cog_osc_probe_binary_matches_json "$stdout_file")"
      if [[ $(jq 'length' <<<"$matches") -eq 0 ]]; then
        ok=false
        reason="binary not found in published search"
      elif [[ $(__cog_osc_probe_binary_unique_package_count <<<"$matches") -gt 1 ]]; then
        ok=false
        reason="ambiguous source package"
      else
        source_package="$(__cog_osc_probe_binary_first_package <<<"$matches")"
        if [[ $source_package != "$binary" ]]; then
          source_differs=true
        fi
        ok=true
      fi
    else
      exit_code="$?"
      stderr_text="$(__cog_osc_probe_binary_stderr_snippet "$stderr_file")"
      probe_status=fail
      probe_reason="osc binary probe failed"
      reason="$probe_reason"
    fi
    rm -f "$stdout_file" "$stderr_file"
  fi

  jq -n \
    --argjson ok "$ok" \
    --arg api "$api" \
    --arg binary "$binary" \
    --arg project "$project" \
    --arg osc_path "$osc_path" \
    --arg query_path "$query_path" \
    --arg probe_status "$probe_status" \
    --argjson exit_code "$exit_code" \
    --arg probe_reason "$probe_reason" \
    --arg stderr "$stderr_text" \
    --argjson matches "$matches" \
    --arg source_package "$source_package" \
    --argjson source_differs "$source_differs" \
    --arg reason "$reason" \
    '{
      ok: $ok,
      api: $api,
      binary: $binary,
      project: $project,
      osc_path: (if $osc_path == "" then null else $osc_path end),
      query_path: $query_path,
      probe: {
        status: $probe_status,
        exit_code: $exit_code,
        reason: (if $probe_reason == "" then null else $probe_reason end),
        stderr: $stderr
      },
      matches: $matches,
      source_package: (if $source_package == "" then null else $source_package end),
      source_differs: $source_differs,
      reason: (if $ok then null else $reason end)
    }'
  return 0
}

cog::cmd::osc_probe_binary() {
  local binary="" project="" api="${OBS_API:-https://api.opensuse.org}" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_osc_probe_binary_usage
        return 0
        ;;
      --binary)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing binary RPM name" "option: --binary" "" "run 'cog osc-probe-binary --help'"
        binary="$2"
        shift 2
        ;;
      --project)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing source project" "option: --project" "" "run 'cog osc-probe-binary --help'"
        project="$2"
        shift 2
        ;;
      --api)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing OBS API URL" "option: --api" "" "run 'cog osc-probe-binary --help'"
        api="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate osc-probe-binary output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown osc-probe-binary option" "option: $1" "" "run 'cog osc-probe-binary --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many osc-probe-binary output paths" "argument: $1" "" "run 'cog osc-probe-binary --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $binary && -n $project ]] || cog::fn::error_raise "MissingArgument" "missing osc-probe-binary argument" "usage: cog osc-probe-binary --binary <binary-rpm> --project <source-project> [--api <url>] (<out.json>|--json)" "" "run 'cog osc-probe-binary --help'"
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing osc-probe-binary output mode" "usage: cog osc-probe-binary --binary <binary-rpm> --project <source-project> [--api <url>] (<out.json>|--json)" "" "run 'cog osc-probe-binary --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_osc_probe_binary_build_json "$binary" "$project" "$api")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_osc_probe_binary_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_osc_probe_binary_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
