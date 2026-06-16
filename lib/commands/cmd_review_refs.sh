# shellcheck shell=bash
: 'desc: Resolve docs-n-notes review reference files.'

__cog_review_refs_self_check='.docs_notes_repo.relevant_agents_md != null'

__cog_review_refs_usage() {
  cog::fn::ui_data "Usage: cog review-refs --classification <file> [--docs-notes-repo <path>] (<out.json>|--json)"
  cog::fn::ui_data "Usage: cog review-refs <classification.json> (<out.json>|--json)"
}

__cog_review_refs_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

__cog_review_refs_build_json() {
  local classification_file="$1"
  local docs_override="$2"
  local classification is_cli docs_path="" available=false refs_json
  local -a langs=() refs=()

  [[ -r $classification_file ]] || cog::fn::error_raise "InputUnreadable" \
    "classification file is not readable" "path: ${classification_file}" "" "check the file path"
  classification="$(jq -c . "$classification_file" 2>/dev/null)" || cog::fn::error_raise "InvalidJsonInput" \
    "classification file is not valid JSON" "path: ${classification_file}" "" "check the file contents"

  is_cli="$(jq -r 'if .is_cli == true then "true" else "false" end' <<<"$classification")"
  mapfile -t langs < <(jq -r '(.languages // [])[]? | .lang // empty' <<<"$classification")

  if [[ -n $docs_override && ! -d ${docs_override}/tech ]]; then
    docs_path=""
  elif docs_path="$(cog::fn::refs_resolve_docs_path "$docs_override")"; then
    available=true
    mapfile -t refs < <(cog::fn::refs_compute "$docs_path" "$is_cli" "${langs[@]}")
  fi
  refs_json="$(__cog_review_refs_json_array "${refs[@]}")"

  jq -n \
    --argjson classification "$classification" \
    --argjson available "$available" \
    --arg path "$docs_path" \
    --argjson relevant_agents_md "$refs_json" \
    '{
      classification: $classification,
      docs_notes_repo: {
        available: $available,
        path: $path,
        relevant_agents_md: $relevant_agents_md
      }
    }'
}

__cog_review_refs_run() {
  local classification_file="" docs_override="" mode="" out="" json
  local -a positionals=()

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_refs_usage
        return 0
        ;;
      --classification)
        [[ $# -ge 2 && -n ${2:-} && -z $classification_file ]] || cog::fn::error_raise "MissingArgument" \
          "missing classification file" "option: --classification" "" "run 'cog review-refs --help'"
        classification_file="$2"
        shift 2
        ;;
      --docs-notes-repo)
        [[ $# -ge 2 && -n ${2:-} && -z $docs_override ]] || cog::fn::error_raise "MissingArgument" \
          "missing docs-n-notes repo path" "option: --docs-notes-repo" "" "run 'cog review-refs --help'"
        docs_override="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate review-refs output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-refs option" "option: $1" "" "run 'cog review-refs --help'"
        ;;
      *)
        positionals+=("$1")
        shift
        ;;
    esac
  done

  if [[ -z $classification_file && ${#positionals[@]} -gt 0 ]]; then
    classification_file="${positionals[0]}"
    positionals=("${positionals[@]:1}")
  fi
  if [[ -z $mode && ${#positionals[@]} -gt 0 ]]; then
    out="${positionals[0]}"
    mode=file
    positionals=("${positionals[@]:1}")
  fi

  ((${#positionals[@]} == 0)) || cog::fn::error_raise "TooManyArguments" \
    "too many review-refs arguments" "argument: ${positionals[0]}" "" "run 'cog review-refs --help'"
  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $classification_file && -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing review-refs argument" "usage: cog review-refs --classification <file> (<out.json>|--json)" "" \
    "run 'cog review-refs --help'"

  json="$(__cog_review_refs_build_json "$classification_file" "$docs_override")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_refs_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_review_refs_self_check" "$json"
  fi
}

cog::cmd::review_refs() {
  __cog_review_refs_run "$@"
}
