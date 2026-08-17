# shellcheck shell=bash
: 'desc: Apply an SPDX LICENSE to a project.'

__cog_license_apply_self_check='(.ok|type=="boolean") and (.mode|type=="string")'

__cog_license_apply_usage() {
  cog::fn::ui_data "Usage: cog license-apply (--list | --spdx <id> --holder <name> --year <year> [--filename <name>] [--project-root <dir>] [--template-root <dir>] [--conflict overwrite|skip|abort]) (<out.json>|--json)"
}

# True when the destination basename is one the project's license is
# conventionally carried in. A dual `MIT OR Apache-2.0` layout needs two applies
# under two names (LICENSE-MIT, LICENSE-APACHE), so the destination cannot be
# hardcoded; restricting it to the conventional set keeps every applied license
# discoverable by the same resolver `cog bootstrap-audit` reads, instead of
# landing a license file nothing downstream recognizes.
__cog_license_apply_valid_filename() {
  local name="$1" pattern
  [[ -n $name && $name != */* && $name != .* ]] || return 1
  while IFS= read -r pattern; do
    # shellcheck disable=SC2254 # $pattern is a glob by design (LICENSE-*).
    case "$name" in $pattern) return 0 ;; esac
  done < <(cog::fn::template::license_name_patterns)
  return 1
}

# Shipped SPDX identifiers (lowercased). A directory under the template root
# holds each id's LICENSE file.
__cog_license_apply_shipped() {
  printf '%s\n' apache-2.0 bsd-3-clause gpl-3.0 mit
}

# Placeholders each SPDX text requires. MIT and BSD-3-Clause carry copyright
# lines; Apache-2.0 and GPL-3.0 ship verbatim standard text.
__cog_license_apply_needs_fields() {
  case "$1" in
    mit | bsd-3-clause) return 0 ;;
    *) return 1 ;;
  esac
}

__cog_license_apply_is_shipped() {
  local spdx="$1" id
  while IFS= read -r id; do [[ $id == "$spdx" ]] && return 0; done < <(__cog_license_apply_shipped)
  return 1
}

__cog_license_apply_list_json() {
  local template_root="$1" ids=()
  local id
  while IFS= read -r id; do
    [[ -f "$template_root/$id/LICENSE" ]] && ids+=("$id")
  done < <(__cog_license_apply_shipped)
  jq -n --arg template_root "$template_root" \
    --argjson spdx_ids "$(cog::fn::template::json_string_array "${ids[@]}")" \
    '{ok: true, mode: "list", template_root: $template_root, spdx_ids: $spdx_ids, reason: null}'
}

__cog_license_apply_build_json() {
  local spdx="$1" holder="$2" year="$3" project_root="$4" template_root="$5" conflict="$6" filename="${7:-LICENSE}"
  local ok=true reason="" template_dir="$template_root/$spdx" src="$template_root/$spdx/LICENSE" dst="$project_root/$filename"
  local copied=() skipped=() conflicts=()
  if ! cog::fn::template::valid_policy "$conflict"; then
    ok=false
    reason="conflict policy must be overwrite, skip, or abort"
  elif ! __cog_license_apply_valid_filename "$filename"; then
    ok=false
    reason="filename must be a conventional license basename (LICENSE, LICENSE-<id>, COPYING, ...)"
  elif [[ -z $spdx ]]; then
    ok=false
    reason="spdx is required"
  elif ! __cog_license_apply_is_shipped "$spdx"; then
    ok=false
    reason="unknown spdx id (run 'cog license-apply --list')"
  elif [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  elif [[ ! -f $src || -L $src ]]; then
    ok=false
    reason="license template not found"
  elif __cog_license_apply_needs_fields "$spdx" && [[ -z $holder || -z $year ]]; then
    ok=false
    reason="spdx $spdx requires --holder and --year"
  fi
  if [[ $ok == true ]]; then
    cog::fn::template::assert_under_project "$project_root" "$dst" || {
      ok=false
      reason="destination escapes project root"
    }
  fi
  if [[ $ok == true ]]; then
    if [[ -e $dst && $conflict == abort ]]; then
      conflicts+=("$(cog::fn::template::record_json "$src" "$dst")")
      ok=false
      reason="destination conflict"
    elif [[ -e $dst && $conflict == skip ]]; then
      skipped+=("$(cog::fn::template::record_json "$src" "$dst")")
    else
      local content
      content="$(cat "$src")"
      # The replacements are quoted because bash's `patsub_replacement` (on by
      # default since 5.2) expands an unquoted `&` in the replacement to the
      # matched text: an ordinary holder like `Smith & Wesson` otherwise lands in
      # the deployed license as `Smith {{HOLDER}} Wesson` — wrong attribution
      # plus a leftover marker, reported as a success. Quoting is the remedy the
      # bash manual prescribes and is a no-op on older bash, where quote removal
      # applies and `&` was never special here.
      content="${content//\{\{YEAR\}\}/"$year"}"
      content="${content//\{\{HOLDER\}\}/"$holder"}"
      if mkdir -p "$(dirname "$dst")" && printf '%s\n' "$content" >"$dst"; then
        copied+=("$(cog::fn::template::record_json "$src" "$dst")")
      else
        ok=false
        reason="write failed"
      fi
    fi
  fi
  jq -n --argjson ok "$ok" --arg project_root "$project_root" --arg template_root "$template_root" \
    --arg spdx "$spdx" --arg holder "$holder" --arg year "$year" --arg template_dir "$template_dir" \
    --arg filename "$filename" \
    --argjson copied "$(cog::fn::template::json_object_array "${copied[@]}")" \
    --argjson skipped "$(cog::fn::template::json_object_array "${skipped[@]}")" \
    --argjson conflicts "$(cog::fn::template::json_object_array "${conflicts[@]}")" \
    --arg conflict "$conflict" --arg reason "$reason" \
    '{ok: $ok, mode: "apply", project_root: $project_root, template_root: $template_root,
      spdx: $spdx, filename: $filename, holder: (if $holder == "" then null else $holder end),
      year: (if $year == "" then null else $year end), template_dir: $template_dir,
      copied: $copied, skipped: $skipped, conflicts: $conflicts, conflict: $conflict,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::license_apply() {
  local spdx="" holder="" year="" filename="LICENSE" project_root template_root conflict=abort list=false mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root license)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_license_apply_usage
        return 0
        ;;
      --list)
        list=true
        shift
        ;;
      --spdx)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing spdx id" "option: --spdx" "" "run 'cog license-apply --help'"
        spdx="$2"
        shift 2
        ;;
      --holder)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing holder" "option: --holder" "" "run 'cog license-apply --help'"
        holder="$2"
        shift 2
        ;;
      --year)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing year" "option: --year" "" "run 'cog license-apply --help'"
        year="$2"
        shift 2
        ;;
      --filename)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing filename" "option: --filename" "" "run 'cog license-apply --help'"
        filename="$2"
        shift 2
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog license-apply --help'"
        project_root="$2"
        shift 2
        ;;
      --template-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template root" "option: --template-root" "" "run 'cog license-apply --help'"
        template_root="$2"
        shift 2
        ;;
      --conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing conflict policy" "option: --conflict" "" "run 'cog license-apply --help'"
        conflict="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate license-apply output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown license-apply option" "option: $1" "" "run 'cog license-apply --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many license-apply output paths" "argument: $1" "" "run 'cog license-apply --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing license-apply output mode" "usage: cog license-apply (--list | --spdx <id> ...) (<out.json>|--json)" "" "run 'cog license-apply --help'"
  [[ -n $mode ]] || mode=json
  if [[ $list == true ]]; then
    json="$(__cog_license_apply_list_json "$template_root")"
  else
    [[ -n $spdx ]] || cog::fn::error_raise "MissingArgument" "missing license-apply argument" "usage: cog license-apply --spdx <id> --holder <name> --year <year> ... (<out.json>|--json)" "" "run 'cog license-apply --help'"
    json="$(__cog_license_apply_build_json "$spdx" "$holder" "$year" "$project_root" "$template_root" "$conflict" "$filename")"
  fi
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_license_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_license_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
