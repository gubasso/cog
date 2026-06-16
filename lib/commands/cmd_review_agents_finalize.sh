# shellcheck shell=bash
: 'desc: Finalize review reference resolution from classification data.'

if ! declare -F cog::cmd::review_refs >/dev/null; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_review_refs.sh"
fi

cog::cmd::review_agents_finalize() {
  cog::cmd::review_refs "$@"
}
