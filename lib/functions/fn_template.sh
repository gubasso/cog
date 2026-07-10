# shellcheck shell=bash
# Shared deterministic mechanics for cog template domains (pre-commit,
# editorconfig). Detection maps a project classification to one of the shared
# template types; apply primitives copy template files safely under conflict
# policy. Domain commands parameterize these with their own template root and
# config basename.

# Resolve a template domain root under the unified skill-refs resource tree.
cog::fn::template::root() {
  local domain="$1" root
  root="$(cog::fn::skill_refs_root)" || return 1
  printf '%s/templates/%s\n' "$root" "$domain"
}

cog::fn::template::json_string_array() {
  if [[ $# -eq 0 ]]; then jq -cn '[]'; else printf '%s\n' "$@" | jq -R . | jq -s .; fi
}

cog::fn::template::json_object_array() {
  if [[ $# -eq 0 ]]; then jq -cn '[]'; else printf '%s\n' "$@" | jq -s .; fi
}

cog::fn::template::record_json() {
  jq -cn --arg src "$1" --arg dst "$2" '{src: $src, dst: $dst}'
}

cog::fn::template::valid_policy() {
  case "$1" in overwrite | skip | abort) return 0 ;; *) return 1 ;; esac
}

cog::fn::template::assert_under_project() {
  local project_root="$1" dst="$2" root_abs dst_abs
  root_abs="$(realpath -m -- "$project_root")"
  dst_abs="$(realpath -m -- "$dst")"
  [[ $dst_abs == "$root_abs" || $dst_abs == "$root_abs/"* ]]
}

# --- Detection (operates on PROJECT_ROOT; populates MATCHES[]/SIGNALS[]) ---

cog::fn::template::_find_files() {
  find "$PROJECT_ROOT" -path "$PROJECT_ROOT/.git" -prune -o -type f "$@"
}

cog::fn::template::has_file() {
  [[ -f $PROJECT_ROOT/$1 ]]
}

cog::fn::template::count_named_files() {
  local name="$1"
  cog::fn::template::_find_files -name "$name" -print | wc -l | tr -d ' '
}

cog::fn::template::language_present() {
  local classification="$1" lang="$2"
  jq -e --arg lang "$lang" '.languages[]? | select(.lang == $lang)' <<<"$classification" >/dev/null
}

cog::fn::template::add_match() {
  MATCHES+=("$1")
  SIGNALS+=("$2")
}

cog::fn::template::detect_matches() {
  local classification="$1"
  MATCHES=()
  SIGNALS=()
  if cog::fn::template::language_present "$classification" svelte; then
    cog::fn::template::add_match sveltekit "package.json plus *.svelte"
  fi
  if cog::fn::template::language_present "$classification" rust; then
    cog::fn::template::add_match rust "Cargo.toml"
  fi
  if cog::fn::template::language_present "$classification" python; then
    cog::fn::template::add_match python "python language signal"
  elif cog::fn::template::has_file requirements.txt; then
    cog::fn::template::add_match python "requirements.txt"
  fi
  if cog::fn::template::language_present "$classification" javascript && ! cog::fn::template::language_present "$classification" svelte; then
    cog::fn::template::add_match node "package.json"
  fi
  if cog::fn::template::language_present "$classification" c; then
    cog::fn::template::add_match c "c language signal"
  elif [[ $(cog::fn::template::count_named_files '*.h') -gt 0 ]] || cog::fn::template::has_file CMakeLists.txt; then
    cog::fn::template::add_match c "*.h or CMakeLists.txt"
  fi
  if cog::fn::template::language_present "$classification" zig; then
    cog::fn::template::add_match zig "zig language signal"
  elif [[ $(cog::fn::template::count_named_files '*.zig') -gt 0 ]]; then
    cog::fn::template::add_match zig "*.zig"
  fi
  if cog::fn::template::language_present "$classification" bash; then
    cog::fn::template::add_match bash "bash language signal"
  elif [[ $(cog::fn::template::count_named_files '*.bash') -gt 0 || $(cog::fn::template::count_named_files '*.bats') -gt 0 ]]; then
    cog::fn::template::add_match bash "*.bash or *.bats"
  fi
  # Nix and markdown are fallbacks: they resolve only when no code-language
  # template matched. Every project carries a lone flake.nix for its devShell, so
  # nix is never a competing top-level match (that would collide with the real
  # language) — it resolves only when Nix sources dominate (a flake-defining repo).
  # Nix wins over markdown so a Nix repo with docs still resolves to nix.
  if [[ ${#MATCHES[@]} -eq 0 ]]; then
    if cog::fn::template::language_present "$classification" nix; then
      cog::fn::template::add_match nix "nix sources dominate"
    elif cog::fn::template::language_present "$classification" markdown; then
      cog::fn::template::add_match markdown "markdown content dominant"
    fi
  fi
}

# Build the detect JSON shared by precommit-detect and editorconfig-detect.
# Args: project_root template_root requested_type config_basename
cog::fn::template::detect_json() {
  local project_root="$1" template_root="$2" requested_type="$3" config_basename="$4"
  local ok=true reason="" detected_type="" confidence=none classification='{}'
  local template_dir="" template_config="" template_exists=false conflicts_json signals_json
  if ! declare -F __cog_classify_project_build_json >/dev/null; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/commands/cmd_classify_project.sh"
  fi
  PROJECT_ROOT="$project_root"
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
      SIGNALS=("requested type")
      MATCHES=("$requested_type")
    else
      cog::fn::template::detect_matches "$classification"
      if [[ ${#MATCHES[@]} -eq 1 ]]; then
        detected_type="${MATCHES[0]}"
        confidence=high
      elif [[ ${#MATCHES[@]} -gt 1 ]]; then
        ok=false
        reason="multiple template types detected"
      else
        ok=false
        reason="could not detect template type"
      fi
    fi
    if [[ -n $detected_type ]]; then
      template_dir="$template_root/$detected_type"
      template_config="$template_dir/$config_basename"
      if [[ -f $template_config ]]; then template_exists=true; else
        ok=false
        reason="${reason:-template config not found}"
      fi
    fi
  else
    MATCHES=()
    SIGNALS=()
  fi
  conflicts_json='[]'
  if [[ $ok == false && ${#MATCHES[@]} -gt 1 && -z $requested_type ]]; then
    conflicts_json="$(cog::fn::template::json_string_array "${MATCHES[@]}")"
  fi
  signals_json="$(cog::fn::template::json_string_array "${SIGNALS[@]}")"
  jq -n \
    --argjson ok "$ok" --arg project_root "$project_root" --arg template_root "$template_root" \
    --arg requested_type "$requested_type" --arg detected_type "$detected_type" --arg confidence "$confidence" \
    --argjson classification "$classification" --argjson signals "$signals_json" --argjson conflicts "$conflicts_json" \
    --arg template_dir "$template_dir" --arg template_config "$template_config" --argjson template_exists "$template_exists" \
    --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root,
      requested_type: (if $requested_type == "" then null else $requested_type end),
      detected_type: (if $detected_type == "" then null else $detected_type end),
      confidence: $confidence, classification: $classification, signals: $signals, conflicts: $conflicts,
      template_dir: $template_dir, template_config: $template_config, template_exists: $template_exists,
      reason: (if $ok then null else $reason end)}'
}
