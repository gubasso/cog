# shellcheck shell=bash
# Deterministic detection and scaffolding mechanics for the Rust/cargo project
# skeleton. Detection reports whether a project is already scaffolded, its crate
# kind and edition, which optional config files are present, and how cargo is
# reachable (bare, through direnv, through nix develop, or absent). Scaffolding
# wraps the official `cargo` CLI (`cargo init`), guarded and idempotent: it runs
# only when the project has no Cargo.toml and never touches .gitignore (it passes
# `--vcs none`, leaving version-control files to the repo domain).

# Resolve how cargo is reachable from a project root. Prefers a cargo already on
# PATH (a loaded devshell), then direnv (an .envrc that would enter the flake),
# then nix develop (a flake.nix on a host with nix), else absent.
cog::fn::cargo::runner() {
  local project_root="$1"
  if command -v cargo >/dev/null 2>&1; then
    printf '%s\n' bare
  elif [[ -f $project_root/.envrc ]] && command -v direnv >/dev/null 2>&1; then
    printf '%s\n' direnv
  elif [[ -f $project_root/flake.nix ]] && command -v nix >/dev/null 2>&1; then
    printf '%s\n' nix-develop
  else
    printf '%s\n' absent
  fi
}

# Run a cargo subcommand through the resolved runner, with cwd at the project
# root. Combined output is captured by the caller; returns cargo's exit status,
# or 127 when the runner is absent.
cog::fn::cargo::exec() {
  local project_root="$1" runner="$2"
  shift 2
  case "$runner" in
    bare) (cd "$project_root" && cargo "$@") ;;
    direnv) (cd "$project_root" && direnv exec "$project_root" cargo "$@") ;;
    nix-develop) (cd "$project_root" && nix develop "$project_root" --command cargo "$@") ;;
    *) return 127 ;;
  esac
}

# Read the crate kind from a Cargo.toml: workspace (a [workspace] table),
# lib (a [lib] table or src/lib.rs), bin (a [[bin]] table or src/main.rs),
# else bin as the cargo-new default. Emits none when no manifest exists.
cog::fn::cargo::_kind() {
  local project_root="$1"
  local manifest="$project_root/Cargo.toml"
  [[ -f $manifest ]] || {
    printf '%s\n' none
    return 0
  }
  if grep -Eq '^\[workspace\]' "$manifest"; then
    printf '%s\n' workspace
  elif grep -Eq '^\[lib\]' "$manifest" || [[ -f $project_root/src/lib.rs ]]; then
    printf '%s\n' lib
  else
    printf '%s\n' bin
  fi
}

# Extract the package edition from a Cargo.toml, or empty when absent.
cog::fn::cargo::_edition() {
  local manifest="$1" line
  [[ -f $manifest ]] || return 0
  line="$(grep -E '^edition[[:space:]]*=' "$manifest" | head -n1 || true)"
  [[ -n $line ]] || return 0
  printf '%s\n' "$line" | sed -E 's/^edition[[:space:]]*=[[:space:]]*"?([^"]*)"?.*/\1/'
}

# Build the cargo-detect JSON for a project root.
cog::fn::cargo::detect_json() {
  local project_root="$1"
  local ok=true reason="" manifest="$project_root/Cargo.toml"
  local scaffolded=false kind edition runner
  local rustfmt=false clippy=false deny=false
  if [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
    jq -n --argjson ok "$ok" --arg project_root "$project_root" --arg reason "$reason" \
      '{ok: $ok, project_root: $project_root, scaffolded: false, kind: "none", edition: null,
        configs: {rustfmt_toml: false, clippy_toml: false, deny_toml: false},
        cargo_runner: "absent", reason: $reason}'
    return 0
  fi
  [[ -f $manifest ]] && scaffolded=true
  kind="$(cog::fn::cargo::_kind "$project_root")"
  edition="$(cog::fn::cargo::_edition "$manifest")"
  runner="$(cog::fn::cargo::runner "$project_root")"
  { [[ -f $project_root/rustfmt.toml ]] || [[ -f $project_root/.rustfmt.toml ]]; } && rustfmt=true
  { [[ -f $project_root/clippy.toml ]] || [[ -f $project_root/.clippy.toml ]]; } && clippy=true
  [[ -f $project_root/deny.toml ]] && deny=true
  jq -n \
    --argjson ok "$ok" --arg project_root "$project_root" \
    --argjson scaffolded "$scaffolded" --arg kind "$kind" --arg edition "$edition" \
    --argjson rustfmt "$rustfmt" --argjson clippy "$clippy" --argjson deny "$deny" \
    --arg cargo_runner "$runner" \
    '{ok: $ok, project_root: $project_root, scaffolded: $scaffolded, kind: $kind,
      edition: (if $edition == "" then null else $edition end),
      configs: {rustfmt_toml: $rustfmt, clippy_toml: $clippy, deny_toml: $deny},
      cargo_runner: $cargo_runner, reason: null}'
}

