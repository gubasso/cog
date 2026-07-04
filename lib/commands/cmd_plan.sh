# shellcheck shell=bash
: 'desc: Resolve and manage plan stores.'

__cog_plan_store_self_check='(.schema == "cog.plan.store.v1") and (.ok|type=="boolean") and (.store_root|type=="string")'
__cog_plan_resolve_self_check='(.schema == "cog.plan.resolve.v1") and (.ok == true) and (.store|type=="string") and (.plan_root|type=="string") and (.plans_dir|type=="string") and (.queue_path|type=="string") and (.project_key|type=="string") and (.identity|type=="object") and (.trust|type=="object") and (.sources|type=="object")'
__cog_plan_trust_self_check='(.schema == "cog.plan.trust.v1") and (.ok == true) and (.project_key|type=="string") and (.status|type=="string")'
__cog_plan_doctor_self_check='(.schema == "cog.plan.doctor.v1") and (.ok|type=="boolean") and (.xdg_data_home|type=="string") and (.xdg_state_home|type=="string") and (.store_root|type=="string") and (.trust_db_path|type=="string") and (.resolved|type=="object")'
__cog_plan_item_self_check='(.schema == "cog.plan.item.v1") and (.ok == true) and (.plan_root|type=="string") and (.plan_slug|type=="string") and (.plan_dir|type=="string")'
__cog_plan_item_list_self_check='(.schema == "cog.plan.item-list.v1") and (.ok == true) and (.plan_root|type=="string") and (.plans|type=="array")'
__cog_plan_item_path_self_check='(.schema == "cog.plan.item-path.v1") and (.ok == true) and (.plan_root|type=="string") and (.plan_slug|type=="string") and (.plan_dir|type=="string")'
__cog_plan_runner_resolve_self_check='(.schema == "cog.plan.runner-resolve.v1") and (.ok == true) and (.store|type=="string") and (.plan_root|type=="string" and startswith("/")) and (.main_queue|type=="string" and startswith("/")) and (.project_key|type=="string") and (.target_type|test("^(plan-dir|main-queue)$")) and (has("plan_dir")) and (has("inner_queue_path"))'

__cog_plan_usage() {
  cog::fn::ui_data "Usage: cog plan store path [--json]"
  cog::fn::ui_data "Usage: cog plan store init [--global|--local] [--no-git] [--json]"
  cog::fn::ui_data "Usage: cog plan project resolve [--project-root <dir>] [--plan-root <dir>] [--store auto|local|global] [--json]"
  cog::fn::ui_data "Usage: cog plan project link [--root <dir>] [--name <alias>] [--json]"
  cog::fn::ui_data "Usage: cog plan project list [--json]"
  cog::fn::ui_data "Usage: cog plan trust|distrust|trust-status [--project-root <dir>] [--json]"
  cog::fn::ui_data "Usage: cog plan doctor [--json]"
  cog::fn::ui_data "Usage: cog plan new --title <text> [--local|--global] [--no-git] [--project-root <dir>] [--json]"
  cog::fn::ui_data "Usage: cog plan list [--local|--global] [--project-root <dir>] [--json]"
  cog::fn::ui_data "Usage: cog plan path <plan-id> [--local|--global] [--project-root <dir>] [--json]"
  cog::fn::ui_data "Usage: cog plan runner-resolve --target <plan_dir|queue> [--project-root <dir>] [--json]"
}

