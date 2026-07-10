# shellcheck shell=bash
: 'desc: Check or stamp bootstrap template review freshness.'

__cog_bootstrap_template_review_check_self_check='(.schema=="cog.bootstrap-template-review.v1") and (.action=="check") and (.review|type=="object") and (.review.fresh|type=="boolean") and (.review.state|type=="string") and (.template_roots|type=="array") and (.skill_refs|type=="object")'

__cog_bootstrap_template_review_stamp_self_check='(.schema=="cog.bootstrap-template-review.v1") and (.action=="stamp") and (.entry_id|type=="string") and (.revalidate_after|type=="string") and (.changed_templates|type=="array") and (.skill_refs|type=="object")'

__cog_bootstrap_template_review_usage() {
  cog::fn::ui_data "Usage: cog bootstrap-template-review check --domain <d> --type <t> [--research-root <dir>] --json"
  cog::fn::ui_data "Usage: cog bootstrap-template-review stamp --domain <d> --type <t> --summary <text> --source-json <json> [--source-json <json> ...] [--changed-template <path> ...] [--research-root <dir>] [--freshness-days <n>] --json"
}

__cog_bootstrap_template_review_require_domain() {
  local domain="$1"
  [[ -n $domain ]] || cog::fn::error_raise "MissingArgument" \
    "missing bootstrap review domain" "option: --domain" "" \
    "run 'cog bootstrap-template-review --help'"
  cog::fn::bootstrap_review::valid_domain "$domain" || cog::fn::error_raise "InvalidInput" \
    "unknown bootstrap review domain" "domain: ${domain}" \
    "expected precommit|editorconfig|nix|repo|ci|taskrunner|governance|cargo-publish|installer" \
    "pass a supported --domain"
}

__cog_bootstrap_template_review_require_type() {
  local type="$1"
  [[ -n $type ]] || cog::fn::error_raise "MissingArgument" \
    "missing bootstrap review type" "option: --type" "" \
    "run 'cog bootstrap-template-review --help'"
  [[ $type =~ ^[a-z0-9-]+$ ]] || cog::fn::error_raise "InvalidInput" \
    "invalid bootstrap review type" "type: ${type}" "type must match ^[a-z0-9-]+$" \
    "pass a lowercase --type such as rust, python, or generic"
}

__cog_bootstrap_template_review_validate_days() {
  local days="$1"
  [[ -z $days ]] && return 0
  [[ $days =~ ^[1-9][0-9]*$ ]] || cog::fn::error_raise "InvalidInput" \
    "invalid freshness window" "freshness-days: ${days}" "expected a positive integer" \
    "pass --freshness-days with a positive integer"
}

__cog_bootstrap_template_review_check() {
  local domain="" type="" research_root="" json_mode=false json

  while (($# > 0)); do
    case "$1" in
      --domain)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing --domain value" "option: --domain" "" "run 'cog bootstrap-template-review --help'"
        domain="$2"
        shift 2
        ;;
      --type)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing --type value" "option: --type" "" "run 'cog bootstrap-template-review --help'"
        type="$2"
        shift 2
        ;;
      --research-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing --research-root value" "option: --research-root" "" "run 'cog bootstrap-template-review --help'"
        research_root="$2"
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown bootstrap-template-review check option" "option: $1" "" "run 'cog bootstrap-template-review --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "unexpected bootstrap-template-review check argument" "argument: $1" "" "run 'cog bootstrap-template-review --help'" ;;
    esac
  done

  __cog_bootstrap_template_review_require_domain "$domain"
  __cog_bootstrap_template_review_require_type "$type"
  [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" \
    "missing bootstrap-template-review output mode" "usage: cog bootstrap-template-review check ... --json" "" \
    "pass --json"

  json="$(cog::fn::bootstrap_review::check_json "$domain" "$type" "$research_root")"
  cog::fn::json_emit "$__cog_bootstrap_template_review_check_self_check" "$json"
  jq -e '.ok == true' <<<"$json" >/dev/null
}

__cog_bootstrap_template_review_stamp() {
  local domain="" type="" summary="" research_root="" freshness_days="" json_mode=false json
  local -a source_jsons=() changed=()

  while (($# > 0)); do
    case "$1" in
      --domain)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing --domain value" "option: --domain" "" "run 'cog bootstrap-template-review --help'"
        domain="$2"
        shift 2
        ;;
      --type)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing --type value" "option: --type" "" "run 'cog bootstrap-template-review --help'"
        type="$2"
        shift 2
        ;;
      --summary)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing --summary value" "option: --summary" "" "run 'cog bootstrap-template-review --help'"
        summary="$2"
        shift 2
        ;;
      --source-json)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing --source-json value" "option: --source-json" "" "run 'cog bootstrap-template-review --help'"
        cog::fn::research::source_json_validate "$2"
        source_jsons+=("$(jq -cS '.' <<<"$2")")
        shift 2
        ;;
      --changed-template)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing --changed-template value" "option: --changed-template" "" "run 'cog bootstrap-template-review --help'"
        changed+=("$2")
        shift 2
        ;;
      --research-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing --research-root value" "option: --research-root" "" "run 'cog bootstrap-template-review --help'"
        research_root="$2"
        shift 2
        ;;
      --freshness-days)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing --freshness-days value" "option: --freshness-days" "" "run 'cog bootstrap-template-review --help'"
        freshness_days="$2"
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown bootstrap-template-review stamp option" "option: $1" "" "run 'cog bootstrap-template-review --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "unexpected bootstrap-template-review stamp argument" "argument: $1" "" "run 'cog bootstrap-template-review --help'" ;;
    esac
  done

  __cog_bootstrap_template_review_require_domain "$domain"
  __cog_bootstrap_template_review_require_type "$type"
  __cog_bootstrap_template_review_validate_days "$freshness_days"
  [[ -n $summary ]] || cog::fn::error_raise "MissingArgument" \
    "missing bootstrap review summary" "option: --summary" "" "run 'cog bootstrap-template-review --help'"
  ((${#source_jsons[@]} > 0)) || cog::fn::error_raise "MissingArgument" \
    "missing bootstrap review source" "option: --source-json" "" "run 'cog bootstrap-template-review --help'"
  [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" \
    "missing bootstrap-template-review output mode" "usage: cog bootstrap-template-review stamp ... --json" "" \
    "pass --json"

  local sources_json changed_json
  sources_json="$(printf '%s\n' "${source_jsons[@]}" | jq -s -c '.')"
  if ((${#changed[@]} > 0)); then
    changed_json="$(printf '%s\n' "${changed[@]}" | jq -R . | jq -s -c '.')"
  else
    changed_json='[]'
  fi

  json="$(cog::fn::bootstrap_review::stamp_json "$domain" "$type" "$summary" "$sources_json" "$changed_json" "$research_root" "$freshness_days")"
  cog::fn::json_emit "$__cog_bootstrap_template_review_stamp_self_check" "$json"
}

cog::cmd::bootstrap_template_review() {
  local mode="${1:-}"
  case "$mode" in
    -h | --help)
      __cog_bootstrap_template_review_usage
      ;;
    check)
      shift
      __cog_bootstrap_template_review_check "$@"
      ;;
    stamp)
      shift
      __cog_bootstrap_template_review_stamp "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" "missing bootstrap-template-review mode" \
        "usage: cog bootstrap-template-review check|stamp" "" \
        "run 'cog bootstrap-template-review --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" "unknown bootstrap-template-review mode" \
        "mode: ${mode}" "" "run 'cog bootstrap-template-review --help'"
      ;;
  esac
}