# Append a scaffold action record to the RAN or SKIPPED array by nameref.
cog::fn::cargo::_record() {
  local action="$1" detail="$2"
  jq -cn --arg action "$action" --arg detail "$detail" '{action: $action, detail: $detail}'
}

# Build the cargo-scaffold-apply JSON. Runs `cargo init --vcs none --<kind>`
# only when Cargo.toml is absent; optionally `cargo deny init` when requested and
# deny.toml is absent. The cargo-init result drives ok; deny init is best-effort
# and reported per-action.
cog::fn::cargo::scaffold_json() {
  local project_root="$1" kind="$2" name="$3" deny_init="$4"
  local ok=true reason="" runner out status
  local ran=() skipped=()
  if [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  elif [[ $kind != bin && $kind != lib ]]; then
    ok=false
    reason="kind must be bin or lib"
  elif [[ -n $name && ! $name =~ ^[A-Za-z0-9_-]+$ ]]; then
    ok=false
    reason="name must match ^[A-Za-z0-9_-]+$"
  fi
  runner="$(cog::fn::cargo::runner "$project_root")"
  if [[ $ok == true ]]; then
    if [[ -f $project_root/Cargo.toml ]]; then
      skipped+=("$(cog::fn::cargo::_record cargo-init "Cargo.toml already present")")
    elif [[ $runner == absent ]]; then
      ok=false
      reason="cargo is not reachable (no cargo on PATH, no .envrc+direnv, no flake.nix+nix)"
    else
      local -a args=(init --vcs none "--$kind")
      [[ -n $name ]] && args+=(--name "$name")
      status=0
      out="$(cog::fn::cargo::exec "$project_root" "$runner" "${args[@]}" 2>&1)" || status=$?
      if [[ $status -eq 0 ]]; then
        ran+=("$(cog::fn::cargo::_record cargo-init "cargo ${args[*]}")")
      else
        ok=false
        reason="cargo init failed"
        ran+=("$(cog::fn::cargo::_record cargo-init "$(printf '%s' "$out" | tail -n1)")")
      fi
    fi
  fi
  if [[ $ok == true && $deny_init == true ]]; then
    if [[ -f $project_root/deny.toml ]]; then
      skipped+=("$(cog::fn::cargo::_record cargo-deny-init "deny.toml already present")")
    elif [[ $runner == absent ]]; then
      skipped+=("$(cog::fn::cargo::_record cargo-deny-init "cargo not reachable")")
    else
      status=0
      out="$(cog::fn::cargo::exec "$project_root" "$runner" deny init 2>&1)" || status=$?
      if [[ $status -eq 0 ]]; then
        ran+=("$(cog::fn::cargo::_record cargo-deny-init "cargo deny init")")
      else
        skipped+=("$(cog::fn::cargo::_record cargo-deny-init "cargo deny init failed: $(printf '%s' "$out" | tail -n1)")")
      fi
    fi
  fi
  local ran_json='[]' skipped_json='[]'
  [[ ${#ran[@]} -gt 0 ]] && ran_json="$(printf '%s\n' "${ran[@]}" | jq -s .)"
  [[ ${#skipped[@]} -gt 0 ]] && skipped_json="$(printf '%s\n' "${skipped[@]}" | jq -s .)"
  jq -n \
    --argjson ok "$ok" --arg project_root "$project_root" --arg cargo_runner "$runner" \
    --argjson ran "$ran_json" --argjson skipped "$skipped_json" --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, cargo_runner: $cargo_runner,
      ran: $ran, skipped: $skipped, reason: (if $ok then null else $reason end)}'
}

# Convert the positional args into a JSON string array. Self-contained so the
# publish helpers work when fn_cargo.sh is sourced on its own.
cog::fn::cargo::_strarray() {
  if [[ $# -eq 0 ]]; then jq -cn '[]'; else printf '%s\n' "$@" | jq -R . | jq -s .; fi
}

# Grep a set of paths for a fixed pattern, quietly, tolerating missing files.
cog::fn::cargo::_matches() {
  local pattern="$1"
  shift
  local p
  for p in "$@"; do
    [[ -e $p ]] || continue
    if grep -rqsF -- "$pattern" "$p" 2>/dev/null; then return 0; fi
  done
  return 1
}

# True when the manifest has a top-level key assignment (leading whitespace
# tolerated), e.g. `description = "..."`. Distinguishes `license` from
# `license-file`, which is a separate key.
cog::fn::cargo::_manifest_has_key() {
  local manifest="$1" key="$2"
  [[ -f $manifest ]] || return 1
  grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$manifest"
}

# Count quoted entries in the first array-valued assignment of a key on a single
# line, e.g. `keywords = ["cli", "tooling"]` -> 2. Absent or empty -> 0.
cog::fn::cargo::_manifest_array_count() {
  local manifest="$1" key="$2" line count
  [[ -f $manifest ]] || {
    printf '0\n'
    return 0
  }
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$manifest" | head -n1 || true)"
  count="$(printf '%s\n' "$line" | grep -oE '"[^"]*"' | grep -c . || true)"
  printf '%s\n' "${count:-0}"
}

# Build the cargo-publish-detect JSON for a project root. Pure file inspection:
# no cargo exec, no auth, no credential access. Reports the release-readiness
# landscape the publish-judgment layer reasons over.
cog::fn::cargo::publish_detect_json() {
  local project_root="$1"
  local ok=true reason="" manifest="$project_root/Cargo.toml"
  local crate_kind runner
  local is_publishable=true publishable_reason=""
  local ci_provider=none
  local release_name=none release_present=false
  local semver_present=false ships_hint=false
  local -a release_signals=() semver_signals=() binary_signals=()
  local wf_dir="$project_root/.github/workflows"
  local -a scan_paths=("$manifest" "$wf_dir" "$project_root/justfile" "$project_root/Justfile" "$project_root/Makefile")

  if [[ ! -d $project_root ]]; then
    jq -n --arg project_root "$project_root" --arg reason "project root is not a directory" \
      '{ok: false, project_root: $project_root, crate_kind: "none", is_publishable: false,
        publishable_reason: null, ci_provider: "none",
        release_tool: {name: "none", present: false, signals: []},
        semver_tool: {present: false, signals: []},
        ships_binaries: {hint: false, signals: []},
        metadata: {has_description: false, has_license: false, has_repository: false,
          has_readme: false, has_exclude: false, has_include: false,
          keywords_count: 0, categories_count: 0},
        cargo_runner: "absent", reason: $reason}'
    return 0
  fi

  crate_kind="$(cog::fn::cargo::_kind "$project_root")"
  runner="$(cog::fn::cargo::runner "$project_root")"

  # Publishability: no manifest, or an active `publish = false` line, blocks it.
  if [[ ! -f $manifest ]]; then
    is_publishable=false
    publishable_reason="no Cargo.toml"
  elif grep -Eq '^[[:space:]]*publish[[:space:]]*=[[:space:]]*false' "$manifest"; then
    is_publishable=false
    publishable_reason="Cargo.toml sets publish = false"
  elif [[ $crate_kind == workspace ]]; then
    publishable_reason="workspace root; member crates need package-level review"
  fi

  # CI provider (github wins when both are present).
  if [[ -d $wf_dir ]] && find "$wf_dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print -quit 2>/dev/null | grep -q .; then
    ci_provider=github
  elif [[ -f $project_root/.gitlab-ci.yml ]]; then
    ci_provider=gitlab
  fi

  # Release tool signals.
  local rp=false cr=false
  if [[ -f $project_root/release-plz.toml ]]; then
    rp=true
    release_signals+=("release-plz.toml")
  fi
  if cog::fn::cargo::_matches "release-plz" "$wf_dir"; then
    rp=true
    release_signals+=(".github/workflows mentions release-plz")
  fi
  if [[ -f $project_root/release.toml || -f $project_root/.release.toml ]]; then
    cr=true
    release_signals+=("release.toml")
  fi
  if [[ -f $manifest ]] && grep -Eq '^\[(workspace|package)\.metadata\.release\]' "$manifest"; then
    cr=true
    release_signals+=("Cargo.toml [metadata.release]")
  fi
  if cog::fn::cargo::_matches "cargo release" "$wf_dir" "$project_root/justfile" "$project_root/Justfile" "$project_root/Makefile"; then
    cr=true
    release_signals+=("workflow/taskrunner mentions cargo release")
  fi
  if [[ $rp == true && $cr == true ]]; then
    release_name=multiple
    release_present=true
  elif [[ $rp == true ]]; then
    release_name=release-plz
    release_present=true
  elif [[ $cr == true ]]; then
    release_name=cargo-release
    release_present=true
  fi

  # SemVer tooling (release-plz runs cargo-semver-checks natively for lib crates).
  if cog::fn::cargo::_matches "semver-checks" "${scan_paths[@]}"; then
    semver_present=true
    semver_signals+=("cargo-semver-checks referenced")
  fi
  if [[ $rp == true ]]; then
    semver_present=true
    semver_signals+=("release-plz runs semver-check for lib crates")
  fi

  # Binary distribution hint.
  if [[ $crate_kind == bin ]]; then
    ships_hint=true
    binary_signals+=("crate kind is bin")
  fi
  if [[ -f $project_root/src/main.rs ]]; then
    ships_hint=true
    binary_signals+=("src/main.rs")
  fi
  if [[ -d $project_root/src/bin ]]; then
    ships_hint=true
    binary_signals+=("src/bin/")
  fi
  if [[ -f $manifest ]] && grep -Eq '^\[\[bin\]\]' "$manifest"; then
    ships_hint=true
    binary_signals+=("Cargo.toml [[bin]]")
  fi
  if [[ -f $project_root/dist-workspace.toml || -f $project_root/dist.toml ]] || { [[ -f $manifest ]] && grep -Eq '^\[(workspace|package)\.metadata\.dist\]' "$manifest"; }; then
    ships_hint=true
    binary_signals+=("cargo-dist config")
  fi

  # crates.io metadata presence (pure manifest inspection). description + a
  # license are the publish-rejecting required fields; the rest are recommended
  # or hygiene signals the judgment layer surfaces to the metadata owner.
  local md_desc=false md_license=false md_repo=false md_readme=false md_exclude=false md_include=false
  local md_keywords=0 md_categories=0
  if [[ -f $manifest ]]; then
    cog::fn::cargo::_manifest_has_key "$manifest" description && md_desc=true
    { cog::fn::cargo::_manifest_has_key "$manifest" license || cog::fn::cargo::_manifest_has_key "$manifest" license-file; } && md_license=true
    cog::fn::cargo::_manifest_has_key "$manifest" repository && md_repo=true
    cog::fn::cargo::_manifest_has_key "$manifest" readme && md_readme=true
    cog::fn::cargo::_manifest_has_key "$manifest" exclude && md_exclude=true
    cog::fn::cargo::_manifest_has_key "$manifest" include && md_include=true
    md_keywords="$(cog::fn::cargo::_manifest_array_count "$manifest" keywords)"
    md_categories="$(cog::fn::cargo::_manifest_array_count "$manifest" categories)"
  fi

  jq -n \
    --argjson ok "$ok" --arg project_root "$project_root" --arg crate_kind "$crate_kind" \
    --argjson is_publishable "$is_publishable" --arg publishable_reason "$publishable_reason" \
    --arg ci_provider "$ci_provider" \
    --arg release_name "$release_name" --argjson release_present "$release_present" \
    --argjson release_signals "$(cog::fn::cargo::_strarray "${release_signals[@]}")" \
    --argjson semver_present "$semver_present" \
    --argjson semver_signals "$(cog::fn::cargo::_strarray "${semver_signals[@]}")" \
    --argjson ships_hint "$ships_hint" \
    --argjson binary_signals "$(cog::fn::cargo::_strarray "${binary_signals[@]}")" \
    --argjson md_desc "$md_desc" --argjson md_license "$md_license" --argjson md_repo "$md_repo" \
    --argjson md_readme "$md_readme" --argjson md_exclude "$md_exclude" --argjson md_include "$md_include" \
    --argjson md_keywords "$md_keywords" --argjson md_categories "$md_categories" \
    --arg cargo_runner "$runner" \
    '{ok: $ok, project_root: $project_root, crate_kind: $crate_kind,
      is_publishable: $is_publishable,
      publishable_reason: (if $publishable_reason == "" then null else $publishable_reason end),
      ci_provider: $ci_provider,
      release_tool: {name: $release_name, present: $release_present, signals: $release_signals},
      semver_tool: {present: $semver_present, signals: $semver_signals},
      ships_binaries: {hint: $ships_hint, signals: $binary_signals},
      metadata: {has_description: $md_desc, has_license: $md_license, has_repository: $md_repo,
        has_readme: $md_readme, has_exclude: $md_exclude, has_include: $md_include,
        keywords_count: $md_keywords, categories_count: $md_categories},
      cargo_runner: $cargo_runner, reason: null}'
}

# Build the cargo-publish-check JSON: go/no-go readiness via `cargo publish
# --dry-run` and `cargo package --list`. No auth is required or inspected. When
# cargo is unreachable, report it rather than running anything.
cog::fn::cargo::publish_check_json() {
  local project_root="$1"
  local runner
  if [[ ! -d $project_root ]]; then
    jq -n --arg project_root "$project_root" --arg reason "project root is not a directory" \
      '{ok: false, project_root: $project_root, cargo_runner: "absent",
        dry_run: null, package_list: null, reason: $reason}'
    return 0
  fi
  runner="$(cog::fn::cargo::runner "$project_root")"
  if [[ $runner == absent ]]; then
    jq -n --arg project_root "$project_root" \
      --arg reason "cargo is not reachable (no cargo on PATH, no .envrc+direnv, no flake.nix+nix)" \
      '{ok: false, project_root: $project_root, cargo_runner: "absent",
        dry_run: null, package_list: null, reason: $reason}'
    return 0
  fi

  local dry_out dry_status=0 list_out list_status=0 dry_tail list_tail list_files
  dry_out="$(cog::fn::cargo::exec "$project_root" "$runner" publish --dry-run 2>&1)" || dry_status=$?
  dry_tail="$(printf '%s' "$dry_out" | tail -n1)"
  list_out="$(cog::fn::cargo::exec "$project_root" "$runner" package --list 2>&1)" || list_status=$?
  list_tail="$(printf '%s' "$list_out" | tail -n1)"
  if [[ $list_status -eq 0 ]]; then
    list_files="$(printf '%s\n' "$list_out" | grep -c .)"
  else
    list_files=0
  fi

  local ok=true
  [[ $dry_status -eq 0 && $list_status -eq 0 ]] || ok=false

  jq -n \
    --argjson ok "$ok" --arg project_root "$project_root" --arg cargo_runner "$runner" \
    --argjson dry_status "$dry_status" --arg dry_tail "$dry_tail" \
    --argjson list_status "$list_status" --arg list_tail "$list_tail" --argjson list_files "$list_files" \
    '{ok: $ok, project_root: $project_root, cargo_runner: $cargo_runner,
      dry_run: {ok: ($dry_status == 0), status: $dry_status, command: "cargo publish --dry-run", tail: $dry_tail},
      package_list: {ok: ($list_status == 0), status: $list_status, command: "cargo package --list", files: $list_files, tail: $list_tail},
      reason: (if $ok then null else "readiness check failed" end)}'
}