__cog_plan_emit() {
  local self_check="$1" json="$2" want_json="${3:-false}" text="${4:-}"
  if [[ $want_json == true || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$self_check" "$json"
  else
    if [[ -n $text ]]; then
      cog::fn::ui_data "$text"
    else
      cog::fn::json_emit "$self_check" "$json"
    fi
  fi
}

__cog_plan_store_path_cmd() {
  local want_json=false root json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_usage
        return 0
        ;;
      --json)
        want_json=true
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown plan store path option" "option: $1" "" "run 'cog plan --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "too many plan store path arguments" "argument: $1" "" "run 'cog plan --help'" ;;
    esac
  done
  root="$(cog::fn::plan_store_root)"
  json="$(jq -n --arg schema "cog.plan.store.v1" --arg store_root "$root" \
    '{schema: $schema, ok: true, store_root: $store_root}')"
  __cog_plan_emit "$__cog_plan_store_self_check" "$json" "$want_json" "$root"
}

__cog_plan_store_init_cmd() {
  local scope="global" with_git=true want_json=false project_root init_root store_root json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_usage
        return 0
        ;;
      --global)
        scope="global"
        shift
        ;;
      --local)
        scope="local"
        shift
        ;;
      --no-git)
        with_git=false
        shift
        ;;
      --git)
        cog::fn::error_raise "InvalidInput" \
          "the --git flag was removed" "option: --git" \
          "the global plan vault is git-by-default (ADR-0057)" \
          "drop --git, or pass --no-git to skip git initialization"
        ;;
      --project-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing project root" "option: --project-root" "" "run 'cog plan --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        want_json=true
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown plan store init option" "option: $1" "" "run 'cog plan --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "too many plan store init arguments" "argument: $1" "" "run 'cog plan --help'" ;;
    esac
  done
  store_root="$(cog::fn::plan_store_root)"
  case "$scope" in
    global)
      cog::fn::plan_store_init_global "$with_git"
      init_root="$store_root"
      ;;
    local)
      # Resolve trust mode through the layered plan config (defaults < user <
      # overlays < project < env), not a bare env read, so config-file and env
      # layers are honored identically to `cog plan project resolve`.
      # __init_plan_source/__init_plan_line are filled via config-loader namerefs
      # (invisible to shellcheck) — suppress the false SC2034.
      # shellcheck disable=SC2034
      local -A __init_plan_config=() __init_plan_source=() __init_plan_line=()
      local init_trust_mode init_home init_local_dir
      cog::fn::plan_config_load "$project_root" __init_plan_config __init_plan_source __init_plan_line
      init_trust_mode="${__init_plan_config[COG_PLAN_TRUST]:-strict}"
      init_home="${__init_plan_config[COG_PLAN_HOME]}"
      init_local_dir="${__init_plan_config[COG_PLAN_LOCAL_DIR]}"
      if [[ "$(jq -r '.status' <<<"$(COG_PLAN_HOME="$init_home" COG_PLAN_LOCAL_DIR="$init_local_dir" cog::fn::plan_trust_status_json "$project_root")")" != "trusted" && $init_trust_mode != off ]]; then
        cog::fn::error_raise "InvalidInput" \
          "local plan root is not trusted" "project-root: ${project_root}" "" \
          "run 'cog plan trust --project-root ${project_root}' first"
      fi
      init_root="$(COG_PLAN_HOME="$init_home" COG_PLAN_LOCAL_DIR="$init_local_dir" cog::fn::plan_project_init_local "$project_root")"
      ;;
  esac
  json="$(jq -n --arg schema "cog.plan.store.v1" --arg store_root "$store_root" --arg initialized "$init_root" --arg scope "$scope" \
    '{schema: $schema, ok: true, store_root: $store_root, initialized: $initialized, scope: $scope}')"
  __cog_plan_emit "$__cog_plan_store_self_check" "$json" "$want_json" "$init_root"
}

__cog_plan_project_resolve_cmd() {
  local project_root="" plan_root="" store="" want_json=false json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing project root" "option: --project-root" "" "run 'cog plan --help'"
        project_root="$2"
        shift 2
        ;;
      --plan-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan root" "option: --plan-root" "" "run 'cog plan --help'"
        plan_root="$2"
        shift 2
        ;;
      --store)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing store value" "option: --store" "" "run 'cog plan --help'"
        store="$2"
        shift 2
        ;;
      --json)
        want_json=true
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown plan project resolve option" "option: $1" "" "run 'cog plan --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "too many plan project resolve arguments" "argument: $1" "" "run 'cog plan --help'" ;;
    esac
  done
  json="$(cog::fn::plan_resolve_json "$project_root" "$store" "$plan_root")"
  __cog_plan_emit "$__cog_plan_resolve_self_check" "$json" "$want_json" "$(jq -r '.plan_root' <<<"$json")"
}

