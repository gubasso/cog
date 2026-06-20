# shellcheck shell=bash
: 'desc: Store and validate dated research findings.'

__cog_research_shelf_self_check='(.schema=="cog.research-shelf.v1") and (.ok|type=="boolean") and (.action|type=="string") and (.root|type=="string") and (.index|type=="string")'

__cog_research_shelf_usage() {
  cog::fn::ui_data "Usage: cog research-shelf init [--root <dir>] [--json]"
  cog::fn::ui_data "Usage: cog research-shelf record [--root <dir>] [--id <id>] --topic-tags <csv> --source-json <json> [--source-json <json> ...] --summary <text> --revalidate-after <date> --consuming-skills <csv> [--recorded-date <date>] [--json]"
  cog::fn::ui_data "Usage: cog research-shelf list [--root <dir>] [--json]"
  cog::fn::ui_data "Usage: cog research-shelf get <id> [--root <dir>] [--json]"
  cog::fn::ui_data "Usage: cog research-shelf validate [--root <dir>] [--json]"
}

__cog_research_shelf_emit() {
  local json="$1"
  local json_mode="$2"

  if [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_research_shelf_self_check" "$json"
    return 0
  fi
  return 1
}

__cog_research_shelf_init() {
  local root_override="" json_mode=false root json index

  while (($# > 0)); do
    case "$1" in
      --root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing research shelf root" "option: --root" "" "run 'cog research-shelf --help'"
        root_override="$2"
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown research-shelf init option" "option: $1" "" "run 'cog research-shelf --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "too many research-shelf init arguments" "argument: $1" "" \
          "run 'cog research-shelf --help'"
        ;;
    esac
  done

  root="$(cog::fn::research::root "$root_override")"
  json="$(cog::fn::research::init_json "$root")"
  __cog_research_shelf_emit "$json" "$json_mode" && return 0

  index="$(jq -r '.index' <<<"$json")"
  cog::fn::ui_data "RESHELF_ROOT=${root}"
  cog::fn::ui_data "RESHELF_INDEX=${index}"
  cog::fn::ui_data "RESHELF_INIT_OK"
}

__cog_research_shelf_record() {
  local root_override="" json_mode=false id="" topic_tags="" summary="" revalidate_after=""
  local consuming_skills="" recorded_date=""
  local root tags_json sources_json skills_json entry_without_id entry_json generated_id json index
  local -a source_jsons=()

  while (($# > 0)); do
    case "$1" in
      --root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing research shelf root" "option: --root" "" "run 'cog research-shelf --help'"
        root_override="$2"
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      --id)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing research shelf id" "option: --id" "" "run 'cog research-shelf --help'"
        id="$2"
        shift 2
        ;;
      --topic-tags)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing research shelf topic tags" "option: --topic-tags" "" \
          "run 'cog research-shelf --help'"
        topic_tags="$2"
        shift 2
        ;;
      --source-json)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing research shelf source JSON" "option: --source-json" "" \
          "run 'cog research-shelf --help'"
        cog::fn::research::source_json_validate "$2"
        source_jsons+=("$(jq -cS '.' <<<"$2")")
        shift 2
        ;;
      --summary)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing research shelf summary" "option: --summary" "" \
          "run 'cog research-shelf --help'"
        summary="$2"
        shift 2
        ;;
      --revalidate-after)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing research shelf revalidation date" "option: --revalidate-after" "" \
          "run 'cog research-shelf --help'"
        revalidate_after="$2"
        shift 2
        ;;
      --consuming-skills)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing research shelf consuming skills" "option: --consuming-skills" "" \
          "run 'cog research-shelf --help'"
        consuming_skills="$2"
        shift 2
        ;;
      --recorded-date)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing research shelf recorded date" "option: --recorded-date" "" \
          "run 'cog research-shelf --help'"
        recorded_date="$2"
        shift 2
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown research-shelf record option" "option: $1" "" "run 'cog research-shelf --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "too many research-shelf record arguments" "argument: $1" "" \
          "run 'cog research-shelf --help'"
        ;;
    esac
  done

  [[ -n $topic_tags ]] || cog::fn::error_raise "MissingArgument" \
    "missing research shelf topic tags" "option: --topic-tags" "" "run 'cog research-shelf --help'"
  ((${#source_jsons[@]} > 0)) || cog::fn::error_raise "MissingArgument" \
    "missing research shelf source" "option: --source-json" "" "run 'cog research-shelf --help'"
  [[ -n $summary ]] || cog::fn::error_raise "MissingArgument" \
    "missing research shelf summary" "option: --summary" "" "run 'cog research-shelf --help'"
  [[ -n $revalidate_after ]] || cog::fn::error_raise "MissingArgument" \
    "missing research shelf revalidation date" "option: --revalidate-after" "" \
    "run 'cog research-shelf --help'"
  [[ -n $consuming_skills ]] || cog::fn::error_raise "MissingArgument" \
    "missing research shelf consuming skills" "option: --consuming-skills" "" \
    "run 'cog research-shelf --help'"

  if [[ -z $recorded_date ]]; then
    recorded_date="$(date -u +%F)"
  fi
  cog::fn::research::date_valid "$recorded_date" || cog::fn::error_raise "InvalidInput" \
    "invalid research shelf recorded date" "recorded-date: ${recorded_date}" \
    "expected YYYY-MM-DD" "pass --recorded-date YYYY-MM-DD"
  cog::fn::research::date_valid "$revalidate_after" || cog::fn::error_raise "InvalidInput" \
    "invalid research shelf revalidation date" "revalidate-after: ${revalidate_after}" \
    "expected YYYY-MM-DD" "pass --revalidate-after YYYY-MM-DD"

  tags_json="$(cog::fn::research::csv_json "$topic_tags" "topic-tags")"
  skills_json="$(cog::fn::research::csv_json "$consuming_skills" "consuming-skills")"
  sources_json="$(printf '%s\n' "${source_jsons[@]}" | jq -s -c '.')"
  entry_without_id="$(jq -n -cS \
    --arg recorded_date "$recorded_date" \
    --arg stable_summary "$summary" \
    --arg revalidate_after "$revalidate_after" \
    --argjson topic_tags "$tags_json" \
    --argjson sources "$sources_json" \
    --argjson consuming_skills "$skills_json" \
    '{"recorded-date": $recorded_date,
      "topic-tags": $topic_tags,
      sources: $sources,
      "stable-summary": $stable_summary,
      "revalidate-after": $revalidate_after,
      "consuming-skills": $consuming_skills}')"

  if [[ -z $id ]]; then
    generated_id="$(cog::fn::research::entry_generate_id "$entry_without_id")"
    id="$generated_id"
  fi
  entry_json="$(jq -cS --arg id "$id" '. + {id: $id}' <<<"$entry_without_id")"

  root="$(cog::fn::research::root "$root_override")"
  json="$(cog::fn::research::record_json "$root" "$entry_json")"
  __cog_research_shelf_emit "$json" "$json_mode" && return 0

  index="$(jq -r '.index' <<<"$json")"
  cog::fn::ui_data "RESHELF_ID=${id}"
  cog::fn::ui_data "RESHELF_INDEX=${index}"
  cog::fn::ui_data "RESHELF_RECORDED"
}

__cog_research_shelf_list() {
  local root_override="" json_mode=false root json

  while (($# > 0)); do
    case "$1" in
      --root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing research shelf root" "option: --root" "" "run 'cog research-shelf --help'"
        root_override="$2"
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown research-shelf list option" "option: $1" "" "run 'cog research-shelf --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "too many research-shelf list arguments" "argument: $1" "" \
          "run 'cog research-shelf --help'"
        ;;
    esac
  done

  root="$(cog::fn::research::root "$root_override")"
  json="$(cog::fn::research::list_json "$root")"
  __cog_research_shelf_emit "$json" "$json_mode" && return 0
  local id
  while IFS= read -r id; do
    cog::fn::ui_data "RESHELF_ID=${id}"
  done < <(jq -r '.entries[].id' <<<"$json")
}

__cog_research_shelf_get() {
  local root_override="" json_mode=false id="" root json

  while (($# > 0)); do
    case "$1" in
      --root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing research shelf root" "option: --root" "" "run 'cog research-shelf --help'"
        root_override="$2"
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown research-shelf get option" "option: $1" "" "run 'cog research-shelf --help'"
        ;;
      *)
        [[ -z $id ]] || cog::fn::error_raise "InvalidInput" \
          "too many research-shelf get arguments" "argument: $1" "" \
          "run 'cog research-shelf --help'"
        id="$1"
        shift
        ;;
    esac
  done

  [[ -n $id ]] || cog::fn::error_raise "MissingArgument" \
    "missing research shelf id" "usage: cog research-shelf get <id>" "" \
    "run 'cog research-shelf --help'"
  root="$(cog::fn::research::root "$root_override")"
  json="$(cog::fn::research::get_json "$root" "$id")"
  __cog_research_shelf_emit "$json" "$json_mode" && return 0
  cog::fn::ui_data "$(jq -c '.entry' <<<"$json")"
}

__cog_research_shelf_validate() {
  local root_override="" json_mode=false root json index entries

  while (($# > 0)); do
    case "$1" in
      --root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing research shelf root" "option: --root" "" "run 'cog research-shelf --help'"
        root_override="$2"
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown research-shelf validate option" "option: $1" "" \
          "run 'cog research-shelf --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "too many research-shelf validate arguments" "argument: $1" "" \
          "run 'cog research-shelf --help'"
        ;;
    esac
  done

  root="$(cog::fn::research::root "$root_override")"
  json="$(cog::fn::research::validate_json "$root")"
  if [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_research_shelf_self_check" "$json"
    jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
    return 0
  fi

  if ! jq -e '.ok == true' <<<"$json" >/dev/null; then
    cog::fn::error_raise "InvalidInput" \
      "research shelf failed validation" "path: $(jq -r '.index' <<<"$json")" \
      "$(jq -c '.' <<<"$json")" "fix malformed, undated, unsourced, or duplicate entries"
  fi

  index="$(jq -r '.index' <<<"$json")"
  entries="$(jq -r '.entries' <<<"$json")"
  cog::fn::ui_data "RESHELF_INDEX=${index}"
  cog::fn::ui_data "RESHELF_ENTRIES=${entries}"
  cog::fn::ui_data "RESHELF_VALID"
}

cog::cmd::research_shelf() {
  local mode="${1:-}"

  case "$mode" in
    -h | --help)
      __cog_research_shelf_usage
      ;;
    init)
      shift
      __cog_research_shelf_init "$@"
      ;;
    record)
      shift
      __cog_research_shelf_record "$@"
      ;;
    list)
      shift
      __cog_research_shelf_list "$@"
      ;;
    get)
      shift
      __cog_research_shelf_get "$@"
      ;;
    validate)
      shift
      __cog_research_shelf_validate "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" \
        "missing research-shelf mode" "usage: cog research-shelf init|record|list|get|validate" "" \
        "run 'cog research-shelf --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown research-shelf mode" "mode: ${mode}" "" "run 'cog research-shelf --help'"
      ;;
  esac
}
