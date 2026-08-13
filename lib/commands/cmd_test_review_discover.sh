# shellcheck shell=bash
: 'desc: Detect test runner and test-review batch status.'

__cog_test_review_discover_self_check='(.ok|type=="boolean") and (.repo_root|type=="string") and (.manifest_path|type=="string") and (.plan_path|type=="string") and (.project.manifests|type=="array") and (.project.languages|type=="array") and (.test_files|type=="array") and (.runner.detected|type=="boolean") and (.runner.candidates|type=="array") and (.batch_status.manifest_exists|type=="boolean") and (.batch_status.plan_exists|type=="boolean") and (.batch_status.task_count|type=="number") and (.batch_status.pending_task_count|type=="number")'

__cog_test_review_discover_usage() {
  cog::fn::ui_data "Usage: cog test-review-discover [--repo-root <dir>] [--manifest <path>] [--plan <path>] (<out.json>|--json)"
}

__cog_test_review_discover_json_string_array() {
  if (($# == 0)); then
    printf '[]\n'
    return 0
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
  return 0
}

__cog_test_review_discover_add_unique() {
  local value="$1" existing
  shift
  for existing in "$@"; do
    [[ $existing == "$value" ]] && return 1
  done
  printf '%s\n' "$value"
  return 0
}

__cog_test_review_discover_rel_files() {
  local root="$1"
  shift
  (cd "$root" && find . "$@" -print 2>/dev/null) \
    | sed 's#^\./##' \
    | sort -u
  return 0
}

__cog_test_review_discover_detect_project_json() {
  local root="$1"
  local -a manifests=()
  local -a languages=()
  [[ -f $root/Cargo.toml ]] && {
    manifests+=("Cargo.toml")
    languages+=("rust")
  }
  if [[ -f $root/pyproject.toml ]]; then
    manifests+=("pyproject.toml")
    languages+=("python")
  elif [[ -f $root/setup.py ]]; then
    manifests+=("setup.py")
    languages+=("python")
  fi
  [[ -f $root/package.json ]] && {
    manifests+=("package.json")
    languages+=("javascript")
  }
  [[ -f $root/go.mod ]] && {
    manifests+=("go.mod")
    languages+=("go")
  }
  if find "$root" \( -name '*.bats' -o -path '*/tests/*.sh' \) -type f -print -quit 2>/dev/null | grep -q .; then
    __cog_test_review_discover_add_unique bash "${languages[@]}" >/dev/null && languages+=("bash")
  fi

  jq -n \
    --argjson manifests "$(__cog_test_review_discover_json_string_array "${manifests[@]}")" \
    --argjson languages "$(__cog_test_review_discover_json_string_array "${languages[@]}")" \
    '{manifests: $manifests, languages: $languages}'
  return 0
}

__cog_test_review_discover_detect_tests_json() {
  local root="$1" f
  local -a files=()
  while IFS= read -r f; do
    [[ -n $f ]] && files+=("$f")
  done < <(
    {
      __cog_test_review_discover_rel_files "$root" -path './.git' -prune -o -type f \( \
        -path './tests/*.rs' -o -path './tests/**/*.rs' -o -name '*_test.rs' \
        -o -path './tests/*.py' -o -path './tests/**/*.py' -o -name 'test_*.py' -o -name '*_test.py' -o -name 'conftest.py' \
        -o -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' -o -name '*.test.jsx' \
        -o -name '*.spec.ts' -o -name '*.spec.tsx' -o -name '*.spec.js' -o -name '*.spec.jsx' \
        -o -path './__tests__/*' -o -path './__tests__/**/*' \
        -o -name '*_test.go' -o -name '*.bats' -o -path './tests/*.sh' -o -path './tests/**/*.sh' \
        \)
      while IFS= read -r mod; do
        grep -Eq '#\[cfg\(test\)\]' "$root/$mod" && printf '%s\n' "$mod"
      done < <(__cog_test_review_discover_rel_files "$root" -path './.git' -prune -o -path './src/*/mod.rs' -type f)
    } | sort -u
  )
  __cog_test_review_discover_json_string_array "${files[@]}"
  return 0
}

__cog_test_review_discover_candidate_json() {
  local name="$1" command_json="$2" status="$3" detected_by="$4"
  jq -cn \
    --arg name "$name" \
    --argjson command "$command_json" \
    --arg status "$status" \
    --arg detected_by "$detected_by" \
    '{name: $name, command: $command, status: $status, detected_by: $detected_by}'
  return 0
}

__cog_test_review_discover_detect_runner_json() {
  local root="$1" test_files_json="$2"
  local selected="" name="" command_json="[]" reason="" status
  local has_py has_bats has_vitest has_npm_test
  local -a candidates=()

  __cog_test_review_discover_add_candidate() {
    local cname="$1" ccmd="$2" detected="$3" why="$4"
    status="not-detected"
    if [[ $detected == true ]]; then
      status="detected"
      if [[ -z $selected ]]; then
        selected="$cname"
        name="$cname"
        command_json="$ccmd"
        reason="$why"
      fi
    fi
    candidates+=("$(__cog_test_review_discover_candidate_json "$cname" "$ccmd" "$status" "$why")")
    return 0
  }

  has_py="$(jq -r 'any(.[]; test("(^|/)tests?/.*\\.py$|(^|/)test_[^/]*\\.py$|_test\\.py$|(^|/)conftest\\.py$"))' <<<"$test_files_json")"
  has_bats="$(jq -r 'any(.[]; test("\\.bats$|(^|/)tests?/.*\\.sh$"))' <<<"$test_files_json")"
  has_vitest=false
  has_npm_test=false
  if [[ -f $root/package.json ]]; then
    grep -Eq '"vitest"|"test"[[:space:]]*:[[:space:]]*"[^"]*vitest' "$root/package.json" && has_vitest=true
    grep -Eq '"test"[[:space:]]*:' "$root/package.json" && has_npm_test=true
  fi

  __cog_test_review_discover_add_candidate just-test "$(__cog_test_review_discover_json_string_array just test)" "$(grep -Eqs '^[[:space:]]*test[[:space:]]*:' "$root/justfile" "$root/Justfile" "$root/.justfile" && printf true || printf false)" "justfile test recipe"
  __cog_test_review_discover_add_candidate cargo-nextest "$(__cog_test_review_discover_json_string_array cargo nextest run)" "$([[ -f "$root/Cargo.toml" ]] && __have cargo-nextest && printf true || printf false)" "Cargo.toml and cargo-nextest"
  __cog_test_review_discover_add_candidate cargo-test "$(__cog_test_review_discover_json_string_array cargo test)" "$([[ -f "$root/Cargo.toml" ]] && printf true || printf false)" "Cargo.toml"
  __cog_test_review_discover_add_candidate pytest-xdist "$(__cog_test_review_discover_json_string_array pytest -n auto)" "$([[ $has_py == true ]] && __have pytest && pytest --help 2>/dev/null | grep -q -- '-n' && printf true || printf false)" "Python tests and pytest-xdist"
  __cog_test_review_discover_add_candidate pytest "$(__cog_test_review_discover_json_string_array pytest)" "$([[ $has_py == true ]] && __have pytest && printf true || printf false)" "Python tests and pytest"
  __cog_test_review_discover_add_candidate vitest "$(__cog_test_review_discover_json_string_array vitest run)" "$([[ $has_vitest == true ]] && printf true || printf false)" "package.json vitest signal"
  __cog_test_review_discover_add_candidate npm-test-run "$(__cog_test_review_discover_json_string_array npm test -- --run)" "$([[ $has_npm_test == true ]] && [[ $has_vitest == true ]] && printf true || printf false)" "package.json test script with vitest"
  __cog_test_review_discover_add_candidate npm-test "$(__cog_test_review_discover_json_string_array npm test)" "$([[ $has_npm_test == true ]] && printf true || printf false)" "package.json test script"
  __cog_test_review_discover_add_candidate go-test "$(__cog_test_review_discover_json_string_array go test ./...)" "$([[ -f "$root/go.mod" ]] && printf true || printf false)" "go.mod"
  __cog_test_review_discover_add_candidate bats "$(__cog_test_review_discover_json_string_array bats tests/)" "$([[ $has_bats == true ]] && printf true || printf false)" "Bats test files"

  jq -n \
    --argjson detected "$([[ -n $selected ]] && printf true || printf false)" \
    --arg name "$name" \
    --argjson command "$command_json" \
    --arg reason "$reason" \
    --argjson candidates "$(printf '%s\n' "${candidates[@]}" | jq -s .)" \
    '{
      detected: $detected,
      name: (if $detected then $name else null end),
      command: (if $detected then $command else [] end),
      reason: (if $detected then $reason else null end),
      candidates: $candidates
    }'
  return 0
}

__cog_test_review_discover_extract_tasks_json() {
  local plan="$1"
  [[ -f $plan ]] || {
    printf '[]\n'
    return 0
  }
  awk '
    /^[[:space:]]*(file|File):[[:space:]]*/ {
      current = $0
      sub(/^[^:]*:[[:space:]]*/, "", current)
      next
    }
    /^##?[[:space:]]+/ {
      current = ""
    }
    /^[[:space:]]*-[[:space:]]+\[[ xX]\][[:space:]]+T-[A-Z]+-[0-9]+/ {
      line = $0
      done = (line ~ /\[[xX]\]/)
      match(line, /T-[A-Z]+-[0-9]+/)
      id = substr(line, RSTART, RLENGTH)
      file = current
      if (match(line, /(file|File):[[:space:]]*[^,;) ]+/)) {
        file = substr(line, RSTART, RLENGTH)
        sub(/^[^:]*:[[:space:]]*/, "", file)
      }
      gsub(/"/, "\\\"", file)
      printf("{\"id\":\"%s\",\"done\":%s,\"file\":\"%s\"}\n", id, done ? "true" : "false", file)
    }
  ' "$plan" | jq -s .
  return 0
}

