# shellcheck shell=bash

cog::fn::parse_globals() {
  local -n __ctx="$1"
  local -n __argv="$2"
  shift 2

  # The keys below are associative-array elements of the $1 nameref, not bare
  # variables; shellcheck misreads them as unassigned references (SC2154) and
  # flags the intentional empty-string defaults (SC2192).
  # shellcheck disable=SC2154,SC2192
  __ctx=(
    [verbosity]=0
    [log_level]=warn
    [json]=false
    [dry_run]=false
    [print_config]=false
    [help]=false
    [version]=false
    [subcommand]=
    [cli_set_json]=false
    [cli_set_dry_run]=false
    [cli_set_log_level]=false
    [cli_log_level_flag]=
  )
  __argv=()

  local verbosity=0
  local tok

  while (($# > 0)); do
    tok="$1"
    case "$tok" in
      --help | -h)
        __ctx[help]=true
        shift
        ;;
      --version | -V)
        __ctx[version]=true
        shift
        ;;
      --json)
        __ctx[json]=true
        __ctx[cli_set_json]=true
        shift
        ;;
      --dry-run)
        __ctx[dry_run]=true
        __ctx[cli_set_dry_run]=true
        shift
        ;;
      --print-config)
        __ctx[print_config]=true
        shift
        ;;
      -v | -vv | -vvv)
        verbosity=$((verbosity + ${#tok} - 1))
        __ctx[cli_set_log_level]=true
        __ctx[cli_log_level_flag]="$tok"
        shift
        ;;
      --)
        shift
        if (($# > 0)); then
          __ctx[subcommand]="$1"
          shift
          __argv=("$@")
        fi
        break
        ;;
      -*)
        cog::helpers::die "$EX_USAGE" "UnknownGlobalFlag" \
          "unknown global flag" "flag: ${tok}" "" "run 'cog --help'"
        ;;
      *)
        __ctx[subcommand]="$tok"
        shift
        __argv=("$@")
        break
        ;;
    esac
  done

  __ctx[verbosity]="$verbosity"
  case "$verbosity" in
    0)
      __ctx[log_level]=warn
      ;;
    1)
      __ctx[log_level]=info
      ;;
    2)
      __ctx[log_level]=debug
      ;;
    *)
      __ctx[log_level]=trace
      ;;
  esac
}
