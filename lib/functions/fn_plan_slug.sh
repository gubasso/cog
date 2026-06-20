# shellcheck shell=bash

cog::fn::plan_slug::derive() {
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

cog::fn::plan_slug::build_json() {
  local input="$1" slug ok=true reserved=false reason=""
  slug="$(cog::fn::plan_slug::derive "$input")"
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
