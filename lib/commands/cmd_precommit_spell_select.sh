# shellcheck shell=bash
: 'desc: Select the markdown spell checker for a set of KB content languages.'

# Deterministic language -> spell-checker mapping for the markdown/KB pre-commit
# template. English-only (or unset) resolves to `typos`; any non-English content
# language resolves to `cspell` (real multi-language dictionaries). The judgment
# of which languages a KB holds stays with the caller; this command only maps a
# declared set to the variant that `cog precommit-apply-template --spell` accepts.

__cog_precommit_spell_select_self_check='(.ok|type=="boolean") and (.spell|type=="string") and (.languages|type=="array") and (.non_english|type=="boolean")'

__cog_precommit_spell_select_usage() {
  cog::fn::ui_data "Usage: cog precommit-spell-select [--languages <csv>] (<out.json>|--json)"
}

__cog_precommit_spell_select_build_json() {
  local raw="$1"
  local ok=true reason="" spell=typos non_english=false
  local langs=() tok
  IFS=',' read -r -a langs <<<"$raw"
  local cleaned=()
  for tok in "${langs[@]}"; do
    tok="${tok#"${tok%%[![:space:]]*}"}"
    tok="${tok%"${tok##*[![:space:]]}"}"
    [[ -z $tok ]] && continue
    if [[ ! $tok =~ ^[a-z]{2}(_[A-Z]{2})?$ ]]; then
      ok=false
      reason="invalid language token: $tok (expected e.g. en or pt_BR)"
      break
    fi
    cleaned+=("$tok")
    [[ $tok == en ]] || non_english=true
  done
  [[ $non_english == true ]] && spell=cspell
  jq -n --argjson ok "$ok" --arg spell "$spell" --argjson non_english "$non_english" --arg reason "$reason" \
    --argjson languages "$(printf '%s\n' "${cleaned[@]}" | jq -R . | jq -s 'map(select(length > 0))')" \
    '{ok: $ok, languages: $languages, spell: (if $ok then $spell else "typos" end),
      non_english: (if $ok then $non_english else false end),
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::precommit_spell_select() {
  local languages="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_precommit_spell_select_usage
        return 0
        ;;
      --languages)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing languages value" "option: --languages" "" "run 'cog precommit-spell-select --help'"
        languages="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate precommit-spell-select output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown precommit-spell-select option" "option: $1" "" "run 'cog precommit-spell-select --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many precommit-spell-select output paths" "argument: $1" "" "run 'cog precommit-spell-select --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing precommit-spell-select output mode" "usage: cog precommit-spell-select [--languages <csv>] (<out.json>|--json)" "" "run 'cog precommit-spell-select --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_precommit_spell_select_build_json "$languages")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_precommit_spell_select_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_precommit_spell_select_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
