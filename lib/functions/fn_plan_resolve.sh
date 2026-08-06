# shellcheck shell=bash

cog::fn::plan_assert_flat_root() {
  local plan_root="${1:-}" plans_dir nested
  [[ -n $plan_root ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan root" "function: plan assert flat" "" ""
  plans_dir="${plan_root%/}/plans"
  [[ -d $plans_dir ]] || return 0
  nested="$(find "$plans_dir" -mindepth 3 -type f -name 'queue-rounds.yaml' | LC_ALL=C sort)"
  [[ -z $nested ]] || cog::fn::error_raise "InvalidInput" \
    "nested plan directory detected" "path: ${plans_dir}" "$nested" \
    "move each plan to a flat sibling plans/<slug>/ and wire ordering via depends_on"
}

__cog_plan_init_project_tree() {
  local plan_root="${1:-}" project_root="${2:-}" plans_dir queue_path
  [[ -n $plan_root && -n $project_root ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan init inputs" "function: plan init project tree" "" ""
  plans_dir="${plan_root%/}/plans"
  queue_path="${plan_root%/}/queue-plans.yaml"
  mkdir -p "$plans_dir" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create plans directory" "path: ${plans_dir}" "" "check permissions"
  cog::fn::plan_write_project_file "$plan_root" "$project_root"
  cog::fn::queue_bootstrap_file "$queue_path" plans
  cog::fn::queue_validate_file "$queue_path" plans
  cog::fn::plan_assert_flat_root "$plan_root"
}

cog::fn::plan_store_init_global() {
  local with_git="${1:-true}" store_root config_path
  store_root="$(cog::fn::plan_store_root)"
  mkdir -p "${store_root}/projects" "${store_root}/aliases" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create plan store directories" "path: ${store_root}" "" "check permissions"
  config_path="${store_root}/config.sh"
  if [[ ! -e $config_path ]]; then
    printf '%s\n' "COG_PLAN_STORE='auto'" "COG_PLAN_TRUST='strict'" >"$config_path" \
      || cog::fn::error_raise "JsonWriteFailed" \
        "could not write plan store config" "path: ${config_path}" "" "check permissions"
  fi
  if [[ $with_git == true && ! -d ${store_root}/.git ]]; then
    git -C "$store_root" init >/dev/null 2>&1 || cog::fn::error_raise "InvalidInput" \
      "could not initialize plan store git repository" "path: ${store_root}" "" "check git availability"
  fi
}

cog::fn::plan_project_init_global() {
  local root="${1:-}" with_git="${2:-true}" project_dir
  # Git-init the global store on first use (ADR-0011 D2), so `cog plan new --global`
  # and resolve-time creation produce a tracked vault, not only `cog plan store init`.
  # `--no-git` threads through as with_git=false to skip git initialization.
  cog::fn::plan_store_init_global "$with_git"
  project_dir="$(cog::fn::plan_project_dir "$root")"
  __cog_plan_init_project_tree "$project_dir" "$root"
  printf '%s\n' "$project_dir"
}

cog::fn::plan_project_init_local() {
  local root="${1:-}" project_root plan_root
  project_root="$(realpath "$root")"
  plan_root="$(cog::fn::plan_local_dir "$project_root")"
  __cog_plan_init_project_tree "$plan_root" "$project_root"
  printf '%s\n' "$plan_root"
}

__cog_plan_trust_mode_check() {
  local trust_mode="${1:-strict}"
  case "$trust_mode" in
    strict | off) return 0 ;;
    prompt)
      cog::fn::error_raise "InvalidInput" \
        "plan trust prompt mode is unsupported" "COG_PLAN_TRUST=prompt" \
        "cog is non-interactive for plan trust decisions" "use COG_PLAN_TRUST=strict or run cog plan trust"
      ;;
    *)
      cog::fn::error_raise "InvalidConfigValue" \
        "invalid plan trust value" "COG_PLAN_TRUST=${trust_mode}" \
        "expected strict, prompt, or off" "correct the plan config value"
      ;;
  esac
}

cog::fn::plan_resolve_json() {
  local project_root="${1:-}" store_flag="${2:-}" plan_root_flag="${3:-}"
  # plan_source/plan_line are filled and consumed by the config loader via
  # namerefs, which shellcheck cannot see — it reports false SC2034.
  # shellcheck disable=SC2034
  local -A plan_config=() plan_source=() plan_line=()
  local identity project_key project_dir local_root selected_store selected_root trust_json trust_status sources_json
  local plans_dir queue_path trust_mode plan_home source_store
  # Declared local so the prefix assignments below scope to this function and do
  # not leak COG_PLAN_HOME/COG_PLAN_LOCAL_DIR into the caller's shell.
  local COG_PLAN_HOME COG_PLAN_LOCAL_DIR

  [[ -n $project_root ]] || project_root="$(pwd -P)"
  [[ -d $project_root ]] || cog::fn::error_raise "InputNotFound" \
    "project root not found" "path: ${project_root}" "" "check the project root"
  project_root="$(realpath "$project_root")"

  cog::fn::plan_config_load "$project_root" plan_config plan_source plan_line
  [[ -z $store_flag || $store_flag == auto || $store_flag == local || $store_flag == global ]] \
    || cog::fn::error_raise "InvalidConfigValue" \
      "invalid plan store value" "option: --store ${store_flag}" "expected auto, local, or global" \
      "use --store auto|local|global"

  if [[ -n $store_flag ]]; then
    plan_config[COG_PLAN_STORE]="$store_flag"
    plan_source[COG_PLAN_STORE]="cli:--store"
  fi
  if [[ -n $plan_root_flag ]]; then
    plan_config[COG_PLAN_ROOT]="$(realpath -m "$plan_root_flag")"
    # shellcheck disable=SC2034 # consumed by config loader via nameref
    plan_source[COG_PLAN_ROOT]="cli:--plan-root"
  fi

  __cog_plan_config_validate plan_config plan_source
  trust_mode="${plan_config[COG_PLAN_TRUST]}"
  __cog_plan_trust_mode_check "$trust_mode"

  plan_home="${plan_config[COG_PLAN_HOME]}"
  COG_PLAN_HOME="$plan_home" COG_PLAN_LOCAL_DIR="${plan_config[COG_PLAN_LOCAL_DIR]}" identity="$(cog::fn::plan_project_identity_json "$project_root")"
  project_key="$(jq -r '.project_key' <<<"$identity")"
  COG_PLAN_HOME="$plan_home" project_dir="$(cog::fn::plan_project_dir "$project_root")"
  COG_PLAN_LOCAL_DIR="${plan_config[COG_PLAN_LOCAL_DIR]}" local_root="$(cog::fn::plan_local_dir "$project_root")"
  trust_json="$(COG_PLAN_LOCAL_DIR="${plan_config[COG_PLAN_LOCAL_DIR]}" cog::fn::plan_trust_status_json "$project_root")"
  trust_status="$(jq -r '.status' <<<"$trust_json")"

  if [[ -n ${plan_config[COG_PLAN_ROOT]} ]]; then
    selected_store="custom"
    selected_root="${plan_config[COG_PLAN_ROOT]}"
  else
    source_store="${plan_config[COG_PLAN_STORE]}"
    case "$source_store" in
      global)
        selected_store="global"
        selected_root="$project_dir"
        trust_json="$(jq -c '. + {status: "implicitly-trusted-global"}' <<<"$trust_json")"
        ;;
      local)
        [[ -d $local_root ]] || cog::fn::error_raise "InputNotFound" \
          "local plan root not found" "path: ${local_root}" "" "run 'cog plan store init --local'"
        if [[ $trust_mode != off && $trust_status != trusted ]]; then
          cog::fn::error_raise "InvalidInput" \
            "local plan root is not trusted" "path: ${local_root}" "trust status: ${trust_status}" \
            "run 'cog plan trust --project-root ${project_root}'"
        fi
        selected_store="local"
        selected_root="$local_root"
        ;;
      auto)
        if [[ -d $local_root && ($trust_status == trusted || $trust_mode == off) ]]; then
          selected_store="local"
          selected_root="$local_root"
        else
          selected_store="global"
          selected_root="$project_dir"
          if [[ -d $local_root ]]; then
            trust_json="$(jq -c '. + {status: "local-untrusted-fell-back"}' <<<"$trust_json")"
          else
            trust_json="$(jq -c '. + {status: "global-default"}' <<<"$trust_json")"
          fi
        fi
        ;;
    esac
  fi

  plans_dir="${selected_root%/}/plans"
  queue_path="${selected_root%/}/queue-plans.yaml"
  sources_json="$(cog::fn::plan_config_sources_json plan_config plan_source)"

  jq -n \
    --arg schema "cog.plan.resolve.v1" \
    --arg store "$selected_store" \
    --arg plan_root "$selected_root" \
    --arg plans_dir "$plans_dir" \
    --arg queue_path "$queue_path" \
    --arg project_key "$project_key" \
    --arg project_dir "$project_dir" \
    --argjson identity "$identity" \
    --argjson trust "$trust_json" \
    --argjson sources "$sources_json" \
    '{schema: $schema, ok: true, store: $store, plan_root: $plan_root,
      plans_dir: $plans_dir, queue_path: $queue_path, project_key: $project_key,
      project_dir: $project_dir, identity: $identity, trust: $trust, sources: $sources}'
}

