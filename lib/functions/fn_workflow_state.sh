# shellcheck shell=bash

# Run state, node directories, claim tokens, and receipts for the cog workflow
# engine (docs/reference/workflow-contract.md, "Artifacts").
#
# state_read and state_write are the only place exit code 1 originates: an
# internal failure reading or persisting state is 1, and everything the caller
# got wrong is 2.

cog::fn::workflow::state_path() {
  printf '%s/state.json\n' "${1%/}"
}

cog::fn::workflow::node_dir() {
  printf '%s/%s\n' "${1%/}" "$2"
}

cog::fn::workflow::state_read() {
  local run_dir="${1:-}"
  local path
  path="$(cog::fn::workflow::state_path "$run_dir")"

  [[ -f $path ]] || cog::fn::error_raise_with_exit 1 "InternalStateFailure" \
    "run state not found" "path: ${path}" \
    "the run directory carries no state.json" "run 'cog workflow resolve' first"
  jq -e '.' "$path" 2>/dev/null || cog::fn::error_raise_with_exit 1 "InternalStateFailure" \
    "run state does not parse" "path: ${path}" "" "the run directory is corrupt"
}

# Atomic write: a partial state.json is worse than none.
cog::fn::workflow::state_write() {
  local run_dir="${1:-}" json="${2:-}"
  local path tmp
  path="$(cog::fn::workflow::state_path "$run_dir")"
  tmp="${path}.tmp"

  printf '%s\n' "$json" >"$tmp" 2>/dev/null || cog::fn::error_raise_with_exit 1 \
    "InternalStateFailure" "could not write run state" "path: ${tmp}" "" "check run directory permissions"
  jq -e '.schema == "cog.workflow.state.v1"' "$tmp" >/dev/null 2>&1 \
    || cog::fn::error_raise_with_exit 1 "InternalStateFailure" \
      "refusing to persist malformed run state" "path: ${tmp}" "" "report this cog bug"
  mv -f -- "$tmp" "$path" 2>/dev/null || cog::fn::error_raise_with_exit 1 \
    "InternalStateFailure" "could not persist run state" "path: ${path}" "" "check run directory permissions"
}

# Claim and decision tokens are local anti-stale-write guards, not credentials.
cog::fn::workflow::new_token() {
  od -An -tx1 -N16 /dev/urandom | tr -d ' \n'
}

# Inventory a node directory: cog counts files and never reads them.
cog::fn::workflow::inventory() {
  local dir="${1:-}"

  if [[ ! -d $dir ]]; then
    printf '%s\n' '[]'
    return 0
  fi
  (
    cd "$dir" || exit 1
    find . -type f ! -name 'outputs.json' -printf '%P\t%s\n' 2>/dev/null | LC_ALL=C sort
  ) | jq -Rsc 'split("\n") | map(select(length > 0) | split("\t") | {path: .[0], bytes: (.[1] | tonumber)})'
}

cog::fn::workflow::node_json() {
  local state="${1:-}" as="${2:-}"
  jq -c --arg as "$as" '.nodes | map(select(.as == $as)) | first // empty' <<<"$state"
}

# A node is ready when it is pending and every needs: target is done.
cog::fn::workflow::node_ready() {
  local state="${1:-}" as="${2:-}"
  jq -e --arg as "$as" '
    .nodes as $n
    | ($n | map(select(.status == "done") | .as)) as $done
    | ($n | map(select(.as == $as)) | first) as $node
    | ($node != null)
      and ($node.status == "pending")
      and (($node.needs // []) | all(. as $t | ($done | index($t)) != null))
  ' <<<"$state" >/dev/null 2>&1
}

# The concrete upstream directories needs: hands to a node.
cog::fn::workflow::node_inputs() {
  local state="${1:-}" as="${2:-}"
  jq -c --arg as "$as" '
    (.nodes | map(select(.as == $as)) | first) as $node
    | (($node.needs // []) | map(. + "/"))
  ' <<<"$state"
}

# Recompute the run state from its nodes. Terminal run states live in the JSON
# state field at exit 0, never in the exit code.
#
# A pending node whose needs: target failed can never become ready, and nothing
# in this release moves a node out of failed. Such a node is blocked, and so is
# anything downstream of it; a run whose only pending nodes are blocked is
# terminal. Reporting it as running instead would leave `next` handing out 75
# forever with no transition that could ever clear it.
cog::fn::workflow::recompute_state() {
  jq -c '
    .nodes as $n
    | ($n | map(select(.status == "failed") | .as)) as $failed
    | (reduce range(0; ($n | length)) as $_ ($failed;
        . as $blocked
        | (. + [$n[] | select(.status == "pending")
                | select((.needs // []) | any(. as $t | ($blocked | index($t)) != null))
                | .as]) | unique)) as $blocked
    | .state = (
        if ($n | length) == 0 then "completed"
        elif ($n | all(.status == "done")) then "completed"
        elif ($n | any(.status == "claimed")) then "running"
        elif ([$n[] | . as $node | select($node.status == "pending")
                | select(($blocked | index($node.as)) == null)] | length) > 0 then "running"
        elif ($n | any(.status == "failed")) then "failed"
        else "running" end)
  ' <<<"${1:-}"
}
