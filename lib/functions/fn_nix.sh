# shellcheck shell=bash
# Deterministic detection mechanics for the nix devShell template domain.
# Unlike the shared template matcher, nix detection never hard-fails on an
# unrecognized project: a single recognized language signal maps to one of
# python|rust|node|zig, and everything else (none, ambiguous, or unrecognized)
# falls back to the `generic` devShell. The emitted JSON mirrors the shared
# cog::fn::template::detect_json shape with config_basename = flake.nix.

# Map the classification's language signals to the set of nix template types.
# Populates NIX_MATCHES[] (unique nix types) and NIX_SIGNALS[] in parallel.
cog::fn::nix::_map_matches() {
  local classification="$1"
  NIX_MATCHES=()
  NIX_SIGNALS=()
  if cog::fn::template::language_present "$classification" rust; then
    NIX_MATCHES+=(rust)
    NIX_SIGNALS+=("rust language signal")
  fi
  if cog::fn::template::language_present "$classification" python; then
    NIX_MATCHES+=(python)
    NIX_SIGNALS+=("python language signal")
  fi
  if cog::fn::template::language_present "$classification" javascript; then
    NIX_MATCHES+=(node)
    NIX_SIGNALS+=("javascript language signal")
  fi
  if cog::fn::template::language_present "$classification" zig; then
    NIX_MATCHES+=(zig)
    NIX_SIGNALS+=("zig language signal")
  fi
}

# Build the nix-devshell detect JSON. Never hard-fails on classification: a
# missing/ambiguous/unrecognized project resolves to the `generic` devShell.
# Hard input errors (bad --type, missing project/template root) still set ok:false.
# Args: project_root template_root requested_type
cog::fn::nix::detect_json() {
  local project_root="$1" template_root="$2" requested_type="$3"
  local config_basename="flake.nix"
  local ok=true reason="" detected_type="" confidence=none classification='{}'
  local template_dir="" template_config="" template_exists=false signals_json
  if ! declare -F __cog_classify_project_build_json >/dev/null; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/commands/cmd_classify_project.sh"
  fi
  NIX_SIGNALS=()
  NIX_MATCHES=()
  if [[ -n $requested_type && ! $requested_type =~ ^[a-z0-9-]+$ ]]; then
    ok=false
    reason="type must match ^[a-z0-9-]+$"
  elif [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  elif [[ ! -d $template_root ]]; then
    ok=false
    reason="template root is not a directory"
  fi
  if [[ $ok == true ]]; then
    classification="$(cd "$project_root" && __cog_classify_project_build_json)"
    if [[ -n $requested_type ]]; then
      detected_type="$requested_type"
      confidence=requested
      NIX_SIGNALS=("requested type")
    else
      cog::fn::nix::_map_matches "$classification"
      if [[ ${#NIX_MATCHES[@]} -eq 1 ]]; then
        detected_type="${NIX_MATCHES[0]}"
        confidence=high
      else
        detected_type="generic"
        confidence=fallback
        if [[ ${#NIX_MATCHES[@]} -gt 1 ]]; then
          NIX_SIGNALS=("ambiguous language signals: ${NIX_MATCHES[*]}")
        else
          NIX_SIGNALS=("no recognized language signal")
        fi
      fi
    fi
    template_dir="$template_root/$detected_type"
    template_config="$template_dir/$config_basename"
    if [[ -f $template_config ]]; then
      template_exists=true
    else
      ok=false
      reason="template config not found"
    fi
  fi
  signals_json="$(cog::fn::template::json_string_array "${NIX_SIGNALS[@]}")"
  jq -n \
    --argjson ok "$ok" --arg project_root "$project_root" --arg template_root "$template_root" \
    --arg requested_type "$requested_type" --arg detected_type "$detected_type" --arg confidence "$confidence" \
    --argjson classification "$classification" --argjson signals "$signals_json" \
    --arg template_dir "$template_dir" --arg template_config "$template_config" --argjson template_exists "$template_exists" \
    --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root,
      requested_type: (if $requested_type == "" then null else $requested_type end),
      detected_type: (if $detected_type == "" then null else $detected_type end),
      confidence: $confidence, classification: $classification, signals: $signals, conflicts: [],
      template_dir: $template_dir, template_config: $template_config, template_exists: $template_exists,
      reason: (if $ok then null else $reason end)}'
}