# Resolve the plan root for an item command and ensure its project tree exists,
# honoring the same --store/config/trust precedence as plan_resolve_json. Echoes
# two lines: STORE=<store> and ROOT=<plan-root>.
__cog_plan_item_resolve_root() {
  local project_root="${1:-}" store_flag="${2:-}" with_git="${3:-true}" resolve_json selected_store plan_root
  [[ -n $project_root ]] || project_root="$(pwd -P)"
  resolve_json="$(cog::fn::plan_resolve_json "$project_root" "$store_flag" "")"
  selected_store="$(jq -r '.store' <<<"$resolve_json")"
  case "$selected_store" in
    local) plan_root="$(cog::fn::plan_project_init_local "$project_root")" ;;
    global) plan_root="$(cog::fn::plan_project_init_global "$project_root" "$with_git")" ;;
    custom)
      plan_root="$(jq -r '.plan_root' <<<"$resolve_json")"
      __cog_plan_init_project_tree "$plan_root" "$(realpath "$project_root")"
      ;;
    *) cog::fn::error_raise "InvalidInput" \
      "unsupported store for plan item command" "store: ${selected_store}" "" "use --store global|local" ;;
  esac
  printf 'STORE=%s\n' "$selected_store"
  printf 'ROOT=%s\n' "$plan_root"
}

