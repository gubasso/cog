# shellcheck shell=bash

# Executor-stamped round-prompt assembly and validation (ADR-0015). The set of
# stampable executors is derived from the executor-capability SoT, never a
# duplicated list, so a stamp can only name an executor the matcher can return.

cog::fn::round_prompt::known_executors_json() {
  cog::fn::power_grade::executor_json "" | jq -c '[.executors[].executor]'
}

cog::fn::round_prompt::is_known_executor() {
  local name="${1:-}"
  [[ -n $name ]] || return 1
  cog::fn::round_prompt::known_executors_json \
    | jq -e --arg n "$name" 'index($n) != null' >/dev/null
}

# Assemble "/<executor> <flags> <round-path>". Fails closed on a missing,
# reserved (null/empty), or unknown executor.
cog::fn::round_prompt::build_json() {
  local executor="${1:-}" round_path="${2:-}" args="${3:-}" flags prompt
  [[ -n $executor ]] || cog::fn::error_raise "MissingArgument" \
    "missing executor name" "option: --executor" \
    "a reserved (>30) round has no executor and is never queued" \
    "route a reserved round back through plan-split (ADR-0015)"
  [[ $executor != null ]] || cog::fn::error_raise "InvalidInput" \
    "reserved round cannot be stamped" "executor: null" \
    "a reserved (>30) round is never queued" \
    "route the round back through plan-split (ADR-0015)"
  [[ -n $round_path ]] || cog::fn::error_raise "MissingArgument" \
    "missing round path" "option: --round-path" "" "pass the round file path"
  cog::fn::round_prompt::is_known_executor "$executor" || cog::fn::error_raise "InvalidInput" \
    "unknown executor" "executor: ${executor}" \
    "not a graded executor-* in data/power-grade/executor-capability" \
    "use an executor reported by 'cog power-grade executor'"
  flags="${args:--ar}"
  prompt="/${executor} ${flags} ${round_path}"
  jq -n \
    --arg schema "cog.round-prompt.build.v1" \
    --arg executor "$executor" \
    --arg round_path "$round_path" \
    --arg flags "$flags" \
    --arg prompt "$prompt" \
    '{schema: $schema, ok: true, executor: $executor, round_path: $round_path,
      flags: $flags, prompt: $prompt}'
}

