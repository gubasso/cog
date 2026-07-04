# Bash completion for cog.
#
# The command list is static and mirrors:
#   find lib/commands -maxdepth 1 -name 'cmd_*.sh' | sort | sed 's#.*/cmd_##; s#\.sh$##; s#_#-#g'
# Per-command option completion is intentionally deferred because command
# metadata currently exposes command names and desc sentinels, not option specs.

_cog() {
  local cur prev word
  local subcommand_seen=false
  local -a global_flags=(
    -h
    --help
    -V
    --version
    --json
    --dry-run
    --print-config
    -v
    -vv
    -vvv
  )
  local -a commands=(
    assess-input
    bootstrap-audit
    bootstrap-template-review
    ci-apply
    ci-detect
    classify-project
    claudemd-audit
    codex-runner
    cog-skill-creator-scaffold
    cog-skill-creator-validate
    context-brief
    digest-check
    digest-stamp
    doctor
    editorconfig-apply
    editorconfig-detect
    executor
    executor-prex-parse-args
    gate
    gc-classify-failure
    gc-commit
    gc-commit-lint
    gc-loop-progress
    gc-plan
    gc-push
    gc-stage
    gitignore-apply
    gitignore-detect
    help
    hook-guard
    init
    jira-ticket-creator
    license-apply
    lint-codex-wrapper
    lock
    longrun
    match-telemetry
    msg
    nix-devshell-apply
    nix-devshell-detect
    noop
    osc-preflight
    osc-probe-binary
    plan
    plan-builder-to-queue-setup
    plan-complexity
    plan-doc
    plan-init
    plan-multi-setup
    plan-review
    plan-slug
    power-grade
    precommit-apply-template
    precommit-detect
    preflight
    print-config
    queue-append
    queue-bootstrap
    queue-deps-set
    queue-graph-check
    queue-prompt-set
    queue-reorder
    queue-select
    queue-status-set
    readme-apply
    refactor-scan-drift
    refactor-scan-source
    refactor-setup
    require
    research-shelf
    review-comment
    review-init
    review-loop-input
    review-loop-progress
    review-loop-summary
    review-normalize-findings
    review-plan-multi-setup
    review-queue-rounds-scan
    review-queue-rounds-verify
    review-scope
    review-tech-scope
    review-validate-findings
    round-prompt
    round-req
    round-split
    rundir
    runner-all-setup
    runner-commit-parse
    runner-plan-setup
    skill-class
    skill-lint
    skill-refs
    suckless-apply
    suckless-conflicts
    suckless-preflight
    taskrunner-apply
    taskrunner-detect
    test-review-discover
    test-review-lint
    test-review-manifest
    tracking-scan
  )

  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  for word in "${COMP_WORDS[@]:1:COMP_CWORD-1}"; do
    [[ $word == -- ]] && break
    [[ $word == -* ]] && continue
    subcommand_seen=true
    break
  done

  if [[ $cur == -* ]]; then
    COMPREPLY=($(compgen -W "${global_flags[*]}" -- "$cur"))
    return 0
  fi

  if [[ $subcommand_seen == false ]]; then
    COMPREPLY=($(compgen -W "${commands[*]}" -- "$cur"))
    return 0
  fi

  case "$prev" in
    help)
      COMPREPLY=($(compgen -W "${commands[*]}" -- "$cur"))
      ;;
    *)
      COMPREPLY=($(compgen -W "--help ${global_flags[*]}" -- "$cur"))
      ;;
  esac
  return 0
}

complete -F _cog cog
