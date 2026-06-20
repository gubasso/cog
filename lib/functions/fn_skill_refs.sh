# shellcheck shell=bash

cog::fn::skill_refs_root() {
  local xdg_candidate repo_candidate normalized
  xdg_candidate="${XDG_DATA_HOME:-$HOME/.local/share}/cog/skill-refs"
  repo_candidate="${LIB_DIR}/../skill-refs"

  if [[ -d $xdg_candidate ]]; then
    normalized="$(cd -P "$xdg_candidate" && pwd)" || return 1
    printf '%s\n' "$normalized"
    return 0
  fi
  if [[ -d $repo_candidate ]]; then
    normalized="$(cd -P "$repo_candidate" && pwd)" || return 1
    printf '%s\n' "$normalized"
    return 0
  fi
  return 1
}

cog::fn::skill_refs_path() {
  local rel="${1:-}"
  local root resolved

  [[ -n $rel ]] || return 1
  [[ $rel != /* ]] || return 1
  [[ $rel != *..* ]] || return 1
  root="$(cog::fn::skill_refs_root)" || return 1
  resolved="${root}/${rel}"
  [[ -e $resolved ]] || return 1
  printf '%s\n' "$resolved"
}
