# shellcheck shell=bash
: 'desc: Aggregate bootstrap domain present/missing status.'

__cog_bootstrap_audit_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.domains|type=="array") and (.domains|length==6) and (all(.domains[]; (.domain|type=="string") and (.present|type=="boolean") and (.artifacts|type=="array") and (.requirements|type=="array") and (.requires_question|type=="boolean") and (.default_in_scope|type=="boolean") and (.default_action|type=="string") and (.requirements_satisfied|type=="boolean")))'

__cog_bootstrap_audit_usage() {
  cog::fn::ui_data "Usage: cog bootstrap-audit [--project-root <dir>] (<out.json>|--json)"
}

# Emit a JSON array of {name, present} for each relpath, presence by existence
# under project_root. README/LICENSE/config presence is a deliverable-file check,
# not a detector's template-type signal, so the audit reports what already exists.
__cog_bootstrap_audit_artifacts() {
  local root="$1"
  shift
  local rel present
  local -a objs=()
  for rel in "$@"; do
    if [[ -e "$root/$rel" ]]; then present=true; else present=false; fi
    objs+=("$(jq -cn --arg n "$rel" --argjson p "$present" '{name: $n, present: $p}')")
  done
  printf '%s\n' "${objs[@]}" | jq -cs '.'
}

# Emit one domain object. present is computed by the caller (AND across
# deliverables for most domains, OR for taskrunner, existing_ci for ci).
# requirements is a (possibly empty) JSON array of content-level {name, satisfied}
# checks a present domain must still pass — cross-domain fragments a bare
# file-existence check cannot see (nix ignore lines, the editorconfig-checker hook).
# The scope model is machine-explicit (ADR-0062): every domain is in scope by
# default (opt-out is an orchestrator decision), a present domain reconciles while
# an absent one installs, and requirements_satisfied folds the content checks into
# one boolean so the orchestrator reads the action instead of re-deriving it.
__cog_bootstrap_audit_domain() {
  local domain="$1" present="$2" requires_question="$3" detail="$4" artifacts="$5" requirements="${6:-[]}"
  jq -cn \
    --arg domain "$domain" --argjson present "$present" \
    --argjson requires_question "$requires_question" \
    --arg detail "$detail" --argjson artifacts "$artifacts" \
    --argjson requirements "$requirements" \
    '{domain: $domain, present: $present, artifacts: $artifacts,
      requirements: $requirements, requires_question: $requires_question,
      default_in_scope: true,
      default_action: (if $present then "reconcile" else "install" end),
      requirements_satisfied: ($requirements | all(.satisfied)),
      detail: (if $detail == "" then null else $detail end)}'
}

# Emit one {name, satisfied} requirement object.
__cog_bootstrap_audit_req() {
  jq -cn --arg n "$1" --argjson s "$2" '{name: $n, satisfied: $s}'
}

# Print true when the file under root exists and contains every fixed-string
# pattern; false otherwise. Backs the content-level requirement checks.
__cog_bootstrap_audit_file_has() {
  local root="$1" rel="$2"
  shift 2
  local f="$root/$rel" p
  [[ -f $f ]] || {
    printf 'false'
    return
  }
  for p in "$@"; do
    grep -qF -- "$p" "$f" || {
      printf 'false'
      return
    }
  done
  printf 'true'
}

