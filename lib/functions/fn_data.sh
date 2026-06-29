# shellcheck shell=bash

cog::fn::data_root() {
  local xdg_candidate repo_candidate normalized
  xdg_candidate="${XDG_DATA_HOME:-$HOME/.local/share}/cog/data"
  repo_candidate="${LIB_DIR}/../data"

  if [[ -d $xdg_candidate ]]; then
    normalized="$(cd -P "$xdg_candidate" && pwd)" || return 1
    printf '%s\n' "$normalized"
    return 0
  fi
  if [[ -d $repo_candidate ]]; then
    normalized="$(cd -P "$repo_candidate" && pwd)" || return 1
    printf '%s\n' "$normalized"
    return 0
  fi
  return 1
}

cog::fn::data::path() {
  local rel="${1:-}"
  local root resolved

  [[ -n $rel ]] || return 1
  [[ $rel != /* ]] || return 1
  [[ $rel != *..* ]] || return 1
  root="$(cog::fn::data_root)" || return 1
  resolved="${root}/${rel}"
  [[ -e $resolved ]] || return 1
  printf '%s\n' "$resolved"
}

cog::fn::data::require() {
  local cmd
  for cmd in jq yq; do
    __have "$cmd" || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
      "required command not found" "command: ${cmd}" "" "install ${cmd} and retry"
  done
}

cog::fn::data::load_dir() {
  local path="${1:-}"
  local -a files=()

  [[ -n $path ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing data path" "function: cog::fn::data::load_dir" "" ""
  [[ -e $path ]] || cog::helpers::die "$EX_NOINPUT" "InputNotFound" \
    "data path not found" "path: ${path}" "" "check the data directory"

  cog::fn::data::require

  if [[ -d $path ]]; then
    while IFS= read -r file; do
      files+=("$file")
    done < <(find "$path" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) -print | sort)
    ((${#files[@]} > 0)) || cog::helpers::die "$EX_NOINPUT" "InputNotFound" \
      "data directory has no YAML files" "path: ${path}" "" "add *.yaml files"
  else
    files=("$path")
  fi

  (
    set -o pipefail
    yq e -o=json '.' "${files[@]}" 2>/dev/null | jq -s '
      def filename($i): $files[$i];
      . as $docs
      | reduce range(0; $docs | length) as $i (
        {out: {}, seen: {}, errors: []};
        . as $state
        | ($docs[$i] // {}) as $x
        | if ($x | type) != "object" then
            $state | .errors += ["non-object YAML document in " + filename($i)]
          else
            ($x | keys_unsorted) as $keys
            | ($keys | map(select($state.seen[.] != null))) as $dupes
            | if ($dupes | length) > 0 then
                $state | .errors += ["duplicate top-level key(s) in " + filename($i) + ": " + ($dupes | join(", "))]
              else
                $state
                | .out = (.out * $x)
                | .seen = (.seen + ($keys | map({key: ., value: filename($i)}) | from_entries))
              end
          end
      )
      | if (.errors | length) > 0 then error(.errors | join("; ")) else .out end
    ' --argjson files "$(printf '%s\n' "${files[@]}" | jq -R -s 'split("\n")[:-1]')"
  ) \
    || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
      "data YAML does not parse or merge" "path: ${path}" "" "fix the data YAML"
}
