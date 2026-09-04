#!/usr/bin/env bash
: 'desc: Check or refresh vendored skill-package references against their owner.'
# shellcheck shell=bash

# A shipped skill package must carry its own references, or it cannot run where
# cog is absent. That means two copies of one authored owner, so the copies need
# a gate rather than a convention. This command owns both halves: `sync` copies
# the owner's files into the package and records a digest for each, and `check`
# recomputes those digests and fails on drift.
#
# The manifest is the package's own file, so a consumer of the installed package
# can verify it without cog.

# This command compares authored checkout paths, so it needs the checkout, not the
# installed application root. An installed `cog` sets LIB_DIR under $PREFIX/lib/cog,
# which holds bin, lib and VERSION but no skills/ or skill-refs/ tree, so trusting
# LIB_DIR would make an installed run report false drift. Walk up from the current
# directory instead, and accept a root only when it carries both trees.
__cog_skill_vendor_repo_root() {
  local dir="${PWD}"

  while [[ $dir != / ]]; do
    if [[ -d $dir/skills && -d $dir/skill-refs/skill-authoring ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname -- "$dir")"
  done

  if [[ -n ${LIB_DIR:-} && -d ${LIB_DIR}/../skills && -d ${LIB_DIR}/../skill-refs/skill-authoring ]]; then
    (cd "${LIB_DIR}/.." && pwd -P)
    return 0
  fi

  return 1
}

__cog_skill_vendor_usage() {
  cog::fn::ui_data "Usage: cog skill-vendor <check|sync> [--package <dir>] [--source <dir>] (<out.json>|--json)"
}

# Every vendored pairing in the repository. One line per pairing:
# "<package dir>|<source dir>". Add a line when a package starts vendoring.
__cog_skill_vendor_pairings() {
  printf '%s\n' "skills/skill-creator/references|skill-refs/skill-authoring/universal"
}

__cog_skill_vendor_manifest_path() {
  printf '%s/MANIFEST.yaml\n' "$1"
}

__cog_skill_vendor_digest() {
  sha256sum -- "$1" | cut -d' ' -f1
}

# Write the package copy plus the digest manifest. Files present in the package
# but absent from the source are removed, so a retired reference cannot survive
# as a stale copy.
__cog_skill_vendor_sync_one() {
  local pkg_dir="$1" src_dir="$2" manifest name digest

  [[ -d $src_dir ]] || cog::fn::error_raise "InputNotFound" \
    "vendor source directory not found" "path: ${src_dir}" "" "check the source path"

  mkdir -p -- "$pkg_dir"
  manifest="$(__cog_skill_vendor_manifest_path "$pkg_dir")"

  local -a existing=()
  while IFS= read -r name; do
    [[ -n $name ]] && existing+=("$name")
  done < <(find "$pkg_dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' -printf '%f\n' 2>/dev/null | sort)

  # The header stays tool-neutral. This manifest ships inside a package that must
  # run where cog is absent, so it records provenance and digests without naming
  # a command the package's own user cannot run.
  {
    printf '# Vendored copies. Each digest is the SHA-256 of the file beside it.\n'
    printf '# These files are copies. Edit them at the source below, not here.\n'
    printf 'source: %s\n' "$src_dir"
    printf 'files:\n'
  } >"$manifest"

  while IFS= read -r name; do
    [[ -n $name ]] || continue
    cp -- "$src_dir/$name" "$pkg_dir/$name"
    digest="$(__cog_skill_vendor_digest "$pkg_dir/$name")"
    printf '  %s: %s\n' "$name" "$digest" >>"$manifest"
  done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort)

  local stale
  for stale in "${existing[@]}"; do
    [[ -e "$src_dir/$stale" ]] || rm -f -- "$pkg_dir/$stale"
  done

  return 0
}

# What a sync would write and remove, without touching anything.
__cog_skill_vendor_plan_one() {
  local pkg_dir="$1" src_dir="$2" name

  [[ -d $src_dir ]] || {
    printf '%s: vendor source directory not found\n' "$src_dir"
    return 0
  }

  printf '%s/MANIFEST.yaml: would rewrite\n' "$pkg_dir"
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    if [[ ! -f "$pkg_dir/$name" ]]; then
      printf '%s/%s: would create\n' "$pkg_dir" "$name"
    elif ! cmp -s -- "$src_dir/$name" "$pkg_dir/$name"; then
      printf '%s/%s: would overwrite\n' "$pkg_dir" "$name"
    fi
  done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort)

  while IFS= read -r name; do
    [[ -n $name ]] || continue
    [[ -e "$src_dir/$name" ]] || printf '%s/%s: would remove\n' "$pkg_dir" "$name"
  done < <(find "$pkg_dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' -printf '%f\n' 2>/dev/null | sort)

  return 0
}

# Report every drift between a package copy and its source: a changed copy, a
# missing copy, an extra copy, or a manifest that no longer matches the bytes.
__cog_skill_vendor_check_one() {
  local pkg_dir="$1" src_dir="$2" manifest name digest recorded

  manifest="$(__cog_skill_vendor_manifest_path "$pkg_dir")"
  if [[ ! -f $manifest ]]; then
    printf '%s: missing vendor manifest; run cog skill-vendor sync\n' "$pkg_dir"
    return 0
  fi

  while IFS= read -r name; do
    [[ -n $name ]] || continue
    if [[ ! -f "$pkg_dir/$name" ]]; then
      printf '%s/%s: vendored copy missing\n' "$pkg_dir" "$name"
      continue
    fi
    if ! cmp -s -- "$src_dir/$name" "$pkg_dir/$name"; then
      printf '%s/%s: vendored copy differs from %s/%s\n' "$pkg_dir" "$name" "$src_dir" "$name"
      continue
    fi
    digest="$(__cog_skill_vendor_digest "$pkg_dir/$name")"
    recorded="$(awk -v k="  ${name}:" '$0 ~ "^" k {print $2; exit}' "$manifest")"
    [[ $recorded == "$digest" ]] || printf '%s/%s: manifest digest stale\n' "$pkg_dir" "$name"
  done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort)

  while IFS= read -r name; do
    [[ -n $name ]] || continue
    [[ -e "$src_dir/$name" ]] || printf '%s/%s: vendored copy has no source\n' "$pkg_dir" "$name"
  done < <(find "$pkg_dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort)

  return 0
}

cog::cmd::skill_vendor() {
  local mode="" pkg_override="" src_override="" out="" json=false
  local repo_root pairing pkg_dir src_dir
  local -a findings=()

  while (($#)); do
    case "$1" in
      check | sync)
        mode="$1"
        shift
        ;;
      --package)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing package directory" "option: --package" "" "run 'cog skill-vendor --help'"
        pkg_override="$2"
        shift 2
        ;;
      --source)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing source directory" "option: --source" "" "run 'cog skill-vendor --help'"
        src_override="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -h | --help)
        __cog_skill_vendor_usage
        return 0
        ;;
      *)
        out="$1"
        shift
        ;;
    esac
  done

  [[ -n $mode ]] || cog::fn::error_raise "MissingArgument" "missing mode" "expected: check or sync" "" "run 'cog skill-vendor --help'"

  repo_root="$(__cog_skill_vendor_repo_root)" || cog::fn::error_raise "InputNotFound" \
    "no cog checkout found" "searched upward from: ${PWD}" \
    "a checkout carries both skills/ and skill-refs/skill-authoring/" \
    "run this from a cog checkout; it compares authored files, not installed ones"
  cd -- "$repo_root" || cog::fn::error_raise "InputNotFound" "repo root is not reachable" "path: ${repo_root}" "" "check the path"

  local -a pairings=()
  if [[ -n $pkg_override || -n $src_override ]]; then
    [[ -n $pkg_override && -n $src_override ]] || cog::fn::error_raise "MissingArgument" \
      "--package and --source are used together" "" "" "pass both, or neither"
    pairings=("${pkg_override}|${src_override}")
  else
    while IFS= read -r pairing; do
      [[ -n $pairing ]] && pairings+=("$pairing")
    done < <(__cog_skill_vendor_pairings)
  fi

  local dry_run="${COG_UI_DRY_RUN:-false}"

  for pairing in "${pairings[@]}"; do
    pkg_dir="${pairing%%|*}"
    src_dir="${pairing#*|}"
    if [[ $mode == sync ]]; then
      if [[ $dry_run == true ]]; then
        # --dry-run promises no state change, so report the planned writes and
        # removals rather than performing them.
        while IFS= read -r line; do
          [[ -n $line ]] && findings+=("$line")
        done < <(__cog_skill_vendor_plan_one "$pkg_dir" "$src_dir")
      else
        __cog_skill_vendor_sync_one "$pkg_dir" "$src_dir"
      fi
    else
      while IFS= read -r line; do
        [[ -n $line ]] && findings+=("$line")
      done < <(__cog_skill_vendor_check_one "$pkg_dir" "$src_dir")
    fi
  done

  # A check reports drift as failure. A dry-run sync reports a plan, which is
  # informational, so it stays successful.
  local ok=true
  if [[ $mode == check ]]; then
    ((${#findings[@]} == 0)) || ok=false
  fi

  local payload
  payload="$(jq -n --arg schema "cog.skill-vendor.${mode}.v1" --argjson ok "$ok" \
    --argjson findings "$(cog::fn::skill::json_string_array "${findings[@]}")" \
    '{schema: $schema, ok: $ok, findings: $findings}')"

  if [[ $json == true || -n $out ]]; then
    cog::fn::json_emit '(.ok|type=="boolean") and (.findings|type=="array")' "$payload" "$out"
  else
    local finding
    for finding in "${findings[@]}"; do
      printf '%s\n' "$finding" >&2
    done
    [[ $ok == true ]] && cog::fn::ui_human "ok skill-vendor ${mode}"
  fi

  [[ $ok == true ]]
}