# Classify an existing round prompt string. Emits ok/executor/known/reserved/
# well_formed. A legacy "/executor-prex -ar <path>" stays valid; a reserved or
# unknown executor, or a prompt missing a flag-and-path pair, fails the ok gate.
cog::fn::round_prompt::validate_json() {
  local prompt="${1:-}" trimmed rest token rest_args reserved known well_formed ok
  local -a parts=()
  [[ -n $prompt ]] || cog::fn::error_raise "MissingArgument" \
    "missing prompt string" "option: --prompt" "" "pass the queue prompt to validate"
  trimmed="${prompt#"${prompt%%[![:space:]]*}"}"
  reserved=false
  known=false
  well_formed=false
  token=""
  if [[ $trimmed == /* ]]; then
    rest="${trimmed#/}"
    read -r token rest_args <<<"$rest"
    [[ -n $token && $token != null ]] || reserved=true
    if [[ $reserved == false ]] && cog::fn::round_prompt::is_known_executor "$token"; then
      known=true
    fi
    read -r -a parts <<<"$rest_args"
    local has_flag=false has_path=false w
    for w in "${parts[@]}"; do
      if [[ $w == -* ]]; then has_flag=true; else has_path=true; fi
    done
    [[ $has_flag == true && $has_path == true ]] && well_formed=true
  fi
  ok=false
  [[ $known == true && $reserved == false && $well_formed == true ]] && ok=true
  jq -n \
    --arg schema "cog.round-prompt.validate.v1" \
    --arg prompt "$prompt" \
    --arg executor "$token" \
    --argjson ok "$ok" \
    --argjson known "$known" \
    --argjson reserved "$reserved" \
    --argjson well_formed "$well_formed" \
    '{schema: $schema, ok: $ok, prompt: $prompt, executor: $executor,
      known: $known, reserved: $reserved, well_formed: $well_formed}'
}

# Producer-side, build-time gate over a whole queue file. For a `rounds` queue,
# every prompt must be a valid executor stamp; for a `plans` queue, every prompt
# must be a "/runner-plan -ar @<plan-dir>/" dispatch. Runners never call this —
# they stay producer-blind and verbatim. Returns EX_DATAERR when any entry fails.
cog::fn::round_prompt::validate_queue_json() {
  local queue_path="${1:-}" schema="${2:-}" key invalid_json checked
  [[ -n $queue_path ]] || cog::fn::error_raise "MissingArgument" \
    "missing queue path" "option: --queue" "" "pass the queue file path"
  key="$(cog::fn::queue_schema_key "$schema")" || cog::fn::error_raise "InvalidInput" \
    "invalid queue schema" "schema: ${schema}" "expected plans or rounds" "use --schema plans|rounds"
  cog::fn::queue_validate_file "$queue_path" "$key"
  invalid_json='[]'
  checked=0
  local item prompt entry_check reason
  while IFS=$'\t' read -r item prompt; do
    [[ -n $item ]] || continue
    checked=$((checked + 1))
    reason=""
    if [[ $key == rounds ]]; then
      entry_check="$(cog::fn::round_prompt::validate_json "$prompt")"
      if [[ "$(jq -r '.ok' <<<"$entry_check")" != true ]]; then
        if [[ "$(jq -r '.reserved' <<<"$entry_check")" == true ]]; then
          reason="reserved round must not be queued"
        elif [[ "$(jq -r '.known' <<<"$entry_check")" != true ]]; then
          reason="unknown executor stamp"
        else
          reason="malformed executor prompt (need flag and round path)"
        fi
      fi
    else
      # ADR-0015: the top-level ledger prompt must be the exact
      # `/runner-plan -ar @<plan-dir>/` dispatch. Tokenize and require the
      # /runner-plan head, an -ar flag, and a non-empty @<plan-dir> target, so a
      # malformed prompt (wrong flag, missing -ar, or a bare `@`) fails closed
      # instead of slipping a contract-breaking queue item past the producer gate.
      local plan_head plan_rest plan_tok plan_has_ar=false plan_has_target=false
      local -a plan_parts=()
      read -r plan_head plan_rest <<<"$prompt"
      read -r -a plan_parts <<<"$plan_rest"
      for plan_tok in "${plan_parts[@]}"; do
        if [[ $plan_tok == "-ar" ]]; then
          plan_has_ar=true
        elif [[ $plan_tok == @?* ]]; then
          plan_has_target=true
        fi
      done
      if [[ $plan_head != /runner-plan || $plan_has_ar != true || $plan_has_target != true ]]; then
        reason="plans entry must dispatch /runner-plan -ar @<plan-dir>/"
      fi
    fi
    if [[ -n $reason ]]; then
      invalid_json="$(jq -c --arg item "$item" --arg prompt "$prompt" --arg reason "$reason" \
        '. + [{item: $item, prompt: $prompt, reason: $reason}]' <<<"$invalid_json")"
    fi
  done < <(KEY="$key" yq e -r '.[strenv(KEY)][]? | .item + "\t" + .prompt' "$queue_path")

  local ok
  if [[ "$(jq 'length' <<<"$invalid_json")" -eq 0 ]]; then ok=true; else ok=false; fi
  jq -n \
    --arg schema "cog.round-prompt.queue.v1" \
    --arg queue_path "$queue_path" \
    --arg queue_schema "$key" \
    --argjson ok "$ok" \
    --argjson checked "$checked" \
    --argjson invalid "$invalid_json" \
    '{schema: $schema, ok: $ok, queue_path: $queue_path, queue_schema: $queue_schema,
      checked: $checked, invalid: $invalid}'
}
