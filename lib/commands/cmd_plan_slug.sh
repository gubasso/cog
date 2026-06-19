# shellcheck shell=bash
: 'desc: Derive and validate an implementation plan slug.'

__cog_plan_slug_self_check='(.ok|type=="boolean") and (.input|type=="string") and ((.slug|type=="string") or (.slug == null)) and (.reserved|type=="boolean") and (.max_length == 60)'

__cog_plan_slug_usage() {
  cog::fn::ui_data "Usage: cog plan-slug --text <orientation> (<out.json>|--json)"
}

__cog_plan_slug_derive() {
  local input="$1" normalized word slug=""
  local -a words=()
  normalized="$(printf '%s' "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  IFS='-' read -r -a words <<<"$normalized"
  for word in "${words[@]}"; do
    [[ -n $word ]] || continue
    if [[ -z $slug ]]; then
      slug="$word"
    else
      slug="${slug}-${word}"
    fi
    [[ "$(tr -cd '-' <<<"$slug" | wc -c | tr -d ' ')" -ge 4 ]] && break
  done
  slug="${slug:0:60}"
  sed -E 's/-+$//' <<<"$slug"
}

__cog_plan_slug_build_json() {
  local input="$1" slug ok=true reserved=false reason=""
  slug="$(__cog_plan_slug_derive "$input")"
  case "${slug,,}" in
    "")
      ok=false
      reason="slug is empty"
      ;;
    readme | strategy | queue | queue-plans | queue-rounds)
      ok=false
      reserved=true
      reason="slug is reserved"
      ;;
  esac

  jq -n \
    --argjson ok "$ok" \
    --arg input "$input" \
    --arg slug "$slug" \
    --argjson reserved "$reserved" \
    --arg reason "$reason" \
    '{ok: $ok, input: $input, slug: (if $ok then $slug else null end),
      reserved: $reserved, max_length: 60, reason: (if $ok then null else $reason end)}'
}

cog::cmd::plan_slug() {
  local input="" have_text=false mode="" out="" json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_slug_usage
        return 0
        ;;
      --text)
        [[ $# -ge 2 && $have_text == false ]] || cog::fn::error_raise "MissingArgument" \
          "missing or duplicate plan-slug text" "option: --text" "" "run 'cog plan-slug --help'"
        input="$2"
        have_text=true
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate plan-slug output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown plan-slug option" "option: $1" "" "run 'cog plan-slug --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many plan-slug output paths" "argument: $1" "" "run 'cog plan-slug --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ $have_text == true && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan-slug argument" "usage: cog plan-slug --text <orientation> (<out.json>|--json)" "" \
    "run 'cog plan-slug --help'"
  [[ -n $mode ]] || mode=json

  json="$(__cog_plan_slug_build_json "$input")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plan_slug_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_plan_slug_self_check" "$json"
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
