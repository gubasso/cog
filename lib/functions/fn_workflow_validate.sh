# shellcheck shell=bash

# The workflow validator (docs/reference/workflow-contract.md, "Validator
# rules"). Validation runs once at load, before any agent is spawned, so a
# failure does not land at depth three after real spend.
#
# Every entry point prints a JSON array of findings. An empty array is a pass.
# The caller turns a non-empty array into exit 2; these helpers never exit, so
# `validate` with no key can report every workflow rather than the first.
#
# jq note: `index(f)` evaluates f against the array it is applied to, not
# against the surrounding element. Every membership test below binds the needle
# to a variable first; writing `$haystack | index(.needle)` silently searches
# for the haystack itself.

# Two deliberate non-checks, recorded so they are not added later:
#   * A step file's described inputs:/artifacts: are aligned against its skill
#     at lint time and are never enforced at run time.
#   * The subagent budget is not a validator check. The structural part is
#     max_workflow_depth; the harness part is the opt-in --max-fresh-depth an
#     orchestrator passes from its own remaining budget.

__cog_workflow_finding() {
  jq -nc --arg rule "$1" --arg where "$2" --arg message "$3" \
    '{rule: $rule, severity: "error", where: $where, message: $message}'
}

# --- Registry invariants ---------------------------------------------------

