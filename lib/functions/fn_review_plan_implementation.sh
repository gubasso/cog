# shellcheck shell=bash

__cog_review_plan_implementation_require_jq_yq() {
  local cmd
  for cmd in jq yq sha256sum; do
    __have "$cmd" || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
      "required command not found" "command: ${cmd}" "" "install ${cmd} and retry"
  done
}

__cog_review_plan_implementation_require_repo_root() {
  local repo_root="${1:-}"
  [[ -n $repo_root ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing repo root" "function: review implementation plans" "expected <repo_root>" ""
  [[ -d $repo_root ]] || cog::helpers::die "$EX_NOINPUT" "InputNotFound" \
    "repo root not found" "path: ${repo_root}" "" "check the repo root"
}

__cog_review_plan_implementation_require_queue_file() {
  local queue_path="${1:-}"
  [[ -n $queue_path ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing queue path" "function: review implementation plans" "expected <queue_path>" ""
  [[ -f $queue_path ]] || cog::helpers::die "$EX_NOINPUT" "InputNotFound" \
    "queue file not found" "path: ${queue_path}" "" "check the queue path"
}

cog::fn::review_plan_implementation_queue_schema() {
  __cog_review_plan_implementation_require_jq_yq
  local queue_path="${1:-}"
  local has_plans has_rounds
  __cog_review_plan_implementation_require_queue_file "$queue_path"

  yq e '.' "$queue_path" >/dev/null || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "queue file does not parse" "path: ${queue_path}" "" "fix the YAML syntax"

  has_plans="$(yq e 'has("plans") and (.plans | tag == "!!seq")' "$queue_path")"
  has_rounds="$(yq e 'has("rounds") and (.rounds | tag == "!!seq")' "$queue_path")"

  if [[ $has_plans == true && $has_rounds == true ]]; then
    cog::helpers::die "$EX_DATAERR" "InvalidInput" \
      "queue file has ambiguous schema" "path: ${queue_path}" \
      "both plans and rounds item arrays are present" "keep exactly one queue item-array schema"
  fi
  if [[ $has_plans != true && $has_rounds != true ]]; then
    cog::helpers::die "$EX_DATAERR" "InvalidInput" \
      "queue file has no supported schema" "path: ${queue_path}" \
      "expected plans: [] or rounds: []" "use a supported queue schema"
  fi

  if [[ $has_plans == true ]]; then
    printf '%s\n' plans
  else
    printf '%s\n' rounds
  fi
}

cog::fn::review_plan_implementation_assert_flat() {
  local repo_root="${1:-}" abs_repo plans_dir nested
  __cog_review_plan_implementation_require_repo_root "$repo_root"
  abs_repo="$(realpath "$repo_root")"
  plans_dir="${abs_repo}/.implementation-plans/plans"
  [[ -d $plans_dir ]] || return 0

  # Plan directories are always flat siblings directly under plans/ (plans/<slug>/).
  # An inner queue-rounds.yaml below the depth-2 sibling level signals a nested plan.
  nested="$(find "$plans_dir" -mindepth 3 -type f -name 'queue-rounds.yaml' | LC_ALL=C sort)"
  [[ -z $nested ]] || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "nested plan directory detected" "path: ${plans_dir}" "$nested" \
    "move each plan to a flat sibling plans/<slug>/ and wire ordering via depends_on"
}

__cog_review_plan_implementation_queue_json() {
  local queue_path="$1" schema="$2" abs_queue
  abs_queue="$(realpath "$queue_path")"
  cog::fn::queue_validate_file "$abs_queue" "$schema"
  yq e -o=json '.' "$abs_queue" | jq -c \
    --arg schema "$schema" \
    --arg path "$abs_queue" '
      {
        path: $path,
        schema: $schema,
        items: (
          .[$schema]
          | map({
              schema: $schema,
              queue_path: $path,
              item,
              status,
              depends_on,
              prompt,
              notes,
              mutable: (.status == "todo" or .status == "backlog")
            })
        )
      }
    '
}

cog::fn::review_plan_implementation_inventory_json() {
  __cog_review_plan_implementation_require_jq_yq
  local repo_root="${1:-}" main_queue="${2:-}"
  local abs_repo abs_main plans_dir path schema
  local -a queue_jsons=()

  __cog_review_plan_implementation_require_repo_root "$repo_root"
  __cog_review_plan_implementation_require_queue_file "$main_queue"
  abs_repo="$(realpath "$repo_root")"
  abs_main="$(realpath "$main_queue")"

  schema="$(cog::fn::review_plan_implementation_queue_schema "$abs_main")"
  [[ $schema == plans ]] || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "main queue must use plans schema" "path: ${abs_main}" "actual schema: ${schema}" \
    "pass the root queue-plans.yaml file"
  queue_jsons+=("$(__cog_review_plan_implementation_queue_json "$abs_main" plans)")

  cog::fn::review_plan_implementation_assert_flat "$abs_repo"

  plans_dir="${abs_repo}/.implementation-plans/plans"
  if [[ -d $plans_dir ]]; then
    while IFS= read -r path; do
      schema="$(cog::fn::review_plan_implementation_queue_schema "$path")"
      [[ $schema == rounds ]] || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
        "inner queue must use rounds schema" "path: ${path}" "actual schema: ${schema}" \
        "queue-rounds.yaml files must contain rounds"
      queue_jsons+=("$(__cog_review_plan_implementation_queue_json "$path" rounds)")
    done < <(find "$plans_dir" -mindepth 2 -maxdepth 2 -type f -name 'queue-rounds.yaml' | LC_ALL=C sort)
  fi

  printf '%s\n' "${queue_jsons[@]}" | jq -s '{queues: .}'
}

cog::fn::review_plan_implementation_repo_fingerprint() {
  local repo_root="${1:-}" abs_repo
  __cog_review_plan_implementation_require_repo_root "$repo_root"
  abs_repo="$(realpath "$repo_root")"

  (
    cd "$abs_repo" \
      && find . \
        \( -path './.git' -o -path './.implementation-plans' -o -path './.pytest_cache' \
        -o -path './.mypy_cache' -o -path './.ruff_cache' -o -path './.cache' \
        -o -path './.state' -o -path './state' -o -path './.run' -o -path './run' \
        -o -path './runs' -o -path './node_modules' -o -path '*/__pycache__' \) -prune \
        -o -type f ! -name '*.tmp.*' -print0
  ) | cog::fn::refactor_null_path_fingerprint "$abs_repo"
}

cog::fn::review_plan_implementation_plans_fingerprint() {
  local repo_root="${1:-}" abs_repo plans_dir
  __cog_review_plan_implementation_require_repo_root "$repo_root"
  abs_repo="$(realpath "$repo_root")"
  plans_dir="${abs_repo}/.implementation-plans"
  [[ -d $plans_dir ]] || cog::helpers::die "$EX_NOINPUT" "InputNotFound" \
    "implementation plans directory not found" "path: ${plans_dir}" "" \
    "initialize implementation plans first"

  (
    cd "$abs_repo" \
      && find .implementation-plans -type f \
        \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' \) \
        ! -name '*.tmp.*' -print0
  ) | cog::fn::refactor_null_path_fingerprint "$abs_repo"
}
