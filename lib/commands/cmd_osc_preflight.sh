# shellcheck shell=bash
: 'desc: Detect OBS/osc session prerequisites.'

__cog_osc_preflight_self_check='(.ok|type=="boolean") and (.api|type=="string") and (.workspace|type=="string") and (.checks|type=="object") and (.checks.env.status|IN("pass","fail","skip")) and (.checks.osc_binary.status|IN("pass","fail","skip")) and (.checks.credentials.status|IN("pass","fail","skip")) and (.checks.auth_probe.status|IN("pass","fail","skip")) and (.checks.workspace.status|IN("pass","fail","skip")) and (.checks.home_project.status|IN("pass","fail","skip")) and (.checks.obs_build.status|IN("pass","fail","skip"))'

__cog_osc_preflight_usage() {
  cog::fn::ui_data "Usage: cog osc-preflight (<out.json>|--json)"
}

__cog_osc_preflight_step_json() {
  local status="$1" ok="$2" reason="$3" remediation="$4" details="$5"
  jq -n \
    --arg status "$status" \
    --argjson ok "$ok" \
    --arg reason "$reason" \
    --arg remediation "$remediation" \
    --argjson details "$details" \
    '{
      status: $status,
      ok: $ok,
      required: true,
      reason: (if $reason == "" then null else $reason end),
      remediation: (if $remediation == "" then null else $remediation end),
      details: $details
    }'
  return 0
}

__cog_osc_preflight_stderr_snippet() {
  local file="$1"
  if [[ ! -f $file ]]; then
    printf '%s\n' ""
    return 0
  fi
  LC_ALL=C head -c 1000 "$file"
  return 0
}

__cog_osc_preflight_auth_class_for() {
  local text="$1"
  if [[ $text == *401* ]]; then
    printf '%s\n' creds_invalid
  elif [[ $text == *"Unable to instantiate creds mgr"* ]]; then
    printf '%s\n' keyring_unavailable
  else
    printf '%s\n' network
  fi
  return 0
}