__cog_plan_runner_resolve_cmd() {
  local project_root="" target="" want_json=false json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_usage
        return 0
        ;;
      --target)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing runner-resolve target" "option: --target" "" "run 'cog plan --help'"
        target="$2"
        shift 2
        ;;
      --project-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing project root" "option: --project-root" "" "run 'cog plan --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        want_json=true
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown plan runner-resolve option" "option: $1" "" "run 'cog plan --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "too many plan runner-resolve arguments" "argument: $1" "" "run 'cog plan --help'" ;;
    esac
  done
  [[ -n $target ]] || cog::fn::error_raise "MissingArgument" \
    "missing runner-resolve target" "option: --target" "" "pass --target <plan_dir|queue>"
  json="$(cog::fn::plan_runner_resolve_json "$project_root" "$target")"
  __cog_plan_emit "$__cog_plan_runner_resolve_self_check" "$json" "$want_json" \
    "$(jq -r 'if .target_type=="plan-dir" then .plan_dir else .main_queue end' <<<"$json")"
}

__cog_plan_project_link_cmd() {
  local root="" name="" want_json=false project_dir store_root alias_dir alias_file identity project_key json
  root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_usage
        return 0
        ;;
      --root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing root" "option: --root" "" "run 'cog plan --help'"
        root="$2"
        shift 2
        ;;
      --name)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing alias name" "option: --name" "" "run 'cog plan --help'"
        name="$2"
        shift 2
        ;;
      --json)
        want_json=true
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown plan project link option" "option: $1" "" "run 'cog plan --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "too many plan project link arguments" "argument: $1" "" "run 'cog plan --help'" ;;
    esac
  done
  project_dir="$(cog::fn::plan_project_init_global "$root")"
  store_root="$(cog::fn::plan_store_root)"
  identity="$(cog::fn::plan_project_identity_json "$root")"
  project_key="$(jq -r '.project_key' <<<"$identity")"
  if [[ -n $name ]]; then
    alias_dir="${store_root}/aliases"
    mkdir -p "$alias_dir" || cog::fn::error_raise "TempDirCreateFailed" "could not create aliases directory" "path: ${alias_dir}" "" "check permissions"
    alias_file="${alias_dir}/$(cog::fn::plan_slug::derive "$name").sh"
    printf '%s=%s\n' "COG_PLAN_PROJECT_KEY" "$(__cog_plan_quote_literal "$project_key")" >"$alias_file" \
      || cog::fn::error_raise "JsonWriteFailed" "could not write plan alias" "path: ${alias_file}" "" "check permissions"
  fi
  json="$(jq -n --arg schema "cog.plan.store.v1" --arg store_root "$store_root" --arg project_key "$project_key" --arg project_dir "$project_dir" \
    '{schema: $schema, ok: true, store_root: $store_root, project_key: $project_key, project_dir: $project_dir}')"
  __cog_plan_emit "$__cog_plan_store_self_check" "$json" "$want_json" "$project_key"
}

__cog_plan_project_list_cmd() {
  local want_json=false store_root projects_json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_usage
        return 0
        ;;
      --json)
        want_json=true
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown plan project list option" "option: $1" "" "run 'cog plan --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "too many plan project list arguments" "argument: $1" "" "run 'cog plan --help'" ;;
    esac
  done
  store_root="$(cog::fn::plan_store_root)"
  projects_json="$(find "${store_root}/projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | jq -R . | jq -s .)"
  projects_json="$(jq -n --arg schema "cog.plan.store.v1" --arg store_root "$store_root" --argjson projects "$projects_json" \
    '{schema: $schema, ok: true, store_root: $store_root, projects: $projects}')"
  __cog_plan_emit "$__cog_plan_store_self_check" "$projects_json" "$want_json" "$projects_json"
}