__cog_test_review_discover_batch_status_json() {
  local manifest="$1" plan="$2"
  local manifest_exists plan_exists phase tasks pending completed needs_replan rolled_back next_batch
  manifest_exists=false
  plan_exists=false
  [[ -f $manifest ]] && manifest_exists=true
  [[ -f $plan ]] && plan_exists=true
  phase=null
  if [[ $manifest_exists == true ]] && __have yq && yq e '.' "$manifest" >/dev/null 2>&1; then
    phase="$(yq e -o=json '.phase // null' "$manifest")"
  fi
  tasks="$(__cog_test_review_discover_extract_tasks_json "$plan")"
  pending="$(jq -c '[.[] | select(.done == false)]' <<<"$tasks")"
  completed="$(jq -r '[.[] | select(.done == true)] | length' <<<"$tasks")"
  needs_replan=0
  rolled_back=0
  if [[ $manifest_exists == true ]] && __have yq && yq e '.' "$manifest" >/dev/null 2>&1; then
    needs_replan="$(yq e -o=json '.["implementation-log"] // []' "$manifest" | jq '[.[] | select(.status == "needs-replan")] | length')"
    rolled_back="$(yq e -o=json '.["implementation-log"] // []' "$manifest" | jq '[.[] | select(.["rolled-back"] == true or .rolled_back == true)] | length')"
  fi
  next_batch="$(jq -c '
    if length == 0 then null
    else
      .[0].file as $first_file |
      [ .[] | select((($first_file == "") or (.file == $first_file)) ) ][0:5] as $items |
      {index: 1, task_ids: ($items | map(.id)), files: ($items | map(.file) | map(select(. != "")) | unique)}
    end
  ' <<<"$pending")"
  jq -n \
    --argjson manifest_exists "$manifest_exists" \
    --argjson plan_exists "$plan_exists" \
    --argjson phase "$phase" \
    --argjson task_count "$(jq 'length' <<<"$tasks")" \
    --argjson completed_task_count "$completed" \
    --argjson pending_task_count "$(jq 'length' <<<"$pending")" \
    --argjson needs_replan_count "$needs_replan" \
    --argjson rolled_back_count "$rolled_back" \
    --argjson next_batch "$next_batch" \
    '{
      manifest_exists: $manifest_exists,
      plan_exists: $plan_exists,
      phase: $phase,
      task_count: $task_count,
      completed_task_count: $completed_task_count,
      pending_task_count: $pending_task_count,
      needs_replan_count: $needs_replan_count,
      rolled_back_count: $rolled_back_count,
      next_batch: $next_batch
    }'
  return 0
}

