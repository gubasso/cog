# shellcheck shell=bash
: 'desc: Aggregate bootstrap domain present/missing status.'

__cog_bootstrap_audit_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.domains|type=="array") and (.domains|length==7) and (all(.domains[]; (.domain|type=="string") and (.present|type=="boolean") and (.artifacts|type=="array") and (.requirements|type=="array") and (.requires_question|type=="boolean") and (.default_in_scope|type=="boolean") and (.default_action|type=="string") and (.requirements_satisfied|type=="boolean")))'

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
# The scope model is machine-explicit (ADR-0019): every domain is in scope by
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

# Print the config's hooks as one JSON array, or fail when the file is absent or
# does not parse.
#
# yq is a real YAML parser, so comments, quoting styles, escapes, and
# inline-vs-block sequences are its problem rather than ours. An earlier lexical
# scanner here produced a steady stream of both false positives (a rationale
# comment merely naming a forbidden flag) and false negatives (a quoted hook id,
# an escaped quote inside a value) — each fix exposing the next edge case. yq is
# already a first-class dependency of this CLI.
__cog_bootstrap_audit_hooks_json() {
  local root="$1" rel="$2"
  local f="$root/$rel" docs
  [[ -f $f ]] || return 1
  # yq evaluates once per YAML document, so a multi-document file emits a STREAM
  # of arrays. Slurp and concatenate, or a later `---` document would decide the
  # verdict on its own. The two steps stay separate so a yq parse failure is not
  # swallowed by a downstream jq that happily reads empty input.
  docs="$(yq e -o=json -I=0 '[.repos[]?.hooks[]?]' "$f" 2>/dev/null)" || return 1
  jq -c -s 'add // []' <<<"$docs" 2>/dev/null || return 1
}

