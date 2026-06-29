# shellcheck shell=bash

cog::fn::round_split::norm_key() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/`//g; s/[^a-z0-9]+/ /g; s/^ +//; s/ +$//'
}

cog::fn::round_split::coverage_json() {
  local parent="$1"
  shift
  local -a children=("$@")
  local parent_json child_jsons='[]' child json key

  parent_json="$(cog::fn::round_req::list_json "$parent")"
  jq -e '.ok == true' <<<"$parent_json" >/dev/null || {
    jq -n --arg parent "$parent" --argjson parent_report "$parent_json" \
      '{schema:"cog.round-split.coverage.v1", ok:false, parent:$parent, children:[], key:null, parent_report:$parent_report, lost:[], added:[], duplicated:[], coverage_ok:false}'
    return 0
  }
  key="$(jq -r 'if ([.criteria[].id] | all(. != null)) then "id" else "text" end' <<<"$parent_json")"
  for child in "${children[@]}"; do
    json="$(cog::fn::round_req::list_json "$child")"
    child_jsons="$(jq -c --argjson a "$child_jsons" --argjson b "$json" '$a+[$b]' <<<"{}")"
  done
  jq -n \
    --arg parent "$(cog::fn::round_req::abs_path "$parent")" \
    --argjson children "$(printf '%s\n' "${children[@]}" | jq -R . | jq -s .)" \
    --arg key "$key" \
    --argjson parent_report "$parent_json" \
    --argjson child_reports "$child_jsons" '
    def norm: ascii_downcase | gsub("`";"") | gsub("[^a-z0-9]+";" ") | gsub("^ +| +$";"");
    def reqkey($k): if $k == "id" then .id else .text|norm end;
    def uniqarr: unique;
    ($parent_report.criteria | map(reqkey($key))) as $parent_reqs
    | ($child_reports | map(.criteria[] | reqkey($key))) as $child_reqs
    | ($child_reqs | group_by(.) | map(select(length > 1) | .[0])) as $duplicated
    | ($parent_reqs - $child_reqs) as $lost
    | ($child_reqs - $parent_reqs) as $added
    | ($parent_report.ok and ([$child_reports[].ok] | all) and (($lost|length) == 0)) as $ok
    | {
        schema:"cog.round-split.coverage.v1", ok:$ok, parent:$parent, children:$children,
        key:$key, parent_reqs:$parent_reqs, lost:$lost, added:$added,
        duplicated:$duplicated, coverage_ok:$ok,
        parent_report:$parent_report, child_reports:$child_reports
      }'
}
