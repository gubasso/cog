# shellcheck shell=bash
: 'desc: Inventory all plan-vault queues and repo/plan fingerprints.'

__cog_review_queue_rounds_scan_self_check='
  (.ok == true) and
  (.repo_root | type == "string" and startswith("/")) and
  (.main_queue_path | type == "string" and startswith("/")) and
  (.repo_fingerprint | type == "string" and test("^[0-9a-f]{64}$")) and
  (.plans_fingerprint | type == "string" and test("^[0-9a-f]{64}$")) and
  (.queues | type == "array") and
  ([.queues[]? |
    (.path | type == "string" and startswith("/")) and
    (.schema == "plans" or .schema == "rounds") and
    (.items | type == "array") and
    ([.items[]? |
      (.schema == "plans" or .schema == "rounds") and
      (.queue_path | type == "string" and startswith("/")) and
      (.item | type == "string" and . != "") and
      (.status == "backlog" or .status == "todo" or .status == "doing" or .status == "done") and
      (.depends_on | type == "array") and
      (.prompt | type == "string" and . != "") and
      (.notes | type == "string") and
      (.mutable | type == "boolean")
    ] | all)
  ] | all)
'

__cog_review_queue_rounds_scan_usage() {
  cog::fn::ui_data "Usage: cog review-queue-rounds-scan --repo-root <dir> --main-queue <path> [--plan-root <dir>] (<out.json>|--json)"
}

__cog_review_queue_rounds_scan_build_json() {
  local repo_root="$1" main_queue="$2" plan_root="$3"
  local abs_repo abs_main resolve_json resolved_plan_root inventory repo_fingerprint plans_fingerprint

  [[ -n $repo_root && -n $main_queue ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing review-queue-rounds-scan argument" \
    "usage: cog review-queue-rounds-scan --repo-root <dir> --main-queue <path> [--plan-root <dir>] (<out.json>|--json)" "" \
    "run 'cog review-queue-rounds-scan --help'"

  abs_repo="$(realpath "$repo_root")"
  abs_main="$(realpath "$main_queue")"

  # Resolve the plan vault (local or global store) through the shared resolver.
  resolve_json="$(cog::fn::plan_runner_resolve_json "$abs_repo" "$abs_main")"
  [[ "$(jq -r '.target_type' <<<"$resolve_json")" == "main-queue" ]] || cog::fn::error_raise "InvalidInput" \
    "scan --main-queue must be a queue-plans.yaml" "path: ${abs_main}" "" "pass <PLAN_ROOT>/queue-plans.yaml"
  abs_main="$(jq -r '.main_queue' <<<"$resolve_json")"
  resolved_plan_root="$(jq -r '.plan_root' <<<"$resolve_json")"
  # A caller-supplied --plan-root must name the same vault the resolver derived from
  # --main-queue; otherwise the inventory and fingerprints would describe one vault
  # while the main queue belongs to another, hiding or misreporting drift.
  if [[ -n $plan_root ]]; then
    plan_root="$(realpath -m "$plan_root")"
    [[ $plan_root == "$resolved_plan_root" ]] || cog::fn::error_raise "InvalidInput" \
      "scan --plan-root does not match the resolved plan vault" \
      "plan_root: ${plan_root}" "resolved: ${resolved_plan_root}" \
      "omit --plan-root or pass the vault root that owns --main-queue"
  else
    plan_root="$resolved_plan_root"
  fi

  inventory="$(cog::fn::review_queue_rounds_inventory_json "$abs_repo" "$abs_main" "$plan_root")"
  repo_fingerprint="$(cog::fn::review_queue_rounds_repo_fingerprint "$abs_repo" "$plan_root")"
  plans_fingerprint="$(cog::fn::review_queue_rounds_plans_fingerprint "$plan_root")"

  jq -n \
    --argjson ok true \
    --arg repo_root "$abs_repo" \
    --arg main_queue_path "$abs_main" \
    --arg repo_fingerprint "$repo_fingerprint" \
    --arg plans_fingerprint "$plans_fingerprint" \
    --argjson inventory "$inventory" \
    '{ok: $ok, repo_root: $repo_root, main_queue_path: $main_queue_path,
      repo_fingerprint: $repo_fingerprint, plans_fingerprint: $plans_fingerprint,
      queues: $inventory.queues}'
}

cog::cmd::review_queue_rounds_scan() {
  local repo_root="" main_queue="" plan_root="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_queue_rounds_scan_usage
        return 0
        ;;
      --repo-root)
        [[ $# -ge 2 && -z $repo_root ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
          "missing repo root" "option: --repo-root" "" "run 'cog review-queue-rounds-scan --help'"
        repo_root="$2"
        shift 2
        ;;
      --main-queue)
        [[ $# -ge 2 && -z $main_queue ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
          "missing main queue path" "option: --main-queue" "" "run 'cog review-queue-rounds-scan --help'"
        main_queue="$2"
        shift 2
        ;;
      --plan-root)
        [[ $# -ge 2 && -z $plan_root ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
          "missing plan root" "option: --plan-root" "" "run 'cog review-queue-rounds-scan --help'"
        plan_root="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" \
          "duplicate review-queue-rounds-scan output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" \
          "unknown review-queue-rounds-scan option" "option: $1" "" "run 'cog review-queue-rounds-scan --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "TooManyArguments" \
          "too many review-queue-rounds-scan output paths" "argument: $1" "" \
          "run 'cog review-queue-rounds-scan --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing review-queue-rounds-scan output mode" "usage: cog review-queue-rounds-scan ... (<out.json>|--json)" "" \
    "run 'cog review-queue-rounds-scan --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_review_queue_rounds_scan_build_json "$repo_root" "$main_queue" "$plan_root")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_queue_rounds_scan_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_review_queue_rounds_scan_self_check" "$json"
  fi
}
