# shellcheck shell=bash
: 'desc: Resolve, validate, and drive workflow runs.'

# Exit-code protocol for `cog workflow`, per docs/reference/cli-commands.md.
# It is protocol only and never workflow semantics:
#   0  valid result or applied transition, including the terminal states
#   1  internal failure reading or persisting state
#   2  InvalidInput: stale/missing token, illegal transition, digest mismatch,
#      or malformed output
#   75 cannot advance yet, matching `cog codex-runner finalize`
#
# cog::fn::error_raise maps InvalidInput to EX_DATAERR (65); this surface owes
# 2, so every error path goes through these two wrappers instead.
__cog_workflow_die_invalid() { cog::fn::error_raise_with_exit 2 "InvalidInput" "$@"; }
__cog_workflow_die_internal() { cog::fn::error_raise_with_exit 1 "InternalStateFailure" "$@"; }

# Manual runs: cog::fn::data_root prefers the installed XDG root whenever it
# exists, so a checkout's data/ and workflow/ are invisible to an installed cog
# until `just install`. Prefix manual checks with XDG_DATA_HOME="$(mktemp -d)".

__cog_workflow_list_self_check='(.schema=="cog.workflow.list.v1") and (.ok==true) and (.workflows|type=="array")'
__cog_workflow_show_self_check='(.schema=="cog.workflow.show.v1") and (.ok==true) and (.files|type=="array")'
__cog_workflow_init_self_check='(.schema=="cog.workflow.init.v1") and (.ok==true) and (.written|type=="array")'
__cog_workflow_validate_self_check='(.schema=="cog.workflow.validate.v1") and (.findings|type=="array") and (.checked|type=="array")'
__cog_workflow_resolve_self_check='(.schema=="cog.workflow.resolve.v1") and (.ok==true) and (.nodes|type=="array") and (.run_dir|type=="string")'
__cog_workflow_next_self_check='(.schema=="cog.workflow.next.v1") and (.state|type=="string") and (has("node"))'
__cog_workflow_claim_self_check='(.schema=="cog.workflow.claim.v1") and (.ok==true) and (.claim_token|type=="string")'
__cog_workflow_record_self_check='(.schema=="cog.workflow.record.v1") and (.ok==true) and (.receipt_path|type=="string")'
__cog_workflow_advance_self_check='(.schema=="cog.workflow.advance.v1") and (.outcome|type=="string")'
__cog_workflow_reclaim_self_check='(.schema=="cog.workflow.reclaim.v1") and (.ok==true) and (.claim_token|type=="string")'
__cog_workflow_summary_self_check='(.schema=="cog.workflow.summary.v1") and (.ok==true) and (.nodes|type=="array")'

# The receipt key set is closed to inputs, outputs, state, and dispatch identity:
# no token counts, no cost, no durations, no provider response metadata. The
# equality below is the mechanical guard; do not weaken it to has(...) checks.
__cog_workflow_receipt_self_check='(.schema=="cog.workflow.receipt.v1") and ((keys_unsorted|sort) == ["as","engine","error","final_message","final_message_truncated","inputs","outputs","owner","schema","status"])'

__cog_workflow_final_message_ceiling=2000

__cog_workflow_usage() {
  cog::fn::ui_data "Usage: cog workflow list [--json]"
  cog::fn::ui_data "Usage: cog workflow show <key> [--json]"
  cog::fn::ui_data "Usage: cog workflow init <key> --from <key> [--force]"
  cog::fn::ui_data "Usage: cog workflow validate [<key>|--all] [--json]"
  cog::fn::ui_data "Usage: cog workflow resolve --key <key> --run-dir <dir> --task-file <file> [--max-fresh-depth <n>] [--orchestrator <json>] --json"
  cog::fn::ui_data "Usage: cog workflow next    --run-dir <dir> --json"
  cog::fn::ui_data "Usage: cog workflow claim   --run-dir <dir> --as <instance> --owner <id> --json"
  cog::fn::ui_data "Usage: cog workflow record  --run-dir <dir> --as <instance> --claim-token <tok> --status done|failed [--reason <text>] --json"
  cog::fn::ui_data "Usage: cog workflow advance --run-dir <dir> --loop <handle> --decision-token <tok> --outcome continue|converged|pause|abort --reason criterion-met|stalled|unfeasible|needs-user [--note <text>] --json"
  cog::fn::ui_data "Usage: cog workflow reclaim --run-dir <dir> --as <instance> --previous-claim <tok> --owner <id> --reason <text> --json"
  cog::fn::ui_data "Usage: cog workflow summary --run-dir <dir> --json"
  cog::fn::ui_data "Usage: cog workflow conformance --run-dir <dir>"
  cog::fn::ui_data "Exit codes: 0 valid result or applied transition; 1 internal state failure; 2 InvalidInput; 75 cannot advance yet."
}

__cog_workflow_require_value() {
  [[ $2 -ge 2 && -n ${3:-} ]] || __cog_workflow_die_invalid \
    "missing value" "option: $1" "" "run 'cog workflow --help'"
}

__cog_workflow_require_run_dir() {
  [[ -n ${1:-} ]] || __cog_workflow_die_invalid \
    "missing run directory" "option: --run-dir" "" "run 'cog workflow --help'"
  [[ -d $1 ]] || __cog_workflow_die_invalid \
    "run directory not found" "path: $1" "" "run 'cog workflow resolve' first"
}

# --- read-only verbs -------------------------------------------------------

__cog_workflow_list() {
  local json="${COG_UI_JSON:-false}"

  while (($# > 0)); do
    case "$1" in
      --json)
        json=true
        shift
        ;;
      *) __cog_workflow_die_invalid "unexpected argument" "argument: $1" "" "run 'cog workflow --help'" ;;
    esac
  done

  local key source path rows='[]'
  while IFS= read -r key; do
    [[ -n $key ]] || continue
    source="$(cog::fn::workflow::resolve_source "$(cog::fn::workflow::workflow_rel "$key")")" || continue
    path="$(cog::fn::workflow::resolve_file "$(cog::fn::workflow::workflow_rel "$key")")" || continue
    rows="$(jq -c --arg k "$key" --arg s "$source" --arg p "$path" \
      '. + [{key: $k, source: $s, path: $p}]' <<<"$rows")"
  done < <(cog::fn::workflow::list_keys workflows)

  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_workflow_list_self_check" \
      "$(jq -c --argjson w "$rows" '{schema: "cog.workflow.list.v1", ok: true, action: "list", workflows: $w}' <<<'{}')"
  else
    jq -r '.[] | "\(.key)\t\(.source)"' <<<"$rows" | while IFS= read -r line; do
      cog::fn::ui_data "$line"
    done
  fi
}

