# shellcheck shell=bash
: 'desc: Exercise command dispatch without side effects.'

cog::cmd::noop() {
  printf '%s\n' "noop"
  return 0
}