# Print true when the violation predicate is definitively false.
#
# Fails CLOSED. `jq -e` cannot distinguish "predicate is false" from "jq raised
# an error" — both are non-zero — so using its status alone would report a
# malformed config (e.g. a scalar `args:`) as compliant. An audit that gates
# commits must never fail open, so anything other than a literal `false` here
# means unsatisfied.
__cog_bootstrap_audit_no_violation() {
  local hooks="$1" filter="$2" verdict
  verdict="$(jq -r "$filter" <<<"$hooks" 2>/dev/null)" || {
    printf 'false'
    return
  }
  if [[ $verdict == false ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

# Print true when no `<hook>` stanza is missing an `args:` key — including when
# the hook is absent entirely. Backs hooks whose upstream default args are
# mutating, where overriding nothing silently inherits them.
#
# `args: []` counts as set: it is an explicit override to no arguments.
__cog_bootstrap_audit_hook_sets_args() {
  local root="$1" rel="$2" hook="$3" hooks
  hooks="$(__cog_bootstrap_audit_hooks_json "$root" "$rel")" || {
    printf 'false'
    return
  }
  __cog_bootstrap_audit_no_violation "$hooks" \
    "any(.[]; .id == \"$hook\" and (.args | not))"
}

# Print true when the legacy bare `ruff` hook id is absent. Upstream renamed it
# to `ruff-check` and marks `ruff` a legacy alias.
__cog_bootstrap_audit_no_legacy_ruff_id() {
  local root="$1" rel="$2" hooks
  hooks="$(__cog_bootstrap_audit_hooks_json "$root" "$rel")" || {
    printf 'false'
    return
  }
  __cog_bootstrap_audit_no_violation "$hooks" 'any(.[]; .id == "ruff")'
}

# Print true unless the *primary* ruff hook passes `--select`. A CLI `--select`
# replaces the active rule selection from every resolved config file, so the
# project's own [tool.ruff.lint] select stops applying.
#
# An `alias:` is a weak signal, not proof of intent: pre-commit defines it only
# as an additional hook identifier, defaulting to the empty string — so null and
# "" both mean unaliased. An aliased stanza is exempted ONLY when a non-aliased
# ruff hook also exists — i.e. when it is genuinely secondary, the established
# shape for a deliberately isolated single-rule hook (e.g. `--select PLC2701`)
# where `--extend-select` would wrongly enable the project's entire rule set. A
# lone aliased ruff hook IS the primary hook and is still flagged.
__cog_bootstrap_audit_ruff_extend_select() {
  local root="$1" rel="$2" hooks
  hooks="$(__cog_bootstrap_audit_hooks_json "$root" "$rel")" || {
    printf 'false'
    return
  }
  # shellcheck disable=SC2016 # `$ruff`/`$primary` are jq variables; the filter must reach jq unexpanded.
  __cog_bootstrap_audit_no_violation "$hooks" '
    def is_ruff: .id == "ruff" or .id == "ruff-check";
    def unaliased: (.alias | . == null or . == "");
    def uses_select: [(.args // [])[] | tostring] | any(test("^--select(=|$)"));
    map(select(is_ruff)) as $ruff
    | ($ruff | map(select(unaliased))) as $primary
    | ($primary | any(uses_select))
      or (($primary | length) == 0 and ($ruff | any(uses_select)))
  '
}

# Print true when the file under root exists and its bytes exactly match the
# expected content; false otherwise.
__cog_bootstrap_audit_file_exact() {
  local root="$1" rel="$2" expected="$3" f
  f="$root/$rel"
  if [[ -f $f ]] && cmp -s "$f" <(printf '%s' "$expected"); then
    printf 'true'
  else
    printf 'false'
  fi
}

__cog_bootstrap_audit_build_json() {
  local project_root="$1"
  local ok=true reason=""
  # Emit the full seven-domain shape even on a bad root: missing project reports
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
  if [[ $present == true ]]; then
    local -a pc_items=()
    if [[ -e "$project_root/.editorconfig" ]]; then
      pc_items+=("$(__cog_bootstrap_audit_req editorconfig-checker-hook \
        "$(__cog_bootstrap_audit_file_has "$project_root" ".pre-commit-config.yaml" "editorconfig-checker")")")
    fi
    # Upstream renamed `ruff` -> `ruff-check`; the bare id is a legacy alias.
    pc_items+=("$(__cog_bootstrap_audit_req no-legacy-ruff-id \
      "$(__cog_bootstrap_audit_no_legacy_ruff_id "$project_root" ".pre-commit-config.yaml")")")
    pc_items+=("$(__cog_bootstrap_audit_req ruff-extend-select \
      "$(__cog_bootstrap_audit_ruff_extend_select "$project_root" ".pre-commit-config.yaml")")")
    # typos' upstream default args are [--write-changes, --force-exclude], so a
    # stanza that overrides no args auto-fixes rather than reporting.
    pc_items+=("$(__cog_bootstrap_audit_req typos-args-explicit \
      "$(__cog_bootstrap_audit_hook_sets_args "$project_root" ".pre-commit-config.yaml" typos)")")
    pc_reqs="[$(
      IFS=,
      printf '%s' "${pc_items[*]}"
    )]"
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
    # No nix-direnv requirement: direnv's own `use_flake` passes
    # `--profile "$(direnv_layout_dir)/flake-profile"`, and a Nix profile
    # generation is a permanent GC root, so the devShell survives
    # `nix-collect-garbage` without nix-direnv. nix-direnv buys evaluation
    # caching, which is a preference, not a correctness requirement.
    nix_reqs="[$(__cog_bootstrap_audit_req gitignore-nix-lines \
      "$(__cog_bootstrap_audit_file_has "$project_root" ".gitignore" ".direnv/" "/result")")]"
  fi
  rows+=("$(__cog_bootstrap_audit_domain nix "$present" false "nix devshell + direnv" "$arts" "$nix_reqs")")

  # repo: gitignore, license, readme are the bootstrap-repo deliverable set;
  # a missing license needs operator-supplied SPDX/holder/year.
  #
  # The license artifact is resolved by convention, not by the literal name
  # `LICENSE`: a dual `MIT OR Apache-2.0` layout (LICENSE-MIT + LICENSE-APACHE,
  # the Rust ecosystem norm), a COPYING, or a LICENSE.md all satisfy the
  # deliverable. Reporting one of those as an absent license told the orchestrator
  # to ask the operator for an SPDX id the project had already answered. Every
  # resolved file is reported, so the breakdown names what actually exists.
  local -a license_arts=()
  local license_name license_present=false
  while IFS= read -r license_name; do
    [[ -n $license_name ]] || continue
    license_present=true
    license_arts+=("$(jq -cn --arg n "$license_name" '{name: $n, present: true}')")
  done < <(cog::fn::template::resolve_licenses "$project_root" || true)
  ((${#license_arts[@]} > 0)) || license_arts=("$(jq -cn '{name: "LICENSE", present: false}')")
  arts="$(__cog_bootstrap_audit_artifacts "$project_root" ".gitignore" "README.md")"
  arts="$(jq -c --argjson lic "$(printf '%s\n' "${license_arts[@]}" | jq -cs '.')" \
    '[.[0]] + $lic + [.[1]]' <<<"$arts")"
  present="$(jq -c 'all(.[]; .present)' <<<"$arts")"
  local repo_rq=false
  [[ $license_present == false ]] && repo_rq=true
  rows+=("$(__cog_bootstrap_audit_domain repo "$present" "$repo_rq" "gitignore + license + readme" "$arts")")

  # governance: CLAUDE.md + AGENTS.md are the deliverable set. AGENTS.md is the
  # single source of truth, while CLAUDE.md must remain the exact thin
  # `@AGENTS.md` pointer. A present domain's AGENTS.md must still carry the
  # self-containment principle (the tailor-surviving `self-contained` token).
  arts="$(__cog_bootstrap_audit_artifacts "$project_root" "CLAUDE.md" "AGENTS.md")"
  present="$(jq -c 'all(.[]; .present)' <<<"$arts")"
  local gov_reqs='[]'
  if [[ $present == true ]]; then
    gov_reqs="[$(__cog_bootstrap_audit_req self-containment-principle \
      "$(__cog_bootstrap_audit_file_has "$project_root" "AGENTS.md" "self-contained")"),
      $(__cog_bootstrap_audit_req claude-agents-pointer \
        "$(__cog_bootstrap_audit_file_exact "$project_root" "CLAUDE.md" $'@AGENTS.md\n')")]"
  fi
  rows+=("$(__cog_bootstrap_audit_domain governance "$present" false "governance docs" "$arts" "$gov_reqs")")

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

  # taskrunner: any justfile filename variant satisfies the domain. Report a
  # single runner artifact named for whichever variant exists (default justfile)
  # so the breakdown reads as one deliverable.
  local runner="" cand
  while IFS= read -r cand; do
    if [[ -e "$project_root/$cand" ]]; then
      runner="$cand"
      break
    fi
  done < <(cog::fn::template::justfile_names)
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
