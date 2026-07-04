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

# Report the resolved skill-refs root together with its origin and writability so
# a caller can surface whether a template write lands in the installed, uncommitted
# XDG tree or the tracked repo checkout. Recomputes the same candidates as
# skill_refs_root (XDG before repo). Emits
# {ok, root, origin, candidate_xdg, candidate_repo, writable, vcs_note}: origin is
# `xdg` (selected install tree), `repo` (selected fallback), or `none` (ok:false).
cog::fn::skill_refs_origin_json() {
  local xdg_candidate repo_candidate root="" origin="none" writable=false vcs_note=""
  local ok=false candidate_xdg candidate_repo
  xdg_candidate="${XDG_DATA_HOME:-$HOME/.local/share}/cog/skill-refs"
  repo_candidate="${LIB_DIR}/../skill-refs"
  candidate_xdg="$xdg_candidate"
  candidate_repo="$repo_candidate"
  [[ -d $xdg_candidate ]] && candidate_xdg="$(cd -P "$xdg_candidate" && pwd)"
  [[ -d $repo_candidate ]] && candidate_repo="$(cd -P "$repo_candidate" && pwd)"

  if [[ -d $xdg_candidate ]]; then
    root="$candidate_xdg"
    origin="xdg"
  elif [[ -d $repo_candidate ]]; then
    root="$candidate_repo"
    origin="repo"
  fi

  if [[ -n $root ]]; then
    ok=true
    [[ -w $root ]] && writable=true
    case "$origin" in
      xdg) vcs_note="installed skill-refs: template writes are local, uncommitted changes" ;;
      repo) vcs_note="repo skill-refs: template writes are tracked in the cog source repo" ;;
    esac
  fi

  jq -cn \
    --argjson ok "$ok" \
    --arg root "$root" \
    --arg origin "$origin" \
    --arg candidate_xdg "$candidate_xdg" \
    --arg candidate_repo "$candidate_repo" \
    --argjson writable "$writable" \
    --arg vcs_note "$vcs_note" \
    '{ok: $ok, root: (if $root == "" then null else $root end), origin: $origin,
      candidate_xdg: $candidate_xdg, candidate_repo: $candidate_repo,
      writable: $writable, vcs_note: (if $vcs_note == "" then null else $vcs_note end)}'
}
