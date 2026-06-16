# shellcheck shell=bash
: 'desc: Print resolved configuration values and their sources.'

cog::cmd::print_config() {
  # ctx, config, config_source, and config_line are populated/consumed by
  # cog::fn::config_load via nameref, so shellcheck cannot see their use and
  # reports false SC2034 on both the declaration and the ctx initializer.
  local key
  # shellcheck disable=SC2034
  local -A config config_source config_line
  # shellcheck disable=SC2034
  local -A ctx=(
    [cli_set_json]=false
    [cli_set_dry_run]=false
    [cli_set_log_level]=false
  )

  cog::fn::config_load ctx config config_source config_line

  for key in dry_run json log_level; do
    printf '%s=%s source=%s\n' "$key" "${config[$key]}" "${config_source[$key]}"
  done
}
