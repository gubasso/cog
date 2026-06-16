# shellcheck shell=bash
: 'desc: Show generated help for cog or a subcommand.'

cog::cmd::help() {
  case "$#" in
    0)
      cog::fn::help_generate root
      ;;
    1)
      cog::fn::help_generate command "$1"
      ;;
    *)
      cog::helpers::die "$EX_USAGE" "TooManyArguments" \
        "help takes at most one command name" "args: $*" "" \
        "run 'cog help' or 'cog help <command>'"
      ;;
  esac
}
