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
