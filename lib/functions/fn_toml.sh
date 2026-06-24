# shellcheck shell=bash

cog::fn::toml::require() {
  __have taplo || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
    "required command not found" "command: taplo" "" "sudo zypper install taplo"
}

cog::fn::toml::json() {
  local toml_path="${1:-}"
  [[ -n $toml_path ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing TOML path" "function: cog::fn::toml::json" "" ""

  # taplo is advisory in doctor, but TOML parsing fails closed at the point of use.
  cog::fn::toml::require
  taplo get -f "$toml_path" -o json || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "TOML file does not parse" "path: ${toml_path}" "" "fix the TOML syntax"
}