# show resolves the workflow file and every step file it references, printing
# the resolved source per file. That is the observable proof that resolution is
# per file rather than per root: a project-layer workflow can reference an
# installed step, and the shadowing stays visible.
__cog_workflow_show() {
  local json="${COG_UI_JSON:-false}" key=""

  while (($# > 0)); do
    case "$1" in
      --json)
        json=true
        shift
        ;;
      --*) __cog_workflow_die_invalid "unknown option" "option: $1" "" "run 'cog workflow --help'" ;;
      *)
        [[ -z $key ]] || __cog_workflow_die_invalid "too many arguments" "argument: $1" "" ""
        key="$1"
        shift
        ;;
    esac
  done

  [[ -n $key ]] || __cog_workflow_die_invalid "missing workflow key" "usage: cog workflow show <key>" "" ""
  cog::fn::workflow::valid_key "$key" || __cog_workflow_die_invalid \
    "invalid workflow key" "key: ${key}" "expected [a-z0-9][a-z0-9-]*" ""

  local rel path source doc files='[]'
  rel="$(cog::fn::workflow::workflow_rel "$key")"
  path="$(cog::fn::workflow::resolve_file "$rel")" || __cog_workflow_die_invalid \
    "workflow not found in any layer" "key: ${key}" "" "run 'cog workflow list'"
  source="$(cog::fn::workflow::resolve_source "$rel")"
  doc="$(cog::fn::workflow::load_yaml "$path")" || __cog_workflow_die_invalid \
    "workflow definition does not parse" "path: ${path}" "" ""
  files="$(jq -c --arg id "$key" --arg s "$source" --arg p "$path" \
    '. + [{role: "workflow", id: $id, source: $s, path: $p}]' <<<"$files")"

  local sid srel spath ssource
  while IFS= read -r sid; do
    [[ -n $sid ]] || continue
    srel="$(cog::fn::workflow::step_rel "$sid")"
    if spath="$(cog::fn::workflow::resolve_file "$srel")"; then
      ssource="$(cog::fn::workflow::resolve_source "$srel")"
    else
      spath=""
      ssource="unresolved"
    fi
    files="$(jq -c --arg id "$sid" --arg s "$ssource" --arg p "$spath" \
      '. + [{role: "step", id: $id, source: $s, path: (if $p == "" then null else $p end)}]' <<<"$files")"
  done < <(jq -r '[.. | objects | select(has("step")) | .step | select(type == "object") | .id // empty] | unique | .[]' <<<"$doc")

  local body
  body="$(jq -nc --arg key "$key" --argjson files "$files" --argjson def "$doc" \
    --argjson meta "$(cog::fn::workflow::load_meta)" \
    '{schema: "cog.workflow.show.v1", ok: true, action: "show", key: $key, files: $files, meta: $meta, definition: $def}')"

  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_workflow_show_self_check" "$body"
  else
    jq -r '.files[] | "\(.role)\t\(.id)\t\(.source)"' <<<"$body" | while IFS= read -r line; do
      cog::fn::ui_data "$line"
    done
  fi
}

__cog_workflow_init() {
  local json="${COG_UI_JSON:-false}" key="" from="" force=false

  while (($# > 0)); do
    case "$1" in
      --from)
        __cog_workflow_require_value "--from" "$#" "${2:-}"
        from="$2"
        shift 2
        ;;
      --force)
        force=true
        shift
        ;;
      --json)
        json=true
        shift
        ;;
      --*) __cog_workflow_die_invalid "unknown option" "option: $1" "" "run 'cog workflow --help'" ;;
      *)
        [[ -z $key ]] || __cog_workflow_die_invalid "too many arguments" "argument: $1" "" ""
        key="$1"
        shift
        ;;
    esac
  done

  [[ -n $key ]] || __cog_workflow_die_invalid "missing workflow key" "usage: cog workflow init <key> --from <key>" "" ""
  [[ -n $from ]] || __cog_workflow_die_invalid "missing source key" "option: --from" "" ""
  cog::fn::workflow::valid_key "$key" || __cog_workflow_die_invalid "invalid workflow key" "key: ${key}" "" ""
  cog::fn::workflow::valid_key "$from" || __cog_workflow_die_invalid "invalid source key" "key: ${from}" "" ""

  local root src doc written='[]'
  root="$(cog::fn::workflow::project_root)"
  src="$(cog::fn::workflow::resolve_file "$(cog::fn::workflow::workflow_rel "$from")")" \
    || __cog_workflow_die_invalid "source workflow not found" "key: ${from}" "" "run 'cog workflow list'"
  doc="$(cog::fn::workflow::load_yaml "$src")" || __cog_workflow_die_invalid \
    "source workflow does not parse" "path: ${src}" "" ""

  local dest="${root}/workflows/${key}.yaml"
  if [[ -e $dest && $force != true ]]; then
    __cog_workflow_die_invalid "project-layer workflow already exists" "path: ${dest}" \
      "" "pass --force to overwrite"
  fi
  mkdir -p "${root}/workflows" "${root}/steps" "${root}/skills" 2>/dev/null \
    || __cog_workflow_die_internal "could not create project workspace" "path: ${root}" "" ""
  # On a --force re-init the source may already resolve to the destination,
  # because the first init put it in the project layer. Redirecting into the
  # file being read would truncate it before yq saw a byte.
  [[ ! $src -ef $dest ]] || __cog_workflow_die_invalid \
    "source and destination are the same file" "path: ${dest}" \
    "the source already resolves to the project layer" "pass a different key"
  # Rewrite the id so the copy names itself, then carry the rest verbatim.
  yq e -o=yaml ".id = \"${key}\"" "$src" >"$dest" 2>/dev/null \
    || __cog_workflow_die_internal "could not write workflow" "path: ${dest}" "" ""
  written="$(jq -c --arg p "$dest" '. + [$p]' <<<"$written")"

  local sid srel spath sdest skill skpath skdest
  while IFS= read -r sid; do
    [[ -n $sid ]] || continue
    srel="$(cog::fn::workflow::step_rel "$sid")"
    spath="$(cog::fn::workflow::resolve_file "$srel")" || continue
    sdest="${root}/${srel}"
    # Already the project-layer file: nothing to copy, and cp would refuse.
    if [[ ! -e $sdest || ($force == true && ! $spath -ef $sdest) ]]; then
      cp -f -- "$spath" "$sdest" 2>/dev/null \
        || __cog_workflow_die_internal "could not copy step" "path: ${sdest}" "" ""
      written="$(jq -c --arg p "$sdest" '. + [$p]' <<<"$written")"
    fi
    skill="$(yq e -o=json '.skill // ""' "$spath" 2>/dev/null | jq -r '.')"
    [[ -n $skill && $skill != "null" ]] || continue
    skpath="$(cog::fn::workflow::resolve_file "$(cog::fn::workflow::skill_rel "$skill")")" || continue
    skdest="${root}/$(cog::fn::workflow::skill_rel "$skill")"
    if [[ ! -e $skdest || ($force == true && ! $skpath -ef $skdest) ]]; then
      cp -f -- "$skpath" "$skdest" 2>/dev/null \
        || __cog_workflow_die_internal "could not copy skill" "path: ${skdest}" "" ""
      written="$(jq -c --arg p "$skdest" '. + [$p]' <<<"$written")"
    fi
  done < <(jq -r '[.. | objects | select(has("step")) | .step | select(type == "object") | .id // empty] | unique | .[]' <<<"$doc")

  local body
  body="$(jq -nc --arg key "$key" --arg from "$from" --argjson written "$written" \
    '{schema: "cog.workflow.init.v1", ok: true, action: "init", key: $key, from: $from, written: $written}')"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_workflow_init_self_check" "$body"
  else
    jq -r '.written[]' <<<"$body" | while IFS= read -r line; do
      cog::fn::ui_data "WROTE ${line}"
    done
  fi
}

