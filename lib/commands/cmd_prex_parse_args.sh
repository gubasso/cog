# shellcheck shell=bash
: 'desc: Parse prex arguments into run state (compatibility alias for executor-prex-parse-args).'

# shellcheck source=/dev/null
source "${LIB_DIR}/commands/cmd_executor_prex_parse_args.sh"

cog::cmd::prex_parse_args() {
  cog::cmd::executor_prex_parse_args "$@"
}
