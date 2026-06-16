# shellcheck shell=bash
: 'desc: Probe whether the project is a CLI from classification data.'

__cog_review_cli_signals_self_check='(.is_cli | type == "boolean") and (.cli_signals | type == "array") and (.languages | type == "array")'

__cog_review_cli_signals_usage() {
  cog::fn::ui_data "Usage: cog review-cli-signals --classification <file> (<out.json>|--json)"
}

__cog_review_cli_signals_read_classification() {
  local file="$1"
  [[ -r $file ]] || cog::fn::error_raise "InputUnreadable" \
    "classification file is not readable" "path: ${file}" "" "check the file path"
  jq -c . "$file" 2>/dev/null || cog::fn::error_raise "InvalidJsonInput" \
    "classification file is not valid JSON" "path: ${file}" "" "check the file contents"
}

__cog_review_cli_signals_build_json() {
  local classification="$1"
  jq -c '{
    git_root,
    is_cli,
    cli_signals,
    project_types,
    languages,
    frameworks,
    signal_count: (.cli_signals | length)
  }' <<<"$classification"
}

cog::cmd::review_cli_signals() {
  local classification_file="" mode="" out="" classification json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_cli_signals_usage
        return 0
        ;;
      --classification)
        [[ $# -ge 2 && -n ${2:-} && -z $classification_file ]] || cog::fn::error_raise "MissingArgument" \
          "missing classification file" "option: --classification" "" "run 'cog review-cli-signals --help'"
        classification_file="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate review-cli-signals output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-cli-signals option" "option: $1" "" "run 'cog review-cli-signals --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many review-cli-signals output paths" "argument: $1" "" "run 'cog review-cli-signals --help'"
        out="$1"
        mode=file
        shift
        ;;
    esac
  done

  # R8 adds classify-project; until then callers must pass the classification explicitly.
  [[ -n $classification_file ]] || cog::fn::error_raise "MissingClassification" \
    "missing classification file" "usage: cog review-cli-signals --classification <file> (<out.json>|--json)" \
    "implicit classification is not available until classify-project is ported" \
    "run classification first and pass --classification"
  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing review-cli-signals output mode" "usage: cog review-cli-signals --classification <file> (<out.json>|--json)" "" \
    "run 'cog review-cli-signals --help'"

  classification="$(__cog_review_cli_signals_read_classification "$classification_file")"
  json="$(__cog_review_cli_signals_build_json "$classification")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_cli_signals_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_review_cli_signals_self_check" "$json"
  fi
}