__cog_plan_trust_cmd() {
  local action="$1" project_root="" want_json=false json
  shift
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog plan --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        want_json=true
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown plan trust option" "option: $1" "" "run 'cog plan --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "too many plan trust arguments" "argument: $1" "" "run 'cog plan --help'" ;;
    esac
  done
  # Resolve the local-store location through the layered plan config (defaults <
  # user < overlays < project < env), not a bare env read, so the trust helpers
  # operate on the same local plan root that `cog plan project resolve` selects.
  # __trust_plan_source/__trust_plan_line are filled via config-loader namerefs
  # (invisible to shellcheck) — suppress the false SC2034.
  # shellcheck disable=SC2034
  local -A __trust_plan_config=() __trust_plan_source=() __trust_plan_line=()
  local trust_home trust_local_dir
  cog::fn::plan_config_load "$project_root" __trust_plan_config __trust_plan_source __trust_plan_line
  trust_home="${__trust_plan_config[COG_PLAN_HOME]}"
  trust_local_dir="${__trust_plan_config[COG_PLAN_LOCAL_DIR]}"
  case "$action" in
    trust) json="$(COG_PLAN_HOME="$trust_home" COG_PLAN_LOCAL_DIR="$trust_local_dir" cog::fn::plan_trust_allow "$project_root")" ;;
    distrust) json="$(COG_PLAN_HOME="$trust_home" COG_PLAN_LOCAL_DIR="$trust_local_dir" cog::fn::plan_trust_revoke "$project_root")" ;;
    trust-status) json="$(COG_PLAN_HOME="$trust_home" COG_PLAN_LOCAL_DIR="$trust_local_dir" cog::fn::plan_trust_status_json "$project_root")" ;;
  esac
  __cog_plan_emit "$__cog_plan_trust_self_check" "$json" "$want_json" "$(jq -r '.status' <<<"$json")"
}

__cog_plan_doctor_cmd() {
  local want_json=false project_root="" store_root trust_db resolved json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog plan --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        want_json=true
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown plan doctor option" "option: $1" "" "run 'cog plan --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "too many plan doctor arguments" "argument: $1" "" "run 'cog plan --help'" ;;
    esac
  done
  store_root="$(cog::fn::plan_store_root)"
  trust_db="$(cog::fn::plan_trust_db_path)"
  resolved="$(cog::fn::plan_resolve_json "$project_root" "" "")"
  json="$(jq -n \
    --arg schema "cog.plan.doctor.v1" \
    --arg xdg_data_home "${XDG_DATA_HOME:-$HOME/.local/share}" \
    --arg xdg_state_home "${XDG_STATE_HOME:-$HOME/.local/state}" \
    --arg store_root "$store_root" \
    --arg trust_db_path "$trust_db" \
    --argjson store_exists "$(if [[ -d $store_root ]]; then printf true; else printf false; fi)" \
    --argjson trust_db_exists "$(if [[ -f $trust_db ]]; then printf true; else printf false; fi)" \
    --argjson resolved "$resolved" \
    '{schema: $schema, ok: true, xdg_data_home: $xdg_data_home,
      xdg_state_home: $xdg_state_home, store_root: $store_root,
      store_exists: $store_exists, trust_db_path: $trust_db_path,
      trust_db_exists: $trust_db_exists, resolved: $resolved}')"
  __cog_plan_emit "$__cog_plan_doctor_self_check" "$json" "$want_json" "$json"
}

# Parse the store/project-root/json flags shared by the plan item commands.
# Echoes PROJECT_ROOT=, STORE=, WANT_JSON=, and any leftover positional args as
# ARG= lines (one per positional), for the caller to read.
__cog_plan_item_parse_common() {
  local project_root store="" want_json=false with_git=true
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_usage
        return 10
        ;;
      --global)
        store="global"
        shift
        ;;
      --local)
        store="local"
        shift
        ;;
      --no-git)
        with_git=false
        shift
        ;;
      --git)
        cog::fn::error_raise "InvalidInput" \
          "the --git flag was removed" "option: --git" \
          "the global plan vault is git-by-default (ADR-0057)" \
          "drop --git, or pass --no-git to skip git initialization"
        ;;
      --store)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing store value" "option: --store" "" "run 'cog plan --help'"
        store="$2"
        shift 2
        ;;
      --project-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog plan --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        want_json=true
        shift
        ;;
      --title)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing plan title" "option: --title" "" "run 'cog plan --help'"
        printf 'TITLE=%s\n' "$2"
        shift 2
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown plan item option" "option: $1" "" "run 'cog plan --help'" ;;
      *)
        printf 'ARG=%s\n' "$1"
        shift
        ;;
    esac
  done
  printf 'PROJECT_ROOT=%s\n' "$project_root"
  printf 'STORE=%s\n' "$store"
  printf 'WANT_JSON=%s\n' "$want_json"
  printf 'WITH_GIT=%s\n' "$with_git"
}