__cog_workflow_validate() {
  local json="${COG_UI_JSON:-false}" key="" all=false

  while (($# > 0)); do
    case "$1" in
      --all)
        all=true
        shift
        ;;
      --json)
        json=true
        shift
        ;;
      --*) __cog_workflow_die_invalid "unknown option" "option: $1" "" "run 'cog workflow --help'" ;;
      *)
        [[ -z $key ]] || __cog_workflow_die_invalid "too many arguments" "argument: $1" "" ""
        key="$1"
        shift
        ;;
    esac
  done

  [[ -z $key || $all != true ]] || __cog_workflow_die_invalid \
    "--all takes no key" "argument: ${key}" "" "run 'cog workflow validate' with no argument"

  local findings checked
  if [[ -n $key ]]; then
    findings="$(cog::fn::workflow::validate_key "$key")"
    findings="$(jq -c --argjson r "$(cog::fn::workflow::validate_registry)" '$r + .' <<<"$findings")"
    checked="$(jq -nc --arg k "$key" '[$k]')"
  else
    findings="$(cog::fn::workflow::validate_all)"
    checked="$(cog::fn::workflow::all_keys | jq -Rsc 'split("\n") | map(select(length > 0))')"
  fi

  local ok body
  ok=true
  [[ $(jq -r 'length' <<<"$findings") == 0 ]] || ok=false
  body="$(jq -nc --argjson ok "$ok" --argjson checked "$checked" --argjson findings "$findings" \
    '{schema: "cog.workflow.validate.v1", ok: $ok, action: "validate", checked: $checked, findings: $findings}')"

  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_workflow_validate_self_check" "$body"
  else
    jq -r '.findings[] | "FAIL\t\(.rule)\t\(.where)\t\(.message)"' <<<"$body" | while IFS= read -r line; do
      cog::fn::ui_data "$line"
    done
    [[ $ok != true ]] || cog::fn::ui_data "PASS validate"
  fi

  [[ $ok == true ]] || return 2
}

# --- run lifecycle ---------------------------------------------------------