# shellcheck disable=SC2016 # jq program: $-prefixed names are jq variables, not shell.
__cog_workflow_registry_program='
def f($rule; $where; $msg): {rule: $rule, severity: "error", where: $where, message: $msg};
. as $r
| ($r["workflow-engines"]) as $engines
| ($r["workflow-engine-providers"]) as $providers
| if ($engines | type) != "array" then
    [f("registry-shape"; "data/workflow-engines"; "workflow-engines is not a list")]
  elif ($providers | type) != "object" then
    [f("registry-shape"; "data/workflow-engines"; "workflow-engine-providers is not a map")]
  else
    [ $engines[] | . as $e
      | select((($e.id // "") | tostring) != (((($e.provider // "") | tostring)) + "-" + (($e.model // "") | tostring) + "-" + (($e.effort // "") | tostring)))
      | f("derived-ids"; ("engine: " + (($e.id // "?") | tostring)); "id is not <provider>-<model>-<effort>") ]
    + ( [$engines[] | (.id // "?") | tostring] | group_by(.) | map(select(length > 1))
        | map(f("unique-ids"; ("engine: " + .[0]); "duplicate engine id")) )
    + [ $engines[] | . as $e
        | select(($e | keys_unsorted | sort) != ["effort", "id", "model", "provider"])
        | f("exactly-four-fields"; ("engine: " + (($e.id // "?") | tostring)); "record does not carry exactly id, provider, model, effort") ]
    + [ $engines[] | . as $e
        | (($providers[($e.provider // "") | tostring] // {}).efforts // []) as $ladder
        | select(($ladder | index($e.effort)) == null)
        | f("provider-valid-efforts"; ("engine: " + (($e.id // "?") | tostring)); "effort is not on the provider effort ladder") ]
    + [ $engines[] | . as $e
        | select(((($providers[($e.provider // "") | tostring] // {}).runner // "") | tostring) == "")
        | f("existing-provider-runner"; ("engine: " + (($e.id // "?") | tostring)); "provider declares no runner") ]
  end
'

cog::fn::workflow::validate_registry() {
  local registry="${1:-}"
  [[ -n $registry ]] || registry="$(cog::fn::workflow::registry_json)"
  jq -c "$__cog_workflow_registry_program" <<<"$registry"
}

# --- Workflow definitions --------------------------------------------------

# One jq program over a fully assembled bundle. Assembling the bundle in Bash
# keeps file resolution (which is layered) out of jq; the structural rules stay
# in one place here.
# shellcheck disable=SC2016 # jq program: $-prefixed names are jq variables, not shell.
__cog_workflow_validate_program='
def f($rule; $where; $msg): {rule: $rule, severity: "error", where: $where, message: $msg};
def kindsOf($e): if ($e | type) == "object" then (["step", "workflow", "loop"] | map(. as $k | select($e | has($k)))) else [] end;
def isLiteral($v): (($v | type) == "string") and (($v | test("[${}]")) | not);

# Kahn topological sort; the residual is empty iff the graph is acyclic.
# Targets that name no node are treated as satisfied — a missing needs: target
# is reported by its own rule and must not also masquerade as a cycle.
def residual($nodes):
  ($nodes | map(.as)) as $all
  | def walkdown($state):
      ($state.rem | map(. as $n | select(
        (($n.needs // []) | all(. as $t
          | (($all | index($t)) == null) or (($state.done | index($t)) != null)))
      ))) as $ready
      | if ($ready | length) == 0 then $state
        else
          ($ready | map(.as)) as $names
          | walkdown({
              rem: ($state.rem | map(. as $n | select(($names | index($n.as)) == null))),
              done: ($state.done + $names)
            })
        end;
    walkdown({rem: $nodes, done: []}) | .rem;

. as $b
| ($b.registry_ids) as $ids
| (if (($b.meta.max_workflow_depth // 3) | type) == "number"
      then ($b.meta.max_workflow_depth // 3) else 3 end) as $maxdepth

# --- per-workflow-file rules ---
| [ $b.workflows | to_entries[]
    | .key as $wfkey | .value as $doc
    | ("workflows/" + $wfkey + ".yaml") as $where
    | if $doc == null then []
      # Fail closed on a malformed container rather than letting jq abort on a
      # non-iterable: a shape error owes a finding and exit 2 like any other.
      elif ($doc | type) != "object" then
        [f("workflow-shape"; $where; "the definition is not a mapping (" + ($doc | type) + ")")]
      elif ($doc | has("steps")) and (($doc.steps | type) != "array") then
        [f("workflow-shape"; $where; "steps: is not a list (" + ($doc.steps | type) + ")")]
      else
        # `E as $x | body` binds E and evaluates body; anything summed onto E
        # before the binding is discarded. Every finding below is therefore
        # accumulated inside the body, after the bindings.
        ( [ ($doc.steps // [])[] | . as $entry
            | (kindsOf($entry)) as $ks
            | if ($ks | length) != 1 then
                {bad: f("one-kind-key"; $where; "an entry carries " + (($ks | length) | tostring) + " kind keys; exactly one of step:, workflow:, loop: is required")}
              else
                ($ks[0]) as $k | ($entry[$k] // {}) as $body
                | {node: {kind: $k, body: $body,
                          id: ($body.id // null),
                          as: ($body.as // $body.id // null),
                          needs: ($body.needs // [])}}
              end ] ) as $parsed
        | ([$parsed[] | select(has("bad")) | .bad]) as $shapeFindings
        | ([$parsed[] | select(has("node")) | .node]) as $nodes
        | ($nodes | map(.as) | map(select(. != null))) as $all
        # Rule 9: no skill: key anywhere under workflows/, at any nesting level.
        | ( if ([$doc | .. | objects | select(has("skill"))] | length) > 0
              then [f("no-skill-under-workflows"; $where; "a skill: key appears under workflows/; only steps/ may carry skill:")]
              else [] end )
          + $shapeFindings
          # entry shape: step:/workflow: need an id; loop: needs an as.
          + [ $nodes[] | select(.kind != "loop" and (.id == null))
              | f("entry-shape"; $where; "a " + .kind + ": entry carries no id") ]
          + [ $nodes[] | select(.kind == "loop" and (.as == null))
              | f("entry-shape"; $where; "a loop: entry carries no as") ]

          # Rule 2: as unique within the DAG, and every needs target present.
          + ( $all | group_by(.) | map(select(length > 1))
              | map(f("as-unique-and-needs-present"; $where; "duplicate as: " + .[0])) )
          + [ $nodes[] | (.needs // [])[] | . as $t
              | select(($all | index($t)) == null)
              | f("as-unique-and-needs-present"; $where; "needs: target not present in the DAG: " + ($t | tostring)) ]

          # Rule 3: no cycle among needs edges.
          + ( residual([$nodes[] | select(.as != null)]) as $res
              | if ($res | length) > 0
                  then [f("no-cycle"; $where; "cycle among needs: edges involving " + ($res | map(.as) | join(", ")))]
                  else [] end )

          # Rule 4: engine is a literal in the registry; optional on a call
          # site, and absent on a node that runs no agent.
          + [ $nodes[] | select(.kind != "step" and (.body | has("engine")))
              | f("engine-literal"; $where; "a " + .kind + ": node carries engine:, but it runs no agent") ]
          + [ $nodes[] | select(.kind == "step" and (.body | has("engine")))
              | .body.engine as $en
              | if (isLiteral($en) | not)
                  then f("engine-literal"; $where; "call-site engine: is not a plain literal")
                elif (($ids | index($en)) == null)
                  then f("engine-literal"; $where; "call-site engine: is not in the registry: " + ($en | tostring))
                else empty end ]

          # Rule 5: loop: carries both until: and max_rounds:.
          + [ $nodes[] | select(.kind == "loop") | select((.body | has("until")) | not)
              | f("loop-keys"; $where; "a loop: node carries no until:") ]
          + [ $nodes[] | select(.kind == "loop") | select((.body | has("max_rounds")) | not)
              | f("loop-keys"; $where; "a loop: node carries no max_rounds:") ]

          # Rule 6: id/as/engine/until parse as strings; until non-empty.
          + [ $nodes[] | . as $n | ["id", "as", "engine", "until"][] | . as $field
              | select($n.body | has($field))
              | select(($n.body[$field] | type) != "string")
              | f("scalar-strings"; $where; $field + ": does not parse as a string (" + ($n.body[$field] | type) + ")") ]
          + [ $nodes[] | select(.kind == "loop")
              | select((.body.until | type) == "string")
              | select((.body.until | gsub("^\\s+|\\s+$"; "")) == "")
              | f("scalar-strings"; $where; "until: is empty") ]

          # Rule 7: max_rounds is a positive integer.
          + [ $nodes[] | select(.body | has("max_rounds")) | .body.max_rounds as $mr
              | select((($mr | type) != "number") or ($mr != ($mr | floor)) or ($mr <= 0))
              | f("max-rounds-positive"; $where; "max_rounds: is not a positive integer") ]

          # as: names the node directory under the run directory, so it must be
          # one safe path segment. Without this a definition can name
          # "../../elsewhere" and resolve would mkdir outside the run directory.
          + [ $nodes[] | select(.as != null) | select((.as | type) == "string")
              | select((.as | test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) | not)
              | f("safe-instance-name"; $where; "as: is not a single safe path segment: " + (.as | tostring)) ]

          # A loop resolves to one node carrying an unexpanded but fully
          # validated template, so entries inside the template get the kind,
          # engine, and scalar rules the outer DAG gets. Inner step ids are
          # collected by the Bash walker, so their definitions are already
          # covered by the per-step-definition rules below.
          + [ $nodes[] | select(.kind == "loop")
              | ((.body.steps // []) | if type == "array" then . else [] end)[]
              | (kindsOf(.)) as $ks | select(($ks | length) != 1)
              | f("one-kind-key"; $where; "a loop: template entry carries " + (($ks | length) | tostring) + " kind keys; exactly one of step:, workflow:, loop: is required") ]
          + [ $nodes[] | select(.kind == "loop")
              | ((.body.steps // []) | if type == "array" then . else [] end)[]
              | select((type == "object") and has("step")) | (.step // {}) as $ib
              | select(($ib | type) == "object") | select($ib | has("engine"))
              | $ib.engine as $en
              | if (isLiteral($en) | not)
                  then f("engine-literal"; $where; "a loop: template call-site engine: is not a plain literal")
                elif (($ids | index($en)) == null)
                  then f("engine-literal"; $where; "a loop: template call-site engine: is not in the registry: " + ($en | tostring))
                else empty end ]
          + [ $nodes[] | select(.kind == "loop")
              | ((.body.steps // []) | if type == "array" then . else [] end)[]
              | select((type == "object") and has("step")) | (.step // {}) as $ib
              | select(($ib | type) == "object")
              | ["id", "as", "engine"][] | . as $field
              | select($ib | has($field)) | select(($ib[$field] | type) != "string")
              | f("scalar-strings"; $where; "loop: template " + $field + ": does not parse as a string (" + ($ib[$field] | type) + ")") ]
      end ]
  | flatten

# --- unresolvable references ---
+ [ $b.workflows | to_entries[] | select(.value == null)
    | f("unresolvable-reference"; ("workflows/" + .key + ".yaml"); "no layer carries this workflow definition") ]
+ [ $b.steps | to_entries[] | select(.value == null)
    | f("unresolvable-reference"; ("steps/" + .key + ".yaml"); "no layer carries this step definition") ]

# --- per-step-definition rules ---
+ ( [ $b.steps | to_entries[] | select(.value != null)
      | .key as $sid | .value as $doc
      | ("steps/" + $sid + ".yaml") as $where
      | if ($doc | type) != "object" then
          [f("step-shape"; $where; "the definition is not a mapping (" + ($doc | type) + ")")]
        else
          [ ["id", "engine"][] | . as $field
              | select($doc | has($field))
              | select(($doc[$field] | type) != "string")
              | f("scalar-strings"; $where; $field + ": does not parse as a string (" + ($doc[$field] | type) + ")") ]
          + ( if (($doc | has("engine")) | not)
                then [f("engine-literal"; $where; "a step definition carries no engine:; it is required on every definition")]
              elif (isLiteral($doc.engine) | not)
                then [f("engine-literal"; $where; "engine: is not a plain literal")]
              elif (($ids | index($doc.engine)) == null)
                then [f("engine-literal"; $where; "engine: is not in the registry: " + ($doc.engine | tostring))]
              else [] end )
        end ] | flatten )

# --- rule 3, second half: no cycle across file references ---
# Detected over the assembled reference graph rather than along one walk. A
# per-walk ancestor check misses a cycle whose participants were both first
# reached through a different branch, so the whole graph is sorted at once.
+ ( ($b.refedges // []) as $edges
    | (($b.workflows | keys) + [$edges[].to] | unique) as $names
    | residual([$names[] | . as $n | {as: $n, needs: [$edges[] | select(.from == $n) | .to]}]) as $res
    | if ($res | length) > 0
        then [f("no-cycle"; ("workflows/" + $b.key + ".yaml");
                "workflow: reference cycle across files involving " + ($res | map(.as) | join(", ")))]
        else [] end )

# --- meta shape ---
+ ( if (($b.meta | type) == "object") and ($b.meta | has("max_workflow_depth"))
      and (($b.meta.max_workflow_depth | type) != "number")
      then [f("meta-shape"; "meta.yaml"; "max_workflow_depth: is not a number")]
      else [] end )

# --- rule 8: reference nesting within max_workflow_depth ---
+ ( if ($b.depth // 0) > $maxdepth
      then [f("reference-depth"; ("workflows/" + $b.key + ".yaml");
              "reference nesting is " + (($b.depth // 0) | tostring) + ", over max_workflow_depth " + ($maxdepth | tostring))]
      else [] end )

# --- findings the Bash collector produced (parse errors, file cycles) ---
+ ($b.prior // [])
'

# Serialize a Bash name->JSON associative array into one JSON object.
__cog_workflow_map_json() {
  local -n __map_ref="$1"
  local k out='{}'

  for k in "${!__map_ref[@]}"; do
    out="$(jq -c --arg k "$k" --argjson v "${__map_ref[$k]}" '. + {($k): $v}' <<<"$out")"
  done
  printf '%s\n' "$out"
}

# Collect a workflow and everything it references, then run the program.
# Prints a JSON array of findings.
cog::fn::workflow::validate_key() {
  local key="${1:-}"
  local registry="${2:-}"
  local meta="${3:-}"
  local -A wf_docs=() step_docs=()
  local -a prior=()
  local -a queue=()
  local -a edges=()
  local max_depth_seen=0
  local path doc cur depth entry ref sid

  if ! cog::fn::workflow::valid_key "$key"; then
    __cog_workflow_finding "unresolvable-reference" "key: ${key}" \
      "not a valid workflow key; expected [a-z0-9][a-z0-9-]*" | jq -sc '.'
    return 0
  fi

  [[ -n $registry ]] || registry="$(cog::fn::workflow::registry_json)"
  [[ -n $meta ]] || meta="$(cog::fn::workflow::load_meta)"

  # Breadth-first over workflow: references. Each file is loaded once; the
  # reference edges are collected here and sorted for cycles in the jq program,
  # because a cycle can involve two files that a single walk reaches through
  # different branches.
  queue=("${key}|0")
  while ((${#queue[@]} > 0)); do
    entry="${queue[0]}"
    queue=("${queue[@]:1}")
    cur="${entry%%|*}"
    depth="${entry##*|}"

    ((depth > max_depth_seen)) && max_depth_seen="$depth"

    [[ -n ${wf_docs[$cur]+x} ]] && continue

    if ! path="$(cog::fn::workflow::resolve_file "$(cog::fn::workflow::workflow_rel "$cur")")"; then
      wf_docs["$cur"]="null"
      continue
    fi
    if ! doc="$(cog::fn::workflow::load_yaml "$path")" || [[ -z $doc ]]; then
      wf_docs["$cur"]="null"
      prior+=("$(__cog_workflow_finding "parse-error" "workflows/${cur}.yaml" "the definition does not parse as YAML")")
      continue
    fi
    wf_docs["$cur"]="$doc"

    while IFS= read -r ref; do
      [[ -n $ref ]] || continue
      edges+=("${cur}|${ref}")
      queue+=("${ref}|$((depth + 1))")
    done < <(jq -r 'if (.steps | type) == "array" then .steps[] | select(type == "object" and has("workflow")) | .workflow.id // empty else empty end' <<<"$doc")

    while IFS= read -r sid; do
      [[ -n $sid ]] || continue
      [[ -n ${step_docs[$sid]+x} ]] && continue
      if ! path="$(cog::fn::workflow::resolve_file "$(cog::fn::workflow::step_rel "$sid")")"; then
        step_docs["$sid"]="null"
        continue
      fi
      if ! doc="$(cog::fn::workflow::load_yaml "$path")" || [[ -z $doc ]]; then
        step_docs["$sid"]="null"
        prior+=("$(__cog_workflow_finding "parse-error" "steps/${sid}.yaml" "the definition does not parse as YAML")")
        continue
      fi
      step_docs["$sid"]="$doc"
    done < <(jq -r '[.. | objects | select(has("step")) | .step | select(type == "object") | .id // empty] | .[]' <<<"${wf_docs[$cur]}")
  done

  local wf_json step_json prior_json edges_json='[]'
  wf_json="$(__cog_workflow_map_json wf_docs)"
  step_json="$(__cog_workflow_map_json step_docs)"
  if ((${#prior[@]} > 0)); then
    prior_json="$(printf '%s\n' "${prior[@]}" | jq -sc '.')"
  else
    prior_json='[]'
  fi
  if ((${#edges[@]} > 0)); then
    edges_json="$(printf '%s\n' "${edges[@]}" \
      | jq -Rsc 'split("\n") | map(select(length > 0) | split("|") | {from: .[0], to: .[1]})')"
  fi

  jq -nc \
    --arg key "$key" \
    --argjson workflows "$wf_json" \
    --argjson steps "$step_json" \
    --argjson registry "$registry" \
    --argjson meta "$meta" \
    --argjson prior "$prior_json" \
    --argjson refedges "$edges_json" \
    --argjson depth "$max_depth_seen" \
    '{key: $key, workflows: $workflows, steps: $steps, meta: $meta, prior: $prior, depth: $depth,
      refedges: $refedges,
      registry_ids: (($registry["workflow-engines"] // []) | map(.id))}' \
    | jq -c "$__cog_workflow_validate_program"
}

cog::fn::workflow::validate_all() {
  local registry meta key
  local -a chunks=()

  registry="$(cog::fn::workflow::registry_json)"
  meta="$(cog::fn::workflow::load_meta)"
  chunks+=("$(cog::fn::workflow::validate_registry "$registry")")
  while IFS= read -r key; do
    [[ -n $key ]] || continue
    chunks+=("$(cog::fn::workflow::validate_key "$key" "$registry" "$meta")")
  done < <(cog::fn::workflow::list_keys workflows)

  printf '%s\n' "${chunks[@]}" | jq -sc 'add // []'
}

# Every workflow key visible across the layers, for `validate` with no key.
cog::fn::workflow::all_keys() {
  cog::fn::workflow::list_keys workflows
}
