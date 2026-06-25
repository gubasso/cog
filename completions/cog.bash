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
    classify-project
    claudemd-audit
    codex-runner
    cog-skill-creator-scaffold
    cog-skill-creator-validate
    digest-check
    digest-stamp
    doctor
    editorconfig-apply
    editorconfig-detect
    executor
    executor-prex-parse-args
    gc-classify-failure
    gc-commit
    gc-commit-lint
    gc-plan
    gc-push
    gc-stage
    help
    hook-guard
    init
    lint-codex-wrapper
    lock
    longrun
    msg
    noop
    osc-preflight
    osc-probe-binary
    plan-doc
    plan-init
    plan-multi-setup
    plan-review
    plan-slug
    plan-writer-multi-setup
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
    review-plan-implementation-scan
    review-plan-implementation-verify
    review-plan-multi-setup
    review-scope
    review-tech-scope
    review-validate-findings
    rundir
    runner-all-setup
    runner-commit-parse
    runner-plan-setup
    skill-lint
    skill-refs
    suckless-apply
    suckless-conflicts
    suckless-preflight
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