# resolve validates first, then materializes. Validation runs once at load,
# before any agent is spawned and before any node directory exists, so an
# invalid definition leaves nothing behind.
__cog_workflow_resolve() {
  local json="${COG_UI_JSON:-false}"
  local key="" run_dir="" task_file="" max_fresh_depth="null" orchestrator="null"

  while (($# > 0)); do
    case "$1" in
      --key)
        __cog_workflow_require_value "--key" "$#" "${2:-}"
        key="$2"
        shift 2
        ;;
      --run-dir)
        __cog_workflow_require_value "--run-dir" "$#" "${2:-}"
        run_dir="$2"
        shift 2
        ;;
      --task-file)
        __cog_workflow_require_value "--task-file" "$#" "${2:-}"
        task_file="$2"
        shift 2
        ;;
      --max-fresh-depth)
        __cog_workflow_require_value "--max-fresh-depth" "$#" "${2:-}"
        [[ $2 =~ ^[0-9]+$ ]] || __cog_workflow_die_invalid \
          "max fresh depth is not a non-negative integer" "value: $2" "" ""
        max_fresh_depth="$2"
        shift 2
        ;;
      --orchestrator)
        __cog_workflow_require_value "--orchestrator" "$#" "${2:-}"
        jq -e 'type == "object"' <<<"$2" >/dev/null 2>&1 || __cog_workflow_die_invalid \
          "orchestrator is not a JSON object" "option: --orchestrator" "" ""
        orchestrator="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      *) __cog_workflow_die_invalid "unknown option" "option: $1" "" "run 'cog workflow --help'" ;;
    esac
  done

  [[ -n $key ]] || __cog_workflow_die_invalid "missing workflow key" "option: --key" "" ""
  [[ -n $run_dir ]] || __cog_workflow_die_invalid "missing run directory" "option: --run-dir" "" ""
  [[ -n $task_file ]] || __cog_workflow_die_invalid "missing task file" "option: --task-file" "" ""
  [[ -f $task_file && -s $task_file ]] || __cog_workflow_die_invalid \
    "task file is missing or empty" "path: ${task_file}" "" ""
  cog::fn::workflow::valid_key "$key" || __cog_workflow_die_invalid "invalid workflow key" "key: ${key}" "" ""

  local registry findings
  registry="$(cog::fn::workflow::registry_json)"
  findings="$(cog::fn::workflow::validate_key "$key" "$registry")"
  findings="$(jq -c --argjson r "$(cog::fn::workflow::validate_registry "$registry")" '$r + .' <<<"$findings")"
  if [[ $(jq -r 'length' <<<"$findings") != 0 ]]; then
    cog::fn::ui_data "$(jq -nc --argjson f "$findings" \
      '{schema: "cog.workflow.validate.v1", ok: false, action: "resolve", checked: [], findings: $f}')"
    return 2
  fi

  local path doc
  path="$(cog::fn::workflow::resolve_file "$(cog::fn::workflow::workflow_rel "$key")")" \
    || __cog_workflow_die_invalid "workflow not found in any layer" "key: ${key}" "" ""
  doc="$(cog::fn::workflow::load_yaml "$path")"

  # Slice 003 supports only the one accepted linear path. A workflow: or loop:
  # entry is refused here rather than half-materialized; composites and loop
  # rounds arrive with slice 004.
  local unsupported
  unsupported="$(jq -r '[(.steps // [])[] | select(type == "object") | select((has("workflow")) or (has("loop")))] | length' <<<"$doc")"
  if [[ $unsupported != 0 ]]; then
    cog::fn::ui_data "$(jq -nc --arg k "$key" \
      '{schema: "cog.workflow.validate.v1", ok: false, action: "resolve", checked: [$k],
        findings: [{rule: "unsupported-node-kind", severity: "error",
                    where: ("workflows/" + $k + ".yaml"),
                    message: "workflow: and loop: nodes are not materialized in this release; the linear vertical accepts only step: entries"}]}')"
    return 2
  fi

  # Assemble the step-definition map so engines resolve without re-reading.
  local steps_json='{}' sid sdoc spath
  while IFS= read -r sid; do
    [[ -n $sid ]] || continue
    spath="$(cog::fn::workflow::resolve_file "$(cog::fn::workflow::step_rel "$sid")")" \
      || __cog_workflow_die_invalid "step definition not found" "id: ${sid}" "" ""
    sdoc="$(cog::fn::workflow::load_yaml "$spath")"
    steps_json="$(jq -c --arg k "$sid" --argjson v "$sdoc" '. + {($k): $v}' <<<"$steps_json")"
  done < <(jq -r '[(.steps // [])[] | select(type == "object" and has("step")) | .step.id // empty] | unique | .[]' <<<"$doc")

  local nodes
  nodes="$(jq -nc --argjson doc "$doc" --argjson steps "$steps_json" --argjson registry "$registry" '
    ($registry["workflow-engines"] // []) as $engines
    | [ ($doc.steps // [])[] | select(type == "object" and has("step")) | .step as $s
        | ($steps[$s.id] // {}) as $def
        | (($s.engine // $def.engine) | tostring) as $eid
        | ($engines | map(select(.id == $eid)) | first) as $rec
        | {as: ($s.as // $s.id), id: $s.id, kind: "step",
            needs: ($s.needs // []),
            engine: $rec,
            skill: ($def.skill // null),
            dir: ($s.as // $s.id),
            status: "pending", claim_token: null, owner: null, reclaims: []} ]')"

  mkdir -p "$run_dir" 2>/dev/null || __cog_workflow_die_internal \
    "could not create run directory" "path: ${run_dir}" "" ""
  local as
  while IFS= read -r as; do
    [[ -n $as ]] || continue
    # Defence in depth behind the safe-instance-name validator rule: nothing
    # this loop creates may land outside the run directory.
    cog::fn::workflow::valid_instance "$as" || __cog_workflow_die_invalid \
      "unsafe instance name" "as: ${as}" \
      "as: must be a single safe path segment" ""
    mkdir -p "$(cog::fn::workflow::node_dir "$run_dir" "$as")" 2>/dev/null \
      || __cog_workflow_die_internal "could not create node directory" "as: ${as}" "" ""
  done < <(jq -r '.[].as' <<<"$nodes")

  local abs_run abs_task state
  abs_run="$(cd -P "$run_dir" && pwd)"
  abs_task="$(cd -P "$(dirname "$task_file")" && pwd)/$(basename "$task_file")"
  state="$(jq -nc \
    --arg key "$key" --arg run "$abs_run" --arg task "$abs_task" \
    --argjson nodes "$nodes" --argjson meta "$(cog::fn::workflow::load_meta)" \
    --argjson depth "$max_fresh_depth" --argjson orch "$orchestrator" '
    {schema: "cog.workflow.state.v1", key: $key, run_dir: $run, task_file: $task,
      state: "running", max_fresh_depth: $depth, orchestrator: $orch,
      meta: $meta, nodes: $nodes}')"
  cog::fn::workflow::state_write "$run_dir" "$state"

  local body
  body="$(jq -nc --arg run "$abs_run" --arg key "$key" --argjson nodes "$nodes" '
    {schema: "cog.workflow.resolve.v1", ok: true, action: "resolve", run_dir: $run, key: $key,
      state: "running",
      nodes: [$nodes[] | {as, id, dir, needs, engine: (.engine.id // null)}]}')"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_workflow_resolve_self_check" "$body"
  else
    jq -r '.nodes[] | "\(.as)\t\(.id)\t\(.engine)"' <<<"$body" | while IFS= read -r line; do
      cog::fn::ui_data "$line"
    done
  fi
}

# next returns at most one ready node. Not a ready set: that keeps the linear
# vertical linear, and is the rabbit-hole escape against a general scheduler.
__cog_workflow_next() {
  local json="${COG_UI_JSON:-false}" run_dir=""

  while (($# > 0)); do
    case "$1" in
      --run-dir)
        __cog_workflow_require_value "--run-dir" "$#" "${2:-}"
        run_dir="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      *) __cog_workflow_die_invalid "unknown option" "option: $1" "" "run 'cog workflow --help'" ;;
    esac
  done
  __cog_workflow_require_run_dir "$run_dir"

  local state ready run_state body
  state="$(cog::fn::workflow::state_read "$run_dir")"
  ready="$(jq -r '
    .nodes as $n
    | ($n | map(select(.status == "done") | .as)) as $done
    | [ $n[] | select(.status == "pending")
        | select((.needs // []) | all(. as $t | ($done | index($t)) != null)) ]
    | (first // {}) | .as // empty' <<<"$state")"

  if [[ -n $ready ]]; then
    body="$(jq -nc --argjson s "$state" --arg as "$ready" '
      ($s.nodes | map(select(.as == $as)) | first) as $node
      | {schema: "cog.workflow.next.v1", ok: true, action: "next", state: "running",
          node: {as: $node.as, id: $node.id, dir: $node.dir,
                engine: $node.engine, skill: $node.skill,
                inputs: (($node.needs // []) | map(. + "/"))}}')"
    if [[ $json == true ]]; then
      cog::fn::json_emit "$__cog_workflow_next_self_check" "$body"
    else
      cog::fn::ui_data "$ready"
    fi
    return 0
  fi

  # One owner for the run-state rule: a second copy here drifted from
  # recompute_state and reported running for a run that a failed upstream had
  # already made terminal.
  run_state="$(cog::fn::workflow::recompute_state "$state" | jq -r '.state')"

  if [[ $run_state == running ]]; then
    # A node is claimed and its owner has not recorded yet: the caller simply
    # polls again. 75 matches `cog codex-runner finalize`.
    body="$(jq -nc '{schema: "cog.workflow.next.v1", ok: false, action: "next", state: "running",
                      node: null, reason: "no node is ready yet; a claimed node blocks the frontier"}')"
    [[ $json != true ]] || cog::fn::json_emit "$__cog_workflow_next_self_check" "$body"
    return "$EX_TEMPFAIL"
  fi

  body="$(jq -nc --arg st "$run_state" \
    '{schema: "cog.workflow.next.v1", ok: true, action: "next", state: $st, node: null}')"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_workflow_next_self_check" "$body"
  else
    cog::fn::ui_data "$run_state"
  fi
}

__cog_workflow_claim() {
  local json="${COG_UI_JSON:-false}" run_dir="" as="" owner=""

  while (($# > 0)); do
    case "$1" in
      --run-dir)
        __cog_workflow_require_value "--run-dir" "$#" "${2:-}"
        run_dir="$2"
        shift 2
        ;;
      --as)
        __cog_workflow_require_value "--as" "$#" "${2:-}"
        as="$2"
        shift 2
        ;;
      --owner)
        __cog_workflow_require_value "--owner" "$#" "${2:-}"
        owner="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      *) __cog_workflow_die_invalid "unknown option" "option: $1" "" "run 'cog workflow --help'" ;;
    esac
  done
  __cog_workflow_require_run_dir "$run_dir"
  [[ -n $as ]] || __cog_workflow_die_invalid "missing instance" "option: --as" "" ""
  [[ -n $owner ]] || __cog_workflow_die_invalid "missing owner" "option: --owner" "" ""

  local state node status
  state="$(cog::fn::workflow::state_read "$run_dir")"
  node="$(cog::fn::workflow::node_json "$state" "$as")"
  [[ -n $node ]] || __cog_workflow_die_invalid "unknown instance" "as: ${as}" "" "run 'cog workflow summary'"
  status="$(jq -r '.status' <<<"$node")"

  case "$status" in
    pending) ;;
    claimed) __cog_workflow_die_invalid "node is already claimed" "as: ${as}" \
      "an owner holds this node" "use 'cog workflow reclaim'" ;;
    *) __cog_workflow_die_invalid "illegal transition" "as: ${as}" \
      "node is already ${status}" "" ;;
  esac
  cog::fn::workflow::node_ready "$state" "$as" || __cog_workflow_die_invalid \
    "illegal transition" "as: ${as}" "a needs: target is not done" ""

  local token next
  token="$(cog::fn::workflow::new_token)"
  next="$(jq -c --arg as "$as" --arg tok "$token" --arg owner "$owner" '
    .nodes |= map(if .as == $as then .status = "claimed" | .claim_token = $tok | .owner = $owner else . end)' <<<"$state")"
  cog::fn::workflow::state_write "$run_dir" "$next"

  local body
  body="$(jq -nc --arg as "$as" --arg owner "$owner" --arg tok "$token" \
    --argjson node "$node" --argjson inputs "$(cog::fn::workflow::node_inputs "$state" "$as")" '
    {schema: "cog.workflow.claim.v1", ok: true, action: "claim", as: $as, owner: $owner,
      claim_token: $tok, dir: $node.dir, inputs: $inputs}')"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_workflow_claim_self_check" "$body"
  else
    cog::fn::ui_data "$token"
  fi
}

# record is one call: verify the token, inventory the node directory, truncate
# the captured final message, write <as>/outputs.json, update state.json.
# The receipt lists what the directory holds rather than verifying it against a
# declaration — cog counts files and never reads them.
__cog_workflow_record() {
  local json="${COG_UI_JSON:-false}" run_dir="" as="" claim_token="" status="" reason=""

  while (($# > 0)); do
    case "$1" in
      --run-dir)
        __cog_workflow_require_value "--run-dir" "$#" "${2:-}"
        run_dir="$2"
        shift 2
        ;;
      --as)
        __cog_workflow_require_value "--as" "$#" "${2:-}"
        as="$2"
        shift 2
        ;;
      --claim-token)
        __cog_workflow_require_value "--claim-token" "$#" "${2:-}"
        claim_token="$2"
        shift 2
        ;;
      --status)
        __cog_workflow_require_value "--status" "$#" "${2:-}"
        status="$2"
        shift 2
        ;;
      --reason)
        __cog_workflow_require_value "--reason" "$#" "${2:-}"
        reason="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      *) __cog_workflow_die_invalid "unknown option" "option: $1" "" "run 'cog workflow --help'" ;;
    esac
  done
  __cog_workflow_require_run_dir "$run_dir"
  [[ -n $as ]] || __cog_workflow_die_invalid "missing instance" "option: --as" "" ""
  [[ -n $claim_token ]] || __cog_workflow_die_invalid "missing claim token" "option: --claim-token" "" ""
  case "$status" in
    done | failed) ;;
    *) __cog_workflow_die_invalid "invalid status" "value: ${status}" "expected done or failed" "" ;;
  esac

  local state node live
  state="$(cog::fn::workflow::state_read "$run_dir")"
  node="$(cog::fn::workflow::node_json "$state" "$as")"
  [[ -n $node ]] || __cog_workflow_die_invalid "unknown instance" "as: ${as}" "" ""
  live="$(jq -r '.claim_token // ""' <<<"$node")"
  [[ -n $live ]] || __cog_workflow_die_invalid "node is not claimed" "as: ${as}" "" "run 'cog workflow claim' first"
  [[ $live == "$claim_token" ]] || __cog_workflow_die_invalid \
    "stale or missing claim token" "as: ${as}" "the token does not match the live claim" "re-claim the node"

  # The receipt sees the node directory only; it never walks above it.
  local dir outputs final="" truncated=false
  dir="$(cog::fn::workflow::node_dir "$run_dir" "$(jq -r '.dir' <<<"$node")")"
  outputs="$(cog::fn::workflow::inventory "$dir")"
  if [[ -f "${dir}/final-message.txt" ]]; then
    final="$(head -c "$__cog_workflow_final_message_ceiling" "${dir}/final-message.txt")"
    [[ $(wc -c <"${dir}/final-message.txt") -le $__cog_workflow_final_message_ceiling ]] || truncated=true
  fi

  local error_json='null'
  if [[ $status == failed ]]; then
    error_json="$(jq -nc --arg r "${reason:-unspecified}" '{reason: $r}')"
  fi

  local receipt receipt_path
  receipt="$(jq -nc --arg as "$as" --arg st "$status" --arg fm "$final" \
    --argjson tr "$truncated" --argjson outputs "$outputs" --argjson node "$node" \
    --argjson inputs "$(cog::fn::workflow::node_inputs "$state" "$as")" \
    --argjson err "$error_json" '
    {schema: "cog.workflow.receipt.v1", as: $as, status: $st, inputs: $inputs, outputs: $outputs,
      final_message: $fm, final_message_truncated: $tr, engine: $node.engine,
      owner: $node.owner, error: $err}')"
  jq -e "$__cog_workflow_receipt_self_check" <<<"$receipt" >/dev/null 2>&1 \
    || __cog_workflow_die_internal "receipt failed its closed-key-set self-check" "as: ${as}" "" "report this cog bug"

  receipt_path="${dir}/outputs.json"
  printf '%s\n' "$receipt" >"$receipt_path" 2>/dev/null \
    || __cog_workflow_die_internal "could not write receipt" "path: ${receipt_path}" "" ""

  local next run_state body
  next="$(jq -c --arg as "$as" --arg st "$status" '
    .nodes |= map(if .as == $as then .status = $st | .claim_token = null else . end)' <<<"$state")"
  next="$(cog::fn::workflow::recompute_state "$next")"
  cog::fn::workflow::state_write "$run_dir" "$next"
  run_state="$(jq -r '.state' <<<"$next")"

  body="$(jq -nc --arg as "$as" --arg st "$status" --arg rp "$receipt_path" \
    --argjson n "$(jq -r 'length' <<<"$outputs")" --arg rs "$run_state" '
    {schema: "cog.workflow.record.v1", ok: true, action: "record", as: $as, status: $st,
      receipt_path: $rp, outputs_count: $n, run_state: $rs}')"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_workflow_record_self_check" "$body"
  else
    cog::fn::ui_data "$receipt_path"
  fi
}

__cog_workflow_reclaim() {
  local json="${COG_UI_JSON:-false}" run_dir="" as="" previous="" owner="" reason=""

  while (($# > 0)); do
    case "$1" in
      --run-dir)
        __cog_workflow_require_value "--run-dir" "$#" "${2:-}"
        run_dir="$2"
        shift 2
        ;;
      --as)
        __cog_workflow_require_value "--as" "$#" "${2:-}"
        as="$2"
        shift 2
        ;;
      --previous-claim)
        __cog_workflow_require_value "--previous-claim" "$#" "${2:-}"
        previous="$2"
        shift 2
        ;;
      --owner)
        __cog_workflow_require_value "--owner" "$#" "${2:-}"
        owner="$2"
        shift 2
        ;;
      --reason)
        __cog_workflow_require_value "--reason" "$#" "${2:-}"
        reason="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      *) __cog_workflow_die_invalid "unknown option" "option: $1" "" "run 'cog workflow --help'" ;;
    esac
  done
  __cog_workflow_require_run_dir "$run_dir"
  [[ -n $as ]] || __cog_workflow_die_invalid "missing instance" "option: --as" "" ""
  [[ -n $previous ]] || __cog_workflow_die_invalid "missing previous claim" "option: --previous-claim" "" ""
  [[ -n $owner ]] || __cog_workflow_die_invalid "missing owner" "option: --owner" "" ""
  [[ -n $reason ]] || __cog_workflow_die_invalid "missing reason" "option: --reason" "" ""

  local state node status live
  state="$(cog::fn::workflow::state_read "$run_dir")"
  node="$(cog::fn::workflow::node_json "$state" "$as")"
  [[ -n $node ]] || __cog_workflow_die_invalid "unknown instance" "as: ${as}" "" ""
  status="$(jq -r '.status' <<<"$node")"
  [[ $status == claimed ]] || __cog_workflow_die_invalid \
    "illegal transition" "as: ${as}" "node is ${status}, not claimed" ""
  live="$(jq -r '.claim_token // ""' <<<"$node")"
  [[ $live == "$previous" ]] || __cog_workflow_die_invalid \
    "stale or missing claim token" "as: ${as}" "the previous claim does not match" ""

  local token next body
  token="$(cog::fn::workflow::new_token)"
  next="$(jq -c --arg as "$as" --arg tok "$token" --arg owner "$owner" --arg reason "$reason" '
    .nodes |= map(if .as == $as
      then .claim_token = $tok | .owner = $owner | .reclaims = ((.reclaims // []) + [$reason])
      else . end)' <<<"$state")"
  cog::fn::workflow::state_write "$run_dir" "$next"

  body="$(jq -nc --arg as "$as" --arg owner "$owner" --arg tok "$token" --arg reason "$reason" '
    {schema: "cog.workflow.reclaim.v1", ok: true, action: "reclaim", as: $as, owner: $owner,
      claim_token: $tok, reason: $reason}')"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_workflow_reclaim_self_check" "$body"
  else
    cog::fn::ui_data "$token"
  fi
}

# advance carries the full loop transition protocol. until: is a prose criterion
# cog stores and never parses: this verb reads the orchestrator's reported
# outcome and reason, and never evaluates the criterion itself.
__cog_workflow_advance() {
  local json="${COG_UI_JSON:-false}" run_dir="" handle="" token="" outcome="" reason="" note=""

  while (($# > 0)); do
    case "$1" in
      --run-dir)
        __cog_workflow_require_value "--run-dir" "$#" "${2:-}"
        run_dir="$2"
        shift 2
        ;;
      --loop)
        __cog_workflow_require_value "--loop" "$#" "${2:-}"
        handle="$2"
        shift 2
        ;;
      --decision-token)
        __cog_workflow_require_value "--decision-token" "$#" "${2:-}"
        token="$2"
        shift 2
        ;;
      --outcome)
        __cog_workflow_require_value "--outcome" "$#" "${2:-}"
        outcome="$2"
        shift 2
        ;;
      --reason)
        __cog_workflow_require_value "--reason" "$#" "${2:-}"
        reason="$2"
        shift 2
        ;;
      --note)
        __cog_workflow_require_value "--note" "$#" "${2:-}"
        note="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      *) __cog_workflow_die_invalid "unknown option" "option: $1" "" "run 'cog workflow --help'" ;;
    esac
  done
  __cog_workflow_require_run_dir "$run_dir"
  [[ -n $handle ]] || __cog_workflow_die_invalid "missing loop handle" "option: --loop" "" ""
  [[ -n $token ]] || __cog_workflow_die_invalid "missing decision token" "option: --decision-token" "" ""
  case "$outcome" in
    continue | converged | pause | abort) ;;
    *) __cog_workflow_die_invalid "invalid outcome" "value: ${outcome}" \
      "expected continue, converged, pause, or abort" "" ;;
  esac
  case "$reason" in
    criterion-met | stalled | unfeasible | needs-user) ;;
    *) __cog_workflow_die_invalid "invalid reason" "value: ${reason}" \
      "expected criterion-met, stalled, unfeasible, or needs-user" "" ;;
  esac

  local state node
  state="$(cog::fn::workflow::state_read "$run_dir")"
  node="$(jq -c --arg h "$handle" '.nodes | map(select(.as == $h and .kind == "loop")) | first // empty' <<<"$state")"
  # A resolved run in this release carries no loop nodes, so this fails closed
  # on every handle. That is correct behaviour, not a stub: the transition rules
  # below are the contract slice 004 inherits.
  [[ -n $node ]] || __cog_workflow_die_invalid \
    "unknown loop handle" "loop: ${handle}" "no loop node carries this handle" ""

  local live rounds max_rounds produced
  live="$(jq -r '.decision_token // ""' <<<"$node")"
  [[ $live == "$token" ]] || __cog_workflow_die_invalid \
    "stale or missing decision token" "loop: ${handle}" "" ""
  rounds="$(jq -r '.round // 0' <<<"$node")"
  max_rounds="$(jq -r '.max_rounds // 0' <<<"$node")"
  produced="$(jq -r '.round_produced_files // 0' <<<"$node")"

  case "$outcome" in
    pause | abort)
      # Always applicable transitions.
      ;;
    continue | converged)
      # A round that produced no files refuses to continue or converge.
      [[ $produced -gt 0 ]] || __cog_workflow_die_invalid \
        "illegal transition" "loop: ${handle}" \
        "the round produced no files, so it can neither continue nor converge" ""
      if [[ $outcome == continue ]]; then
        # max_rounds is a hard ceiling enforced before a round is materialized,
        # and reaching it is a failure rather than a success.
        [[ $((rounds + 1)) -le $max_rounds ]] || __cog_workflow_die_invalid \
          "illegal transition" "loop: ${handle}" \
          "advancing would exceed max_rounds ${max_rounds}" ""
      fi
      ;;
  esac

  local body run_state next
  if [[ $outcome == continue ]]; then
    # cog materializes round N+1 only on this call, one round at a time. This
    # release has no materializer, so 75 is the honest signal and slice 004
    # replaces it with a materialized round. Nothing is persisted and the
    # decision token stays live, because the transition was not applied.
    body="$(jq -nc --arg h "$handle" --arg o "$outcome" --arg r "$reason" --arg n "$note" \
      --argjson round "$rounds" '
      {schema: "cog.workflow.advance.v1", ok: true, action: "advance", loop: $h, outcome: $o,
        reason: $r, note: (if $n == "" then null else $n end), round: $round, state: "running"}')"
    [[ $json != true ]] || cog::fn::json_emit "$__cog_workflow_advance_self_check" "$body"
    return "$EX_TEMPFAIL"
  fi

  # An applied transition is durable, and its decision token is spent: exit 0
  # reports the transition, so replaying the same token must not be accepted a
  # second time.
  next="$(jq -c --arg h "$handle" --arg o "$outcome" --arg r "$reason" --arg n "$note" '
    .nodes |= map(if .as == $h and .kind == "loop"
      then .decision_token = null | .last_outcome = $o | .last_reason = $r
            | .last_note = (if $n == "" then null else $n end)
            | (if $o == "converged" then .status = "done"
              elif $o == "abort" then .status = "failed"
              else . end)
      else . end)' <<<"$state")"
  if [[ $outcome == pause ]]; then
    # paused is a run state recompute_state has no rule for: it is a report
    # from the orchestrator, not a function of the node statuses.
    next="$(jq -c '.state = "paused"' <<<"$next")"
  else
    next="$(cog::fn::workflow::recompute_state "$next")"
  fi
  cog::fn::workflow::state_write "$run_dir" "$next"
  run_state="$(jq -r '.state' <<<"$next")"

  body="$(jq -nc --arg h "$handle" --arg o "$outcome" --arg r "$reason" --arg n "$note" \
    --argjson round "$rounds" --arg st "$run_state" '
    {schema: "cog.workflow.advance.v1", ok: true, action: "advance", loop: $h, outcome: $o,
      reason: $r, note: (if $n == "" then null else $n end), round: $round, state: $st}')"

  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_workflow_advance_self_check" "$body"
  else
    cog::fn::ui_data "$run_state"
  fi
}

