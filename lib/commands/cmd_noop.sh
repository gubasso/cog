# shellcheck shell=bash
: 'desc: Exercise command dispatch without side effects.'

cog::cmd::noop() {
  cog::fn::ui_data "noop"
  return 0
}
