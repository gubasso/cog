# shellcheck shell=bash

__cog_review_queue_rounds_require_jq_yq() {
  local cmd
  for cmd in jq yq sha256sum; do
    __have "$cmd" || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
      "required command not found" "command: ${cmd}" "" "install ${cmd} and retry"
  done
}

__cog_review_queue_rounds_require_repo_root() {
  local repo_root="${1:-}"
  [[ -n $repo_root ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing repo root" "function: review queue rounds" "expected <repo_root>" ""
  [[ -d $repo_root ]] || cog::helpers::die "$EX_NOINPUT" "InputNotFound" \
    "repo root not found" "path: ${repo_root}" "" "check the repo root"
}

__cog_review_queue_rounds_require_queue_file() {
  local queue_path="${1:-}"
  [[ -n $queue_path ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing queue path" "function: review queue rounds" "expected <queue_path>" ""
  [[ -f $queue_path ]] || cog::helpers::die "$EX_NOINPUT" "InputNotFound" \
    "queue file not found" "path: ${queue_path}" "" "check the queue path"
}

cog::fn::review_queue_rounds_queue_schema() {
  __cog_review_queue_rounds_require_jq_yq
  local queue_path="${1:-}"
  local has_plans has_rounds
  __cog_review_queue_rounds_require_queue_file "$queue_path"

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

# Assert flat plan siblings on a plan_root (local or global store), delegating to
# the shared plan-vault flatness rule (tolerates a rounds/ subdir; rejects a
# nested plans/<slug>/<child>/queue-rounds.yaml).
cog::fn::review_queue_rounds_assert_flat() {
  local plan_root="${1:-}"
  [[ -n $plan_root ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing plan root" "function: review queue rounds" "expected <plan_root>" ""
  cog::fn::plan_assert_flat_root "$plan_root"
}

__cog_review_queue_rounds_queue_json() {
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

# Inventory the main plans queue plus every inner rounds queue under a plan_root.
# plan_root defaults to dirname(main_queue) for a canonical vault, so existing
# callers stay zero-config while the boundary scan works across local and global
# stores.
cog::fn::review_queue_rounds_inventory_json() {
  __cog_review_queue_rounds_require_jq_yq
  local repo_root="${1:-}" main_queue="${2:-}" plan_root="${3:-}"
  local abs_repo abs_main plans_dir path schema
  local -a queue_jsons=()

  __cog_review_queue_rounds_require_repo_root "$repo_root"
  __cog_review_queue_rounds_require_queue_file "$main_queue"
  abs_repo="$(realpath "$repo_root")"
  abs_main="$(realpath "$main_queue")"
  [[ -n $plan_root ]] || plan_root="$(dirname -- "$abs_main")"
  plan_root="$(realpath -m "$plan_root")"

  schema="$(cog::fn::review_queue_rounds_queue_schema "$abs_main")"
  [[ $schema == plans ]] || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "main queue must use plans schema" "path: ${abs_main}" "actual schema: ${schema}" \
    "pass the root queue-plans.yaml file"
  queue_jsons+=("$(__cog_review_queue_rounds_queue_json "$abs_main" plans)")

  cog::fn::review_queue_rounds_assert_flat "$plan_root"

  plans_dir="${plan_root%/}/plans"
  if [[ -d $plans_dir ]]; then
    while IFS= read -r path; do
      schema="$(cog::fn::review_queue_rounds_queue_schema "$path")"
      [[ $schema == rounds ]] || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
        "inner queue must use rounds schema" "path: ${path}" "actual schema: ${schema}" \
        "queue-rounds.yaml files must contain rounds"
      queue_jsons+=("$(__cog_review_queue_rounds_queue_json "$path" rounds)")
    done < <(find "$plans_dir" -mindepth 2 -maxdepth 2 -type f -name 'queue-rounds.yaml' | LC_ALL=C sort)
  fi

  printf '%s\n' "${queue_jsons[@]}" | jq -s '{queues: .}'
}

# Cross-round idempotency scan (ADR-0075). A round declares the artifacts it
# deploys (artifacts:) and/or the artifacts it expects already present
# (idempotency_check:). This scans every EARLIER round in the same rounds queue
# for a matching declared artifact (by type+path); a match means the target
# round's action is probably a no-op an earlier round already performed.
cog::fn::review_queue_rounds_idempotency_json() {
  __cog_review_queue_rounds_require_jq_yq
  local queue_path="${1:-}" round_id="${2:-}" abs_queue schema
  __cog_review_queue_rounds_require_queue_file "$queue_path"
  [[ -n $round_id ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing round id" "function: review queue rounds idempotency" "expected <round_id>" ""

  abs_queue="$(realpath "$queue_path")"
  schema="$(cog::fn::review_queue_rounds_queue_schema "$abs_queue")"
  [[ $schema == rounds ]] || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "idempotency scan requires a rounds queue" "path: ${abs_queue}" "actual schema: ${schema}" \
    "pass a queue-rounds.yaml file"
  cog::fn::queue_validate_file "$abs_queue" rounds

  ROUND="$round_id" yq e -e '.rounds[]? | select(.item == strenv(ROUND))' "$abs_queue" >/dev/null 2>&1 \
    || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
      "round not found in queue" "round: ${round_id}" "path: ${abs_queue}" \
      "pass a round item present in the queue"

  yq e -o=json '.' "$abs_queue" | jq -c \
    --arg schema "cog.review-queue-rounds.idempotency.v1" \
    --arg path "$abs_queue" \
    --arg round "$round_id" '
      (.rounds // []) as $rounds
      | ($rounds | map(.item) | index($round)) as $idx
      | ($rounds[0:$idx]) as $earlier
      | ([ $earlier[] as $r | ($r.artifacts // [])[] | {type: .type, path: .path, by: $r.item} ]) as $deployed
      | (((($rounds[$idx].artifacts // []) + ($rounds[$idx].idempotency_check // [])))
          | unique_by([.type, .path])) as $checks
      | ([ $checks[] as $c
          | ($deployed | map(select(.type == $c.type and .path == $c.path))) as $m
          | select(($m | length) > 0)
          | {type: $c.type, path: $c.path, first_deployed_by: $m[0].by} ]) as $already
      | {
          schema: $schema, ok: true, queue_path: $path, round_id: $round,
          already_deployed: $already, clean: (($already | length) == 0)
        }'
}

# Fingerprint the repo source tree, pruning the local plan vault so in-repo queue
# edits under .cog/plans do not perturb the source fingerprint. Global vaults live
# outside the repo and need no prune.
cog::fn::review_queue_rounds_repo_fingerprint() {
  local repo_root="${1:-}" plan_root="${2:-}" abs_repo abs_plan_root
  local -a extra_prune=(-o -path './.cog')
  __cog_review_queue_rounds_require_repo_root "$repo_root"
  abs_repo="$(realpath "$repo_root")"
  if [[ -n $plan_root ]]; then
    abs_plan_root="$(realpath -m "$plan_root")"
    if [[ $abs_plan_root == "$abs_repo"/* ]]; then
      extra_prune+=(-o -path "./${abs_plan_root#"$abs_repo"/}")
    fi
  fi

  (
    cd "$abs_repo" \
      && find . \
        \( -path './.git' -o -path './.implementation-plans' -o -path './.pytest_cache' \
        -o -path './.mypy_cache' -o -path './.ruff_cache' -o -path './.cache' \
        -o -path './.state' -o -path './state' -o -path './.run' -o -path './run' \
        -o -path './runs' -o -path './node_modules' -o -path '*/__pycache__' \
        "${extra_prune[@]}" \) -prune \
        -o -type f ! -name '*.tmp.*' -print0
  ) | cog::fn::refactor_null_path_fingerprint "$abs_repo"
}

# Fingerprint the plan-vault tree, based at the plan_root so relative paths are
# stable for both stores. A brand-new vault (absent plan_root) yields a stable
# empty fingerprint rather than dying.
cog::fn::review_queue_rounds_plans_fingerprint() {
  local plan_root="${1:-}" abs_plan_root
  [[ -n $plan_root ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing plan root" "function: review queue rounds" "expected <plan_root>" ""
  if [[ ! -d $plan_root ]]; then
    printf '' | sha256sum | cut -d' ' -f1
    return 0
  fi
  abs_plan_root="$(realpath "$plan_root")"

  (
    cd "$abs_plan_root" \
      && find . -type f \
        \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' \) \
        ! -name '*.tmp.*' -print0
  ) | cog::fn::refactor_null_path_fingerprint "$abs_plan_root"
}