__cog_bootstrap_audit_build_json() {
  local project_root="$1"
  local ok=true reason=""
  # Emit the full six-domain shape even on a bad root: missing project reports
  # every domain absent, matching the detectors' ok=false-with-complete-shape
  # convention rather than an empty, invariant-breaking payload.
  if [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  fi

  local -a rows=()
  local arts present

  # precommit: one deliverable config file. When an .editorconfig baseline
  # exists, the config must carry a matching editorconfig-checker hook.
  arts="$(__cog_bootstrap_audit_artifacts "$project_root" ".pre-commit-config.yaml")"
  present="$(jq -c 'all(.[]; .present)' <<<"$arts")"
  local pc_reqs='[]'
  if [[ $present == true && -e "$project_root/.editorconfig" ]]; then
    pc_reqs="[$(__cog_bootstrap_audit_req editorconfig-checker-hook \
      "$(__cog_bootstrap_audit_file_has "$project_root" ".pre-commit-config.yaml" "editorconfig-checker")")]"
  fi
  rows+=("$(__cog_bootstrap_audit_domain precommit "$present" false "pre-commit hooks" "$arts" "$pc_reqs")")

  # editorconfig: one deliverable.
  arts="$(__cog_bootstrap_audit_artifacts "$project_root" ".editorconfig")"
  present="$(jq -c 'all(.[]; .present)' <<<"$arts")"
  rows+=("$(__cog_bootstrap_audit_domain editorconfig "$present" false "editor defaults" "$arts")")

  # nix: devshell flake plus its direnv autoloader; present when both exist.
  # A present devshell requires the .direnv/ and /result ignore lines in
  # .gitignore, applied via `cog gitignore-apply --type nix --append`.
  arts="$(__cog_bootstrap_audit_artifacts "$project_root" "flake.nix" ".envrc")"
  present="$(jq -c 'all(.[]; .present)' <<<"$arts")"
  local nix_reqs='[]'
  if [[ $present == true ]]; then
    nix_reqs="[$(__cog_bootstrap_audit_req gitignore-nix-lines \
      "$(__cog_bootstrap_audit_file_has "$project_root" ".gitignore" ".direnv/" "/result")")]"
  fi
  rows+=("$(__cog_bootstrap_audit_domain nix "$present" false "nix devshell + direnv" "$arts" "$nix_reqs")")

  # repo: gitignore, license, readme are the bootstrap-repo deliverable set;
  # a missing LICENSE needs operator-supplied SPDX/holder/year.
  arts="$(__cog_bootstrap_audit_artifacts "$project_root" ".gitignore" "LICENSE" "README.md")"
  present="$(jq -c 'all(.[]; .present)' <<<"$arts")"
  local license_present
  license_present="$(jq -c '[.[] | select(.name == "LICENSE")][0].present' <<<"$arts")"
  local repo_rq=false
  [[ $license_present == false ]] && repo_rq=true
  rows+=("$(__cog_bootstrap_audit_domain repo "$present" "$repo_rq" "gitignore + license + readme" "$arts")")

  # ci: reuse ci-detect for real existing_ci presence and the operator-target question.
  if ! declare -F __cog_ci_detect_build_json >/dev/null; then
    # shellcheck source=cmd_ci_detect.sh
    source "${LIB_DIR}/commands/cmd_ci_detect.sh"
  fi
  local ci_json existing_len ci_present ci_rq ci_host ci_target ci_arts ci_detail
  ci_json="$(__cog_ci_detect_build_json "$project_root")"
  existing_len="$(jq -c '.existing_ci | length' <<<"$ci_json")"
  ci_rq="$(jq -c '.requires_question' <<<"$ci_json")"
  ci_host="$(jq -r '.host' <<<"$ci_json")"
  ci_target="$(jq -r '.target' <<<"$ci_json")"
  if [[ $existing_len -gt 0 ]]; then
    ci_present=true
    ci_arts="$(jq -c '[.existing_ci[] | {name: ., present: true}]' <<<"$ci_json")"
  else
    ci_present=false
    local ci_placeholder
    case "$ci_target" in
      github) ci_placeholder=".github/workflows/ci.yml" ;;
      gitlab) ci_placeholder=".gitlab-ci.yml" ;;
      *) ci_placeholder="CI workflow" ;;
    esac
    ci_arts="$(jq -cn --arg n "$ci_placeholder" '[{name: $n, present: false}]')"
  fi
  ci_detail="host: ${ci_host}, target: ${ci_target}"
  # When a flake.nix exists, an existing pipeline must reuse it (`nix develop`)
  # so CI and local development share one toolchain.
  local ci_reqs='[]'
  if [[ $ci_present == true && -e "$project_root/flake.nix" ]]; then
    local ci_flake=false ci_file
    while IFS= read -r ci_file; do
      [[ -n $ci_file ]] || continue
      if [[ -f "$project_root/$ci_file" ]] && grep -qF -- "nix develop" "$project_root/$ci_file"; then
        ci_flake=true
        break
      fi
    done < <(jq -r '.existing_ci[]' <<<"$ci_json")
    ci_reqs="[$(__cog_bootstrap_audit_req ci-flake-reuse "$ci_flake")]"
  fi
  rows+=("$(__cog_bootstrap_audit_domain ci "$ci_present" "$ci_rq" "$ci_detail" "$ci_arts" "$ci_reqs")")

  # taskrunner: any recognized runner file satisfies the domain. Report a single
  # runner artifact named for whichever variant exists (default justfile) so the
  # breakdown reads as one deliverable, not competing alternatives.
  local runner="" cand
  for cand in justfile Justfile Makefile makefile GNUmakefile; do
    if [[ -e "$project_root/$cand" ]]; then
      runner="$cand"
      break
    fi
  done
  if [[ -n $runner ]]; then
    present=true
  else
    present=false
    runner="justfile"
  fi
  arts="$(jq -cn --arg n "$runner" --argjson p "$present" '[{name: $n, present: $p}]')"
  rows+=("$(__cog_bootstrap_audit_domain taskrunner "$present" false "task runner" "$arts")")

  printf '%s\n' "${rows[@]}" | jq -s \
    --argjson ok "$ok" --arg project_root "$project_root" --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, domains: .,
      reason: (if $reason == "" then null else $reason end)}'
}

cog::cmd::bootstrap_audit() {
  local project_root mode="" out="" json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_bootstrap_audit_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog bootstrap-audit --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate bootstrap-audit output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown bootstrap-audit option" "option: $1" "" "run 'cog bootstrap-audit --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many bootstrap-audit output paths" "argument: $1" "" "run 'cog bootstrap-audit --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing bootstrap-audit output mode" "usage: cog bootstrap-audit [flags] (<out.json>|--json)" "" "run 'cog bootstrap-audit --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_bootstrap_audit_build_json "$project_root")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_bootstrap_audit_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_bootstrap_audit_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}
