# shellcheck shell=bash

# Single source of truth for the handoff-JSON schema invariant. Both the build
# self-check (cmd_review_loop_input.sh) and validate use this one filter so the
# schema cannot drift between two copies.
#
# The keyset is expressed as a required subset plus an allowed superset rather
# than an enumeration of exact key lists: with two optional fields an
# enumeration needs four alternatives, and the next one doubles it again.
#
# `context` is an optional rich-context-brief payload and must be a non-empty
# string when present. `scope` is an optional declaration of what the run should
# review — commit selectors, an explicit path list, and whether the live working
# tree counts — for a consumer that runs without the session that produced the
# work. Both are omitted when absent, so the canonical 5-key envelope is
# byte-identical to what it always was.
#
# Every optional key is gated on `has(...)` rather than on `// <default>`,
# because `//` treats a present null as absent: `{"shas": null}` would validate
# and then read as the default, turning a malformed commit declaration into a
# silent working-tree scope — a review of the wrong thing that still reports
# clean.
__cog_review_loop_input_filter='
def nonempty: type == "string" and length > 0;
def thread_id: (. == null) or (type == "string" and test("^[A-Za-z0-9._:-]+$"));
def strings: (type == "array") and (all(.[]; nonempty));
((["impl_thread_id","implementation_review","plan_thread_id","reviewed_plan","task"] - [keys[]]) | length == 0) and
(([keys[]] - ["context","impl_thread_id","implementation_review","plan_thread_id","reviewed_plan","scope","task"]) | length == 0) and
(.task | nonempty) and
(.reviewed_plan | nonempty) and
(.implementation_review | nonempty) and
(.plan_thread_id | thread_id) and
(.impl_thread_id | thread_id) and
((has("context") | not) or (.context | nonempty)) and
((has("scope") | not) or (.scope | __SCOPE_DECLARATION__))
'

# The `scope` field is validated by the scope-declaration schema itself rather
# than by a second copy of its rules: the handoff and `cog review-scope
# --declaration` must accept exactly the same object, or the handoff becomes a
# way to smuggle in a scope the resolver will later refuse.
cog::fn::review_loop_input_schema_filter() {
  local declaration
  declaration="$(cog::fn::scope_declaration_filter)"
  printf '%s' "${__cog_review_loop_input_filter//__SCOPE_DECLARATION__/$declaration}"
}

cog::fn::review_loop_input_default_path() {
  local run_dir="${1:-}"
  cog::fn::rundir_path "$run_dir" review_loop_input.json
}

cog::fn::review_loop_input_validate_thread_id() {
  local label="${1:-}"
  local value="${2:-}"

  [[ -n $label ]] || cog::fn::error_raise "MissingArgument" \
    "missing thread id label" "function: cog::fn::review_loop_input_validate_thread_id" "" "pass a label"
  [[ $value =~ ^[A-Za-z0-9._:-]+$ ]] || cog::fn::error_raise "InvalidInput" \
    "bad thread id" "label: ${label}" "value must match ^[A-Za-z0-9._:-]+$" \
    "check the thread id file and retry"
}

__cog_review_loop_input_read_thread_id() {
  local path="$1"
  local label="$2"
  local __value_name="$3"
  local __present_name="$4"
  local value

  if [[ ! -e $path ]]; then
    printf -v "$__value_name" '%s' ""
    printf -v "$__present_name" '%s' false
    return 0
  fi

  [[ -f $path && -r $path ]] || cog::fn::error_raise "InputUnreadable" \
    "${label} is not readable" "path: ${path}" "" "check the file and retry"
  value="$(<"$path")"
  value="${value%$'\n'}"
  [[ -n $value ]] || cog::fn::error_raise "InvalidInput" \
    "${label} is empty" "path: ${path}" "" "write a valid thread id or remove the file"
  cog::fn::review_loop_input_validate_thread_id "$label" "$value"

  printf -v "$__value_name" '%s' "$value"
  printf -v "$__present_name" '%s' true
}

