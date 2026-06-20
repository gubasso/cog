# shellcheck shell=bash
: 'desc: Resolve a tsk issue for a prex run (compatibility alias for executor-prex-tsk-resolve).'

# shellcheck source=/dev/null
source "${LIB_DIR}/commands/cmd_executor_prex_tsk_resolve.sh"

cog::cmd::prex_tsk_resolve() {
  cog::cmd::executor_prex_tsk_resolve "$@"
}