__cog_plan_item_new_cmd() {
  local parsed project_root store want_json title with_git json
  parsed="$(__cog_plan_item_parse_common "$@")" || return 0
  project_root="$(sed -n 's/^PROJECT_ROOT=//p' <<<"$parsed")"
  store="$(sed -n 's/^STORE=//p' <<<"$parsed")"
  want_json="$(sed -n 's/^WANT_JSON=//p' <<<"$parsed")"
  title="$(sed -n 's/^TITLE=//p' <<<"$parsed")"
  with_git="$(sed -n 's/^WITH_GIT=//p' <<<"$parsed")"
  json="$(cog::fn::plan_item_new "$project_root" "$store" "$title" "$with_git")"
  __cog_plan_emit "$__cog_plan_item_self_check" "$json" "$want_json" "$(jq -r '.plan_dir' <<<"$json")"
}

__cog_plan_item_list_cmd() {
  local parsed project_root store want_json json
  parsed="$(__cog_plan_item_parse_common "$@")" || return 0
  project_root="$(sed -n 's/^PROJECT_ROOT=//p' <<<"$parsed")"
  store="$(sed -n 's/^STORE=//p' <<<"$parsed")"
  want_json="$(sed -n 's/^WANT_JSON=//p' <<<"$parsed")"
  json="$(cog::fn::plan_item_list "$project_root" "$store")"
  __cog_plan_emit "$__cog_plan_item_list_self_check" "$json" "$want_json" "$json"
}

__cog_plan_item_path_cmd() {
  local parsed project_root store want_json plan_id json
  parsed="$(__cog_plan_item_parse_common "$@")" || return 0
  project_root="$(sed -n 's/^PROJECT_ROOT=//p' <<<"$parsed")"
  store="$(sed -n 's/^STORE=//p' <<<"$parsed")"
  want_json="$(sed -n 's/^WANT_JSON=//p' <<<"$parsed")"
  plan_id="$(sed -n 's/^ARG=//p' <<<"$parsed" | head -n1)"
  json="$(cog::fn::plan_item_path "$project_root" "$store" "$plan_id")"
  __cog_plan_emit "$__cog_plan_item_path_self_check" "$json" "$want_json" "$(jq -r '.plan_dir' <<<"$json")"
}

cog::cmd::plan() {
  local area="${1:-}"
  case "$area" in
    -h | --help | "")
      __cog_plan_usage
      return 0
      ;;
    store)
      shift
      case "${1:-}" in
        path)
          shift
          __cog_plan_store_path_cmd "$@"
          ;;
        init)
          shift
          __cog_plan_store_init_cmd "$@"
          ;;
        -h | --help | "") __cog_plan_usage ;;
        *) cog::fn::error_raise "InvalidInput" "unknown plan store verb" "verb: ${1:-}" "" "run 'cog plan --help'" ;;
      esac
      ;;
    project)
      shift
      case "${1:-}" in
        resolve)
          shift
          __cog_plan_project_resolve_cmd "$@"
          ;;
        link)
          shift
          __cog_plan_project_link_cmd "$@"
          ;;
        list)
          shift
          __cog_plan_project_list_cmd "$@"
          ;;
        -h | --help | "") __cog_plan_usage ;;
        *) cog::fn::error_raise "InvalidInput" "unknown plan project verb" "verb: ${1:-}" "" "run 'cog plan --help'" ;;
      esac
      ;;
    trust | distrust | trust-status)
      __cog_plan_trust_cmd "$@"
      ;;
    doctor)
      shift
      __cog_plan_doctor_cmd "$@"
      ;;
    new)
      shift
      __cog_plan_item_new_cmd "$@"
      ;;
    list)
      shift
      __cog_plan_item_list_cmd "$@"
      ;;
    path)
      shift
      __cog_plan_item_path_cmd "$@"
      ;;
    runner-resolve)
      shift
      __cog_plan_runner_resolve_cmd "$@"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown plan area" "area: ${area}" "" "run 'cog plan --help'"
      ;;
  esac
}