cog::fn::plan_item_new() {
  local project_root="${1:-}" store_flag="${2:-}" title="${3:-}" with_git="${4:-true}"
  local resolved selected_store plan_root slug plan_dir rounds_queue readme
  [[ -n $title ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan title" "option: --title" "" "pass --title <text>"
  resolved="$(__cog_plan_item_resolve_root "$project_root" "$store_flag" "$with_git")"
  selected_store="$(sed -n 's/^STORE=//p' <<<"$resolved")"
  plan_root="$(sed -n 's/^ROOT=//p' <<<"$resolved")"
  slug="$(cog::fn::plan_slug::derive "$title")"
  [[ -n $slug ]] || slug="plan"
  plan_dir="${plan_root%/}/plans/${slug}"
  [[ ! -d $plan_dir ]] || cog::fn::error_raise "InvalidInput" \
    "plan already exists" "path: ${plan_dir}" "" "choose a different title or remove the existing plan"
  mkdir -p "${plan_dir}/rounds" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create plan directory" "path: ${plan_dir}" "" "check permissions"
  rounds_queue="${plan_dir}/queue-rounds.yaml"
  cog::fn::queue_bootstrap_file "$rounds_queue" rounds
  cog::fn::queue_validate_file "$rounds_queue" rounds
  readme="${plan_dir}/README.md"
  printf '# %s\n\nPlan slug: %s\n' "$title" "$slug" >"$readme" \
    || cog::fn::error_raise "JsonWriteFailed" \
      "could not write plan README" "path: ${readme}" "" "check permissions"
  cog::fn::plan_assert_flat_root "$plan_root"
  jq -n \
    --arg schema "cog.plan.item.v1" \
    --arg store "$selected_store" \
    --arg plan_root "$plan_root" \
    --arg plan_slug "$slug" \
    --arg plan_dir "$plan_dir" \
    --arg title "$title" \
    '{schema: $schema, ok: true, store: $store, plan_root: $plan_root,
      plan_slug: $plan_slug, plan_dir: $plan_dir, title: $title}'
}

cog::fn::plan_item_list() {
  local project_root="${1:-}" store_flag="${2:-}" resolve_json plan_root plans_dir items_json
  [[ -n $project_root ]] || project_root="$(pwd -P)"
  resolve_json="$(cog::fn::plan_resolve_json "$project_root" "$store_flag" "")"
  plan_root="$(jq -r '.plan_root' <<<"$resolve_json")"
  plans_dir="${plan_root%/}/plans"
  items_json="$(find "$plans_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
    | LC_ALL=C sort | sed 's#.*/##' | jq -R . | jq -s .)"
  [[ -n $items_json ]] || items_json='[]'
  jq -n \
    --arg schema "cog.plan.item-list.v1" \
    --arg plan_root "$plan_root" \
    --arg plans_dir "$plans_dir" \
    --argjson plans "$items_json" \
    '{schema: $schema, ok: true, plan_root: $plan_root, plans_dir: $plans_dir, plans: $plans}'
}