__cog_osc_preflight_first_failure_reason() {
  jq -r '
    .checks
    | [to_entries[] | select(.value.status != "pass") | .value.reason // .key]
    | .[0] // ""
  '
  return 0
}

__cog_osc_preflight_build_json() {
  local api home_project workspace oscrc obs_build_vc osc_path timeout_cmd
  local env_check osc_binary_check credentials_check auth_probe_check workspace_check home_project_check obs_build_check
  local ok reason api_pattern user stdout_file stderr_file exit_code stderr_text auth_class

  api="${OBS_API:-https://api.opensuse.org}"
  home_project="${OBS_HOME_PROJECT:-}"
  workspace="${OBS_WORKSPACE:-$HOME/Projects/_obs-work}"
  oscrc="$HOME/.config/osc/oscrc"
  obs_build_vc="${OBS_BUILD_VC:-/usr/lib/build/vc}"
  timeout_cmd="${OSC_AUTH_TIMEOUT:-15s}"

  if [[ -n $home_project ]]; then
    env_check="$(__cog_osc_preflight_step_json pass true "" "" "{}")"
  else
    env_check="$(__cog_osc_preflight_step_json fail false "missing OBS_HOME_PROJECT" "Set OBS_HOME_PROJECT before invoking osc-obs." "{}")"
  fi

  osc_path=""
  if __have osc; then
    osc_path="$(command -v osc)"
    osc_binary_check="$(__cog_osc_preflight_step_json pass true "" "" "$(jq -n --arg path "$osc_path" '{path: $path}')")"
  else
    osc_binary_check="$(__cog_osc_preflight_step_json fail false "osc binary missing" "Install osc before retrying; do not run interactive self-repair from this helper." "$(jq -n '{path: null}')")"
  fi

  api_pattern="$(printf '%s' "$api" | sed 's|/$||')"
  if [[ -f $oscrc ]] && grep -qE "^\[${api_pattern}/?\]" "$oscrc"; then
    credentials_check="$(__cog_osc_preflight_step_json pass true "" "" "$(jq -n --arg oscrc "$oscrc" --arg api "$api" '{oscrc: $oscrc, api: $api}')")"
  else
    credentials_check="$(__cog_osc_preflight_step_json fail false "no credentials for $api in oscrc" "Seed ~/.config/osc/oscrc for the configured API before running osc commands." "$(jq -n --arg oscrc "$oscrc" --arg api "$api" '{oscrc: $oscrc, api: $api}')")"
  fi

  if [[ -z $osc_path ]]; then
    auth_probe_check="$(__cog_osc_preflight_step_json skip false "osc binary missing" "" "{}")"
  elif ! __have timeout; then
    auth_probe_check="$(__cog_osc_preflight_step_json fail false "timeout command missing" "Install coreutils timeout or provide a bounded execution environment." "{}")"
  elif [[ ! -f $oscrc ]]; then
    auth_probe_check="$(__cog_osc_preflight_step_json skip false "oscrc missing" "" "{}")"
  else
    user="$(awk -F'=' '/^user[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$oscrc")"
    if [[ -z $user ]]; then
      auth_probe_check="$(__cog_osc_preflight_step_json fail false "oscrc user missing" "Seed oscrc with a user entry for the configured API." "$(jq -n '{user: null}')")"
    else
      stdout_file="$(mktemp)"
      stderr_file="$(mktemp)"
      if timeout "$timeout_cmd" osc -A "$api" api "/person/${user}" >"$stdout_file" 2>"$stderr_file"; then
        auth_probe_check="$(__cog_osc_preflight_step_json pass true "" "" "$(jq -n --arg user "$user" '{user: $user}')")"
      else
        exit_code="$?"
        stderr_text="$(__cog_osc_preflight_stderr_snippet "$stderr_file")"
        auth_class="$(__cog_osc_preflight_auth_class_for "$stderr_text")"
        auth_probe_check="$(
          __cog_osc_preflight_step_json fail false "osc auth probe failed" "Use the matching osc-obs auth remediation for details.auth_class." "$(
            jq -n \
              --arg user "$user" \
              --arg auth_class "$auth_class" \
              --arg stderr "$stderr_text" \
              --argjson exit_code "$exit_code" \
              '{user: $user, auth_class: $auth_class, stderr: $stderr, exit_code: $exit_code}'
          )"
        )"
      fi
      rm -f "$stdout_file" "$stderr_file"
    fi
  fi

  if [[ -d $workspace ]]; then
    workspace_check="$(__cog_osc_preflight_step_json pass true "" "" "$(jq -n --arg path "$workspace" '{path: $path}')")"
  else
    workspace_check="$(__cog_osc_preflight_step_json fail false "workspace $workspace missing" "Create the workspace root or export a different OBS_WORKSPACE before retrying." "$(jq -n --arg path "$workspace" '{path: $path}')")"
  fi

  if [[ -z $osc_path ]]; then
    home_project_check="$(__cog_osc_preflight_step_json skip false "osc binary missing" "" "{}")"
  elif ! __have timeout; then
    home_project_check="$(__cog_osc_preflight_step_json fail false "timeout command missing" "Install coreutils timeout or provide a bounded execution environment." "{}")"
  elif [[ -z $home_project ]]; then
    home_project_check="$(__cog_osc_preflight_step_json skip false "OBS_HOME_PROJECT missing" "" "{}")"
  else
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    if timeout "$timeout_cmd" osc -A "$api" meta prj "$home_project" >"$stdout_file" 2>"$stderr_file"; then
      home_project_check="$(__cog_osc_preflight_step_json pass true "" "" "$(jq -n --arg project "$home_project" '{project: $project}')")"
    else
      exit_code="$?"
      stderr_text="$(__cog_osc_preflight_stderr_snippet "$stderr_file")"
      home_project_check="$(
        __cog_osc_preflight_step_json fail false "OBS home project probe failed" "Provision the OBS home project outside this helper before retrying." "$(
          jq -n \
            --arg project "$home_project" \
            --arg stderr "$stderr_text" \
            --argjson exit_code "$exit_code" \
            '{project: $project, stderr: $stderr, exit_code: $exit_code}'
        )"
      )"
    fi
    rm -f "$stdout_file" "$stderr_file"
  fi

  if [[ -x $obs_build_vc ]]; then
    obs_build_check="$(__cog_osc_preflight_step_json pass true "" "" "$(jq -n --arg path "$obs_build_vc" '{path: $path}')")"
  else
    obs_build_check="$(__cog_osc_preflight_step_json fail false "obs-build vc missing" "Install obs-build or bake it into the environment before maintainer flows that require osc vc." "$(jq -n --arg path "$obs_build_vc" '{path: $path}')")"
  fi

  ok=false
  if jq -e '.status == "pass"' <<<"$env_check" >/dev/null \
    && jq -e '.status == "pass"' <<<"$osc_binary_check" >/dev/null \
    && jq -e '.status == "pass"' <<<"$credentials_check" >/dev/null \
    && jq -e '.status == "pass"' <<<"$auth_probe_check" >/dev/null \
    && jq -e '.status == "pass"' <<<"$workspace_check" >/dev/null \
    && jq -e '.status == "pass"' <<<"$home_project_check" >/dev/null \
    && jq -e '.status == "pass"' <<<"$obs_build_check" >/dev/null; then
    ok=true
  fi

  reason="$(
    jq -n \
      --argjson env "$env_check" \
      --argjson osc_binary "$osc_binary_check" \
      --argjson credentials "$credentials_check" \
      --argjson auth_probe "$auth_probe_check" \
      --argjson workspace_check "$workspace_check" \
      --argjson home_project "$home_project_check" \
      --argjson obs_build "$obs_build_check" \
      '{
        checks: {
          env: $env,
          osc_binary: $osc_binary,
          credentials: $credentials,
          auth_probe: $auth_probe,
          workspace: $workspace_check,
          home_project: $home_project,
          obs_build: $obs_build
        }
      }' | __cog_osc_preflight_first_failure_reason
  )"

  jq -n \
    --argjson ok "$ok" \
    --arg api "$api" \
    --arg home_project "$home_project" \
    --arg workspace "$workspace" \
    --arg osc_path "$osc_path" \
    --arg oscrc "$oscrc" \
    --argjson env "$env_check" \
    --argjson osc_binary "$osc_binary_check" \
    --argjson credentials "$credentials_check" \
    --argjson auth_probe "$auth_probe_check" \
    --argjson workspace_check "$workspace_check" \
    --argjson home_project_check "$home_project_check" \
    --argjson obs_build "$obs_build_check" \
    --arg reason "$reason" \
    '{
      ok: $ok,
      api: $api,
      home_project: (if $home_project == "" then null else $home_project end),
      workspace: $workspace,
      osc_path: (if $osc_path == "" then null else $osc_path end),
      oscrc: $oscrc,
      checks: {
        env: $env,
        osc_binary: $osc_binary,
        credentials: $credentials,
        auth_probe: $auth_probe,
        workspace: $workspace_check,
        home_project: $home_project_check,
        obs_build: $obs_build
      },
      reason: (if $ok then null else $reason end)
    }'
  return 0
}

cog::cmd::osc_preflight() {
  local mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_osc_preflight_usage
        return 0
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate osc-preflight output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown osc-preflight option" "option: $1" "" "run 'cog osc-preflight --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many osc-preflight output paths" "argument: $1" "" "run 'cog osc-preflight --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing osc-preflight output mode" "usage: cog osc-preflight (<out.json>|--json)" "" "run 'cog osc-preflight --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_osc_preflight_build_json)"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_osc_preflight_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_osc_preflight_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
