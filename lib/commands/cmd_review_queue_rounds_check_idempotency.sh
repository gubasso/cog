# shellcheck shell=bash
: 'desc: Flag a round whose declared artifacts an earlier round already deployed.'

__cog_review_queue_rounds_check_idempotency_self_check='(.schema=="cog.review-queue-rounds.idempotency.v1") and (.ok==true) and (.round_id|type=="string") and (.already_deployed|type=="array") and (.clean|type=="boolean")'

__cog_review_queue_rounds_check_idempotency_usage() {
  cog::fn::ui_data "Usage: cog review-queue-rounds-check-idempotency --queue <path> --round <id> (<out.json>|--json)"
}

cog::cmd::review_queue_rounds_check_idempotency() {
  local queue_path="" round_id="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_queue_rounds_check_idempotency_usage
        return 0
        ;;
      --queue)
        [[ $# -ge 2 && -n ${2:-} && -z $queue_path ]] || cog::fn::error_raise "MissingArgument" \
          "missing queue path" "option: --queue" "" "run 'cog review-queue-rounds-check-idempotency --help'"
        queue_path="$2"
        shift 2
        ;;
      --round)
        [[ $# -ge 2 && -n ${2:-} && -z $round_id ]] || cog::fn::error_raise "MissingArgument" \
          "missing round id" "option: --round" "" "run 'cog review-queue-rounds-check-idempotency --help'"
        round_id="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate idempotency output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-queue-rounds-check-idempotency option" "option: $1" "" \
          "run 'cog review-queue-rounds-check-idempotency --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many idempotency output paths" "argument: $1" "" \
          "run 'cog review-queue-rounds-check-idempotency --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $queue_path && -n $round_id && -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing idempotency argument" \
    "usage: cog review-queue-rounds-check-idempotency --queue <path> --round <id> (<out.json>|--json)" "" \
    "run 'cog review-queue-rounds-check-idempotency --help'"

  json="$(cog::fn::review_queue_rounds_idempotency_json "$queue_path" "$round_id")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_queue_rounds_check_idempotency_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_review_queue_rounds_check_idempotency_self_check" "$json"
  fi
}