cog::fn::review_loop_input_build() {
  local run_dir="${1:-}"
  local context_file="${2:-}"
  local scope_file="${3:-}"
  local task_file reviewed_plan_file implementation_review_file plan_file impl_file
  local plan_tid="" impl_tid="" plan_present=false impl_present=false
  local context_source="/dev/null" context_present=false
  local scope='{}' scope_present=false

  [[ -n $run_dir ]] || cog::fn::error_raise "MissingArgument" \
    "missing run directory" "function: cog::fn::review_loop_input_build" "" "pass a run directory"

  task_file="$(cog::fn::rundir_path "$run_dir" request.md)"
  reviewed_plan_file="$(cog::fn::rundir_path "$run_dir" vetted-plan.md)"
  implementation_review_file="$(cog::fn::rundir_path "$run_dir" review.md)"
  plan_file="$(cog::fn::rundir_path "$run_dir" plan-thread-id)"
  impl_file="$(cog::fn::rundir_path "$run_dir" impl-thread-id)"

  cog::fn::rundir_require_file "$task_file" "request.md"
  cog::fn::rundir_require_file "$reviewed_plan_file" "vetted-plan.md"
  cog::fn::plan_doc::require_valid_file "$reviewed_plan_file"
  cog::fn::rundir_require_file "$implementation_review_file" "review.md"
  __cog_review_loop_input_read_thread_id "$plan_file" "plan-thread-id" plan_tid plan_present

  # The optional context brief is included verbatim when a non-empty file is given,
  # and omitted entirely otherwise so the canonical 5-key envelope is unchanged.
  if [[ -n $context_file ]]; then
    cog::fn::rundir_require_file "$context_file" "context brief"
    context_source="$context_file"
    context_present=true
  fi
  # The optional scope declaration is validated as JSON here so a malformed file
  # fails at build time rather than at the consumer, which has no session to
  # fall back on.
  if [[ -n $scope_file ]]; then
    cog::fn::rundir_require_file "$scope_file" "scope declaration"
    jq -e . "$scope_file" >/dev/null 2>&1 || cog::fn::error_raise "InvalidInput" \
      "scope declaration is not valid JSON" "path: ${scope_file}" "" "fix the JSON and retry"
    scope="$(jq -c . "$scope_file")"
    scope_present=true
  fi
  __cog_review_loop_input_read_thread_id "$impl_file" "impl-thread-id" impl_tid impl_present

  jq -n \
    --rawfile task "$task_file" \
    --rawfile reviewed_plan "$reviewed_plan_file" \
    --rawfile implementation_review "$implementation_review_file" \
    --arg plan_tid "$plan_tid" \
    --argjson plan_present "$plan_present" \
    --arg impl_tid "$impl_tid" \
    --argjson impl_present "$impl_present" \
    --rawfile context "$context_source" \
    --argjson context_present "$context_present" \
    --argjson scope "$scope" \
    --argjson scope_present "$scope_present" \
    '{
      task: $task,
      reviewed_plan: $reviewed_plan,
      implementation_review: $implementation_review,
      plan_thread_id: (if $plan_present then $plan_tid else null end),
      impl_thread_id: (if $impl_present then $impl_tid else null end)
    }
    + (if $context_present then {context: $context} else {} end)
    + (if $scope_present then {scope: $scope} else {} end)'
}

cog::fn::review_loop_input_validate_file() {
  local json_file="${1:-}" reviewed_plan

  [[ -n $json_file ]] || cog::fn::error_raise "MissingArgument" \
    "missing review-loop input file" "function: cog::fn::review_loop_input_validate_file" "" \
    "pass a JSON file path"
  [[ -e $json_file ]] || cog::fn::error_raise "InputNotFound" \
    "review-loop input file not found" "path: ${json_file}" "" "check the input path"
  [[ -f $json_file && -r $json_file ]] || cog::fn::error_raise "InputUnreadable" \
    "review-loop input file is not readable" "path: ${json_file}" "" "check file permissions"
  jq -e . "$json_file" >/dev/null 2>&1 || cog::fn::error_raise "InvalidInput" \
    "review-loop input is not valid JSON" "path: ${json_file}" "" "fix the JSON and retry"
  jq -e "$(cog::fn::review_loop_input_schema_filter)" "$json_file" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "review-loop input failed schema validation" "path: ${json_file}" \
    "expected task, reviewed_plan, implementation_review, plan_thread_id, impl_thread_id" \
    "fix the handoff JSON and retry"
  reviewed_plan="$(jq -r '.reviewed_plan' "$json_file")"
  cog::fn::plan_doc::require_valid_text "$reviewed_plan" "reviewed_plan"
}