cog::fn::plan_item_path() {
  local project_root="${1:-}" store_flag="${2:-}" plan_id="${3:-}" resolve_json plan_root plan_dir
  [[ -n $plan_id ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan id" "argument: <plan-id>" "" "pass a plan slug"
  [[ -n $project_root ]] || project_root="$(pwd -P)"
  resolve_json="$(cog::fn::plan_resolve_json "$project_root" "$store_flag" "")"
  plan_root="$(jq -r '.plan_root' <<<"$resolve_json")"
  plan_dir="${plan_root%/}/plans/${plan_id}"
  [[ -d $plan_dir ]] || cog::fn::error_raise "InputNotFound" \
    "plan not found" "path: ${plan_dir}" "" "run 'cog plan list' to see available plans"
  jq -n \
    --arg schema "cog.plan.item-path.v1" \
    --arg plan_root "$plan_root" \
    --arg plan_slug "$plan_id" \
    --arg plan_dir "$plan_dir" \
    '{schema: $schema, ok: true, plan_root: $plan_root, plan_slug: $plan_slug, plan_dir: $plan_dir}'
}

# Map a runner target (a plan directory or a main queue-plans.yaml file) to the
# resolved plan vault, labeling the store by matching the target-derived plan_root
# against the config/custom, global, and local candidates from plan_resolve_json.
# Role-named, stage-agnostic output; the single source of truth for runner and
# revision-boundary vault resolution across local, global, and custom stores.
cog::fn::plan_runner_resolve_json() {
  local project_root="${1:-}" target="${2:-}"
  # __rr_source/__rr_line are filled by the config loader via namerefs
  # (invisible to shellcheck) — suppress the false SC2034.
  # shellcheck disable=SC2034
  local -A __rr_config=() __rr_source=() __rr_line=()
  local rr_local_dir abs_target target_type plan_dir inner_queue_path plan_root main_queue plans_dir
  local plan_home identity global_root local_root custom_root
  local store project_key trust_json trust_status trust_mode

  [[ -n $project_root ]] || project_root="$(pwd -P)"
  [[ -d $project_root ]] || cog::fn::error_raise "InputNotFound" \
    "project root not found" "path: ${project_root}" "" "check the project root"
  project_root="$(realpath "$project_root")"

  [[ -n $target ]] || cog::fn::error_raise "MissingArgument" \
    "missing runner-resolve target" "function: plan runner-resolve" "" \
    "pass --target <plan_dir|queue>"
  # Runners pass -ar @<plan-dir>; strip one leading @ and trailing slashes.
  target="${target#@}"
  while [[ $target != "/" && $target == */ ]]; do target="${target%/}"; done
  [[ $target == /* ]] || target="${project_root%/}/${target}"
  abs_target="$(realpath -m "$target")"

  # Load plan config to mirror the engine's local-dir precedence.
  cog::fn::plan_config_load "$project_root" __rr_config __rr_source __rr_line
  rr_local_dir="${__rr_config[COG_PLAN_LOCAL_DIR]}"

  # Candidate roots: config/custom, global, and local. Derive each candidate
  # directly from config and project identity rather than through a store resolve.
  # A config-default resolve would fail closed on an untrusted or missing local store
  # (config COG_PLAN_STORE=local), and a store=global resolve would still take config
  # COG_PLAN_ROOT precedence and report the custom root as global. Deriving the global
  # vault from plan_project_dir (project identity + store root) is independent of
  # COG_PLAN_STORE, COG_PLAN_ROOT, and local trust, so every candidate is honored.
  plan_home="${__rr_config[COG_PLAN_HOME]}"
  identity="$(COG_PLAN_HOME="$plan_home" COG_PLAN_LOCAL_DIR="$rr_local_dir" cog::fn::plan_project_identity_json "$project_root")"
  project_key="$(jq -r '.project_key' <<<"$identity")"
  global_root="$(realpath -m "$(COG_PLAN_HOME="$plan_home" cog::fn::plan_project_dir "$project_root")")"
  local_root="$(realpath -m "$(COG_PLAN_LOCAL_DIR="$rr_local_dir" cog::fn::plan_local_dir "$project_root")")"
  custom_root=""
  [[ -n ${__rr_config[COG_PLAN_ROOT]:-} ]] && custom_root="$(realpath -m "${__rr_config[COG_PLAN_ROOT]}")"

  # Classify the target shape and derive its plan_root.
  if [[ "$(basename -- "$abs_target")" == "queue-plans.yaml" ]]; then
    target_type="main-queue"
    plan_root="$(dirname -- "$abs_target")"
    plan_dir="null"
    inner_queue_path="null"
  elif [[ -d $abs_target ]]; then
    target_type="plan-dir"
    [[ "$(basename -- "$(dirname -- "$abs_target")")" == "plans" ]] || cog::fn::error_raise "InvalidInput" \
      "runner-resolve plan directory must be a direct child of plans/" "path: ${abs_target}" "" \
      "pass <PLAN_ROOT>/plans/<slug>"
    plan_root="$(dirname -- "$(dirname -- "$abs_target")")"
    plan_dir="$abs_target"
    inner_queue_path="${abs_target}/queue-rounds.yaml"
    [[ -f $inner_queue_path ]] || cog::fn::error_raise "InvalidInput" \
      "plan directory has no queue-rounds.yaml" "path: ${abs_target}" "" \
      "pass a plan directory that contains queue-rounds.yaml"
  else
    cog::fn::error_raise "InvalidInput" \
      "runner-resolve target must be a plan directory or a queue-plans.yaml file" \
      "path: ${abs_target}" "" "pass <PLAN_ROOT>/plans/<slug> or <PLAN_ROOT>/queue-plans.yaml"
  fi
  plan_root="$(realpath -m "$plan_root")"

  # Label the store by matching the derived plan_root against the candidates.
  if [[ -n $custom_root && $plan_root == "$custom_root" ]]; then
    store="custom"
  elif [[ $plan_root == "$global_root" ]]; then
    store="global"
  elif [[ $plan_root == "$local_root" ]]; then
    store="local"
    # A local target is honored only under the same strict-trust rule the engine
    # applies to an explicit --store local resolve.
    trust_json="$(COG_PLAN_LOCAL_DIR="$rr_local_dir" cog::fn::plan_trust_status_json "$project_root")"
    trust_status="$(jq -r '.status' <<<"$trust_json")"
    trust_mode="${__rr_config[COG_PLAN_TRUST]:-strict}"
    if [[ $trust_mode != off && $trust_status != trusted ]]; then
      cog::fn::error_raise "InvalidInput" \
        "local plan root is not trusted" "path: ${local_root}" "trust status: ${trust_status}" \
        "run 'cog plan trust --project-root ${project_root}'"
    fi
  else
    cog::fn::error_raise "InvalidInput" \
      "target is not a member of the resolved plan vault" "path: ${abs_target}" \
      "expected under: ${global_root}/plans or ${local_root}/plans" "run 'cog plan list'"
  fi

  # Flatness, main-queue presence, and schema validation.
  cog::fn::plan_assert_flat_root "$plan_root"
  main_queue="${plan_root%/}/queue-plans.yaml"
  [[ -f $main_queue ]] || cog::fn::error_raise "InputNotFound" \
    "resolved main queue not found" "path: ${main_queue}" "" "run 'cog plan new'"
  cog::fn::queue_validate_file "$main_queue" plans
  if [[ $target_type == plan-dir ]]; then
    cog::fn::queue_validate_file "$inner_queue_path" rounds
  fi

  plans_dir="${plan_root%/}/plans"
  jq -n \
    --arg schema "cog.plan.runner-resolve.v1" \
    --arg repo_root "$project_root" \
    --arg target "$abs_target" \
    --arg target_type "$target_type" \
    --arg store "$store" \
    --arg project_key "$project_key" \
    --arg plan_root "$plan_root" \
    --arg plans_dir "$plans_dir" \
    --arg main_queue "$main_queue" \
    --arg plan_dir "$plan_dir" \
    --arg inner_queue_path "$inner_queue_path" \
    '{schema: $schema, ok: true, repo_root: $repo_root, target: $target,
      target_type: $target_type, store: $store, project_key: $project_key,
      plan_root: $plan_root, plans_dir: $plans_dir, main_queue: $main_queue,
      queue_path: $main_queue,
      plan_dir: (if $plan_dir == "null" then null else $plan_dir end),
      inner_queue_path: (if $inner_queue_path == "null" then null else $inner_queue_path end)}'
}
