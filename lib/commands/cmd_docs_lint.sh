# shellcheck shell=bash
: 'desc: Validate documentation structure and lean Markdown rules.'

__cog_docs_lint_usage() {
  cog::fn::ui_data "Usage: cog docs-lint"
}

cog::cmd::docs_lint() {
  local result
  if (($# > 0)); then
    case "$1" in
      -h | --help)
        (($# == 1)) || cog::fn::error_raise "TooManyArguments" \
          "too many docs-lint arguments" "argument: ${2:-}" "" "run 'cog docs-lint --help'"
        __cog_docs_lint_usage
        return 0
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "unexpected docs-lint argument" "argument: $1" "" "run 'cog docs-lint --help'"
        ;;
    esac
  fi

  if ! cog::fn::docs_lint::run; then
    return "$EX_DATAERR"
  fi
  printf -v result 'OK\tfiles=%s\tfailures=0' "$COG_DOCS_LINT_FILES"
  cog::fn::ui_data "$result"
}
