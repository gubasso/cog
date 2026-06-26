# shellcheck shell=bash
: 'desc: Template, build, and validate a rich-context handoff brief.'

if ! declare -F cog::fn::context_brief_build >/dev/null; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_context_brief.sh"
fi

__cog_context_brief_usage() {
  cog::fn::ui_data "Usage: cog context-brief template [--out <path>]"
  cog::fn::ui_data "Usage: cog context-brief build --request <file> --body <file> --out <path> [--format md|json]"
  cog::fn::ui_data "Usage: cog context-brief validate <path> [--format text|json]"
  cog::fn::ui_data "Usage: cog context-brief --help"
}

__cog_context_brief_template_cmd() {
  local out=""

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_context_brief_usage
        return 0
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} && -z $out ]] || cog::fn::error_raise "MissingArgument" \
          "missing template output path" "option: --out" "" "run 'cog context-brief --help'"
        out="$2"
        shift 2
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown context-brief template option" "option: $1" "" "run 'cog context-brief --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many context-brief template arguments" "argument: $1" "" "run 'cog context-brief --help'"
        ;;
    esac
  done

  if [[ -n $out ]]; then
    cog::fn::context_brief_scaffold >"$out" || cog::fn::error_raise "JsonWriteFailed" \
      "could not write context-brief template" "path: ${out}" "" "check the output path and retry"
    cog::fn::ui_data "RESOLVED ${out}"
  else
    cog::fn::context_brief_scaffold
  fi
}

__cog_context_brief_build_cmd() {
  local request="" body="" out="" format="md"
  [[ ${COG_UI_JSON:-false} == true ]] && format="json"

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_context_brief_usage
        return 0
        ;;
      --request)
        [[ $# -ge 2 && -n ${2:-} && -z $request ]] || cog::fn::error_raise "MissingArgument" \
          "missing request file" "option: --request" "" "run 'cog context-brief --help'"
        request="$2"
        shift 2
        ;;
      --body)
        [[ $# -ge 2 && -n ${2:-} && -z $body ]] || cog::fn::error_raise "MissingArgument" \
          "missing body file" "option: --body" "" "run 'cog context-brief --help'"
        body="$2"
        shift 2
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} && -z $out ]] || cog::fn::error_raise "MissingArgument" \
          "missing output path" "option: --out" "" "run 'cog context-brief --help'"
        out="$2"
        shift 2
        ;;
      --format)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing format" "option: --format" "" "run 'cog context-brief --help'"
        format="$2"
        shift 2
        ;;
      --json)
        # Deprecated alias for --format json; kept for one release.
        cog::fn::log_warn "cog context-brief build: --json is deprecated; use --format json"
        format="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown context-brief build option" "option: $1" "" "run 'cog context-brief --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many context-brief build arguments" "argument: $1" "" "run 'cog context-brief --help'"
        ;;
    esac
  done

  [[ $format == md || $format == json ]] || cog::fn::error_raise "InvalidInput" \
    "unknown format" "format: ${format}" "" "use --format md|json"

  [[ -n $request ]] || cog::fn::error_raise "MissingArgument" \
    "missing request file" \
    "usage: cog context-brief build --request <file> --body <file> --out <path>" "" \
    "run 'cog context-brief --help'"
  [[ -n $body ]] || cog::fn::error_raise "MissingArgument" \
    "missing body file" "option: --body" "" "run 'cog context-brief --help'"
  [[ -n $out ]] || cog::fn::error_raise "MissingArgument" \
    "missing output path" "option: --out" "" "run 'cog context-brief --help'"

  cog::fn::rundir_require_file "$request" "request file"
  cog::fn::rundir_require_file "$body" "body file"

  cog::fn::context_brief_build "$request" "$body" "$out"

  if [[ $format == json ]]; then
    local result
    result="$(jq -cn --arg brief_file "$out" '{ok: true, brief_file: $brief_file}')"
    cog::fn::json_emit '(.ok == true) and (.brief_file | type == "string" and (. | length) > 0)' "$result"
  else
    cog::fn::ui_data "RESOLVED ${out}"
  fi
}

__cog_context_brief_validate_cmd() {
  local brief="" format="text" result

  [[ ${COG_UI_JSON:-false} == true ]] && format="json"

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_context_brief_usage
        return 0
        ;;
      --format)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing format" "option: --format" "" "run 'cog context-brief --help'"
        format="$2"
        shift 2
        ;;
      --json)
        # Deprecated alias for --format json; kept for one release.
        cog::fn::log_warn "cog context-brief validate: --json is deprecated; use --format json"
        format="json"
        shift
        ;;
      --input)
        [[ $# -ge 2 && -n ${2:-} && -z $brief ]] || cog::fn::error_raise "MissingArgument" \
          "missing context brief file" "option: --input" "" "run 'cog context-brief --help'"
        brief="$2"
        shift 2
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown context-brief validate option" "option: $1" "" "run 'cog context-brief --help'"
        ;;
      *)
        [[ -z $brief ]] || cog::fn::error_raise "TooManyArguments" \
          "too many context-brief validate arguments" "argument: $1" "" "run 'cog context-brief --help'"
        brief="$1"
        shift
        ;;
    esac
  done

  [[ -n $brief ]] || cog::fn::error_raise "MissingArgument" \
    "missing context brief file" "usage: cog context-brief validate <path> [--format text|json]" "" \
    "run 'cog context-brief --help'"

  [[ $format == text || $format == json ]] || cog::fn::error_raise "InvalidInput" \
    "unknown format" "format: ${format}" "" "use --format text|json"

  cog::fn::context_brief_assert "$brief"

  result="$(jq -cn --arg brief_file "$brief" '{ok: true, brief_file: $brief_file}')"
  if [[ $format == json ]]; then
    cog::fn::json_emit '(.ok == true) and (.brief_file | type == "string")' "$result"
  else
    cog::fn::ui_data "$result"
  fi
}

cog::cmd::context_brief() {
  local verb="${1:-}"

  case "$verb" in
    -h | --help | "")
      __cog_context_brief_usage
      return 0
      ;;
    template)
      shift
      __cog_context_brief_template_cmd "$@"
      ;;
    scaffold)
      # Deprecated alias for `template`; kept for one release.
      cog::fn::log_warn "cog context-brief scaffold is deprecated; use cog context-brief template"
      shift
      __cog_context_brief_template_cmd "$@"
      ;;
    build)
      shift
      __cog_context_brief_build_cmd "$@"
      ;;
    validate)
      shift
      __cog_context_brief_validate_cmd "$@"
      ;;
    -*)
      cog::fn::error_raise "InvalidInput" \
        "unknown context-brief option" "option: $verb" "" "run 'cog context-brief --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown context-brief mode" "mode: $verb" "" "expected template, build, or validate"
      ;;
  esac
}