__cog_test_review_discover_build_json() {
  local repo_root="$1" manifest_path="$2" plan_path="$3"
  local project tests runner batch
  repo_root="$(realpath "$repo_root")"
  project="$(__cog_test_review_discover_detect_project_json "$repo_root")"
  tests="$(__cog_test_review_discover_detect_tests_json "$repo_root")"
  runner="$(__cog_test_review_discover_detect_runner_json "$repo_root" "$tests")"
  batch="$(__cog_test_review_discover_batch_status_json "$manifest_path" "$plan_path")"
  jq -n \
    --argjson ok true \
    --arg repo_root "$repo_root" \
    --arg manifest_path "$manifest_path" \
    --arg plan_path "$plan_path" \
    --argjson project "$project" \
    --argjson test_files "$tests" \
    --argjson runner "$runner" \
    --argjson batch_status "$batch" \
    '{
      ok: $ok,
      repo_root: $repo_root,
      manifest_path: $manifest_path,
      plan_path: $plan_path,
      project: $project,
      test_files: $test_files,
      runner: $runner,
      batch_status: $batch_status
    }'
  return 0
}

cog::cmd::test_review_discover() {
  local repo_root manifest_path="" plan_path="" mode="" out="" json
  repo_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_test_review_discover_usage
        return 0
        ;;
      --repo-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing repo root" "option: --repo-root" "" "run 'cog test-review-discover --help'"
        repo_root="$2"
        shift 2
        ;;
      --manifest)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing manifest path" "option: --manifest" "" "run 'cog test-review-discover --help'"
        manifest_path="$2"
        shift 2
        ;;
      --plan)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing plan path" "option: --plan" "" "run 'cog test-review-discover --help'"
        plan_path="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate test-review-discover output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown test-review-discover option" "option: $1" "" "run 'cog test-review-discover --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many test-review-discover output paths" "argument: $1" "" "run 'cog test-review-discover --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing test-review-discover output mode" "usage: cog test-review-discover [--repo-root <dir>] [--manifest <path>] [--plan <path>] (<out.json>|--json)" "" "run 'cog test-review-discover --help'"
  [[ -n $mode ]] || mode=json
  repo_root="$(realpath "$repo_root")"
  [[ -n $manifest_path ]] || manifest_path="$repo_root/.test-review/MANIFEST.yaml"
  [[ -n $plan_path ]] || plan_path="$repo_root/.test-review/REFACTOR_PLAN.md"
  json="$(__cog_test_review_discover_build_json "$repo_root" "$manifest_path" "$plan_path")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_test_review_discover_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_test_review_discover_self_check" "$json"; fi
}
