# shellcheck shell=bash
: 'desc: Inventory all implementation-plan queues and repo/plan fingerprints.'

__cog_plans_revision_scan_self_check='
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

__cog_plans_revision_scan_usage() {
  cog::fn::ui_data "Usage: cog plans-revision-scan --repo-root <dir> --main-queue <path> (<out.json>|--json)"
}

__cog_plans_revision_scan_build_json() {
  local repo_root="$1" main_queue="$2"
  local abs_repo abs_main inventory repo_fingerprint plans_fingerprint

  [[ -n $repo_root && -n $main_queue ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing plans-revision-scan argument" \
    "usage: cog plans-revision-scan --repo-root <dir> --main-queue <path> (<out.json>|--json)" "" \
    "run 'cog plans-revision-scan --help'"

  abs_repo="$(realpath "$repo_root")"
  abs_main="$(realpath "$main_queue")"
  inventory="$(cog::fn::plans_revision_inventory_json "$abs_repo" "$abs_main")"
  repo_fingerprint="$(cog::fn::plans_revision_repo_fingerprint "$abs_repo")"
  plans_fingerprint="$(cog::fn::plans_revision_plans_fingerprint "$abs_repo")"

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

cog::cmd::plans_revision_scan() {
  local repo_root="" main_queue="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plans_revision_scan_usage
        return 0
        ;;
      --repo-root)
        [[ $# -ge 2 && -z $repo_root ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
          "missing repo root" "option: --repo-root" "" "run 'cog plans-revision-scan --help'"
        repo_root="$2"
        shift 2
        ;;
      --main-queue)
        [[ $# -ge 2 && -z $main_queue ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
          "missing main queue path" "option: --main-queue" "" "run 'cog plans-revision-scan --help'"
        main_queue="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" \
          "duplicate plans-revision-scan output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" \
          "unknown plans-revision-scan option" "option: $1" "" "run 'cog plans-revision-scan --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "TooManyArguments" \
          "too many plans-revision-scan output paths" "argument: $1" "" \
          "run 'cog plans-revision-scan --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing plans-revision-scan output mode" "usage: cog plans-revision-scan ... (<out.json>|--json)" "" \
    "run 'cog plans-revision-scan --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_plans_revision_scan_build_json "$repo_root" "$main_queue")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plans_revision_scan_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_plans_revision_scan_self_check" "$json"
  fi
}
