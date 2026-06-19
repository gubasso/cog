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
    digest-check
    digest-stamp
    doctor
    gc-classify-failure
    gc-commit
    gc-plan
    gc-push
    gc-stage
    help
    hook-guard
    init
    lint-codex-wrapper
    lock
    msg
    noop
    osc-preflight
    osc-probe-binary
    plan-init
    plan-slug
    plan-writer-multi-setup
    precommit-apply-template
    precommit-detect
    preflight
    prex-parse-args
    prex-tsk-resolve
    print-config
    queue-append
    queue-bootstrap
    queue-deps-set
    queue-graph-check
    queue-reorder
    queue-select
    queue-status-set
    refactor-scan-drift
    refactor-scan-source
    refactor-setup
    require
    review-agents-finalize
    review-cli-signals
    review-implementation-plans-scan
    review-implementation-plans-verify
    review-init
    review-refs
    review-scope
    review-validate-findings
    rundir
    runner-queue-parse-commit
    runner-queue-resolve-plan
    runner-queue-setup
    skill-builder-scaffold
    skill-builder-validate
    skill-lint
    suckless-apply
    suckless-conflicts
    suckless-preflight
    test-review-discover
    test-review-lint
    test-review-manifest
    tsk-fetch-issue
    tsk-snapshot
    tsk-store-init
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