__cog_workflow_summary() {
  local json="${COG_UI_JSON:-false}" run_dir=""

  while (($# > 0)); do
    case "$1" in
      --run-dir)
        __cog_workflow_require_value "--run-dir" "$#" "${2:-}"
        run_dir="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      *) __cog_workflow_die_invalid "unknown option" "option: $1" "" "run 'cog workflow --help'" ;;
    esac
  done
  __cog_workflow_require_run_dir "$run_dir"

  local state rows='[]' as dir count
  state="$(cog::fn::workflow::state_read "$run_dir")"
  while IFS= read -r as; do
    [[ -n $as ]] || continue
    dir="$(cog::fn::workflow::node_dir "$run_dir" "$as")"
    if [[ -f "${dir}/outputs.json" ]]; then
      count="$(jq -r '.outputs | length' "${dir}/outputs.json" 2>/dev/null || printf '0')"
    else
      count=0
    fi
    rows="$(jq -c --argjson s "$state" --arg as "$as" --argjson n "$count" '
      ($s.nodes | map(select(.as == $as)) | first) as $node
      | . + [{as: $as, status: $node.status, outputs_count: $n, engine: ($node.engine.id // null)}]' <<<"$rows")"
  done < <(jq -r '.nodes[].as' <<<"$state")

  local body
  body="$(jq -nc --argjson s "$state" --argjson rows "$rows" '
    {schema: "cog.workflow.summary.v1", ok: true, action: "summary", run_dir: $s.run_dir,
      key: $s.key, state: $s.state, nodes: $rows}')"
  # summary reports; it never gates.
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_workflow_summary_self_check" "$body"
  else
    cog::fn::ui_data "$(jq -r '.state' <<<"$body")"
    jq -r '.nodes[] | "\(.as)\t\(.status)\t\(.outputs_count)"' <<<"$body" | while IFS= read -r line; do
      cog::fn::ui_data "$line"
    done
  fi
}

# conformance is the human/CI readout: the one verb with no --json in the
# grammar. It checks the durable postconditions of a run directory.
__cog_workflow_conformance() {
  local run_dir=""

  while (($# > 0)); do
    case "$1" in
      --run-dir)
        __cog_workflow_require_value "--run-dir" "$#" "${2:-}"
        run_dir="$2"
        shift 2
        ;;
      *) __cog_workflow_die_invalid "unknown option" "option: $1" "" "run 'cog workflow --help'" ;;
    esac
  done
  __cog_workflow_require_run_dir "$run_dir"

  local state failed=false
  state="$(cog::fn::workflow::state_read "$run_dir")"
  cog::fn::ui_data "PASS state-parses"

  local as status dir all
  all="$(jq -r '[.nodes[].as] | join(" ")' <<<"$state")"
  while IFS= read -r as; do
    [[ -n $as ]] || continue
    status="$(jq -r --arg as "$as" '.nodes | map(select(.as == $as)) | first | .status' <<<"$state")"
    dir="$(cog::fn::workflow::node_dir "$run_dir" "$as")"
    if [[ -d $dir ]]; then
      cog::fn::ui_data "PASS node-dir ${as}"
    else
      cog::fn::ui_data "FAIL node-dir ${as}"
      failed=true
    fi
    case "$status" in
      done | failed)
        if [[ -f "${dir}/outputs.json" ]] \
          && jq -e "$__cog_workflow_receipt_self_check" "${dir}/outputs.json" >/dev/null 2>&1; then
          cog::fn::ui_data "PASS receipt ${as}"
        else
          cog::fn::ui_data "FAIL receipt ${as}"
          failed=true
        fi
        ;;
    esac
  done < <(jq -r '.nodes[].as' <<<"$state")

  local dangling
  dangling="$(jq -r --arg all "$all" '
    ($all | split(" ")) as $names
    | [ .nodes[] | . as $n | (.needs // [])[] | . as $t
        | select(($names | index($t)) == null) | ($n.as + " -> " + $t) ] | join(", ")' <<<"$state")"
  if [[ -z $dangling ]]; then
    cog::fn::ui_data "PASS needs-edges"
  else
    cog::fn::ui_data "FAIL needs-edges ${dangling}"
    failed=true
  fi

  [[ $failed != true ]] || return 2
}

cog::cmd::workflow() {
  local mode="${1:-}"

  case "$mode" in
    -h | --help) __cog_workflow_usage ;;
    list)
      shift
      __cog_workflow_list "$@"
      ;;
    show)
      shift
      __cog_workflow_show "$@"
      ;;
    init)
      shift
      __cog_workflow_init "$@"
      ;;
    validate)
      shift
      __cog_workflow_validate "$@"
      ;;
    resolve)
      shift
      __cog_workflow_resolve "$@"
      ;;
    next)
      shift
      __cog_workflow_next "$@"
      ;;
    claim)
      shift
      __cog_workflow_claim "$@"
      ;;
    record)
      shift
      __cog_workflow_record "$@"
      ;;
    advance)
      shift
      __cog_workflow_advance "$@"
      ;;
    reclaim)
      shift
      __cog_workflow_reclaim "$@"
      ;;
    summary)
      shift
      __cog_workflow_summary "$@"
      ;;
    conformance)
      shift
      __cog_workflow_conformance "$@"
      ;;
    *) __cog_workflow_die_invalid "unknown workflow verb" "verb: ${mode}" "" "run 'cog workflow --help'" ;;
  esac
}
