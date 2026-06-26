# shellcheck shell=bash
: 'desc: Scaffold, build, and validate a rich-context handoff brief.'

if ! declare -F cog::fn::context_brief_build >/dev/null; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_context_brief.sh"
fi

__cog_context_brief_usage() {
  cog::fn::ui_data "Usage: cog context-brief scaffold [--out <path>]"
  cog::fn::ui_data "Usage: cog context-brief build --request <file> --body <file> --out <path> [--json]"
  cog::fn::ui_data "Usage: cog context-brief validate <path> [--json]"
  cog::fn::ui_data "Usage: cog context-brief gate render --skill <name>"
  cog::fn::ui_data "Usage: cog context-brief --help"
}

__cog_context_brief_scaffold_cmd() {
  local out=""

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_context_brief_usage
        return 0
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} && -z $out ]] || cog::fn::error_raise "MissingArgument" \
          "missing scaffold output path" "option: --out" "" "run 'cog context-brief --help'"
        out="$2"
        shift 2
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown context-brief scaffold option" "option: $1" "" "run 'cog context-brief --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many context-brief scaffold arguments" "argument: $1" "" "run 'cog context-brief --help'"
        ;;
    esac
  done

  if [[ -n $out ]]; then
    cog::fn::context_brief_scaffold >"$out" || cog::fn::error_raise "JsonWriteFailed" \
      "could not write context-brief scaffold" "path: ${out}" "" "check the output path and retry"
    cog::fn::ui_data "RESOLVED ${out}"
  else
    cog::fn::context_brief_scaffold
  fi
}

__cog_context_brief_build_cmd() {
  local request="" body="" out="" json="${COG_UI_JSON:-false}"

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
      --json)
        json=true
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

  if [[ $json == true ]]; then
    local result
    result="$(jq -cn --arg brief_file "$out" '{ok: true, brief_file: $brief_file}')"
    cog::fn::json_emit '(.ok == true) and (.brief_file | type == "string" and (. | length) > 0)' "$result"
  else
    cog::fn::ui_data "RESOLVED ${out}"
  fi
}

__cog_context_brief_validate_cmd() {
  local brief="" json="${COG_UI_JSON:-false}" result

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_context_brief_usage
        return 0
        ;;
      --json)
        json=true
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
    "missing context brief file" "usage: cog context-brief validate <path> [--json]" "" \
    "run 'cog context-brief --help'"

  cog::fn::context_brief_assert "$brief"

  result="$(jq -cn --arg brief_file "$brief" '{ok: true, brief_file: $brief_file}')"
  if [[ $json == true ]]; then
    cog::fn::json_emit '(.ok == true) and (.brief_file | type == "string")' "$result"
  else
    cog::fn::ui_data "$result"
  fi
}

__cog_context_brief_gate_render_cmd() {
  local name=""

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_context_brief_usage
        return 0
        ;;
      --skill)
        [[ $# -ge 2 && -n ${2:-} && -z $name ]] || cog::fn::error_raise "MissingArgument" \
          "missing context-brief gate skill name" "option: --skill" "" "run 'cog context-brief --help'"
        name="$2"
        shift 2
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown context-brief gate render option" "option: $1" "" "run 'cog context-brief --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many context-brief gate render arguments" "argument: $1" "" "run 'cog context-brief --help'"
        ;;
    esac
  done

  [[ -n $name ]] || cog::fn::error_raise "MissingArgument" \
    "missing context-brief gate skill name" "option: --skill" "" "run 'cog context-brief --help'"
  cog::fn::skill::name_is_valid "$name" || cog::fn::error_raise "InvalidInput" \
    "invalid skill name" "name: ${name}" "" "use ^[a-z0-9-]{1,64}$ and avoid reserved names anthropic and claude"

  cog::fn::skill::context_brief_gate_render "$name"
}

__cog_context_brief_gate_cmd() {
  local sub="${1:-}"

  case "$sub" in
    -h | --help | "")
      __cog_context_brief_usage
      return 0
      ;;
    render)
      shift
      __cog_context_brief_gate_render_cmd "$@"
      ;;
    -*)
      cog::fn::error_raise "InvalidInput" \
        "unknown context-brief gate option" "option: $sub" "" "run 'cog context-brief --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown context-brief gate mode" "mode: $sub" "" "expected render"
      ;;
  esac
}

cog::cmd::context_brief() {
  local verb="${1:-}"

  case "$verb" in
    -h | --help | "")
      __cog_context_brief_usage
      return 0
      ;;
    scaffold)
      shift
      __cog_context_brief_scaffold_cmd "$@"
      ;;
    build)
      shift
      __cog_context_brief_build_cmd "$@"
      ;;
    validate)
      shift
      __cog_context_brief_validate_cmd "$@"
      ;;
    gate)
      shift
      __cog_context_brief_gate_cmd "$@"
      ;;
    -*)
      cog::fn::error_raise "InvalidInput" \
        "unknown context-brief option" "option: $verb" "" "run 'cog context-brief --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown context-brief mode" "mode: $verb" "" "expected scaffold, build, or validate"
      ;;
  esac
}
