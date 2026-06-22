# shellcheck shell=bash

cog::fn::review::normalize_headline() {
  local headline="${1:-}"
  # Trim leading/trailing whitespace and collapse all internal whitespace,
  # including embedded newlines, so the key reflects the entire headline.
  printf '%s' "$headline" | tr '\n' ' ' | awk '{$1=$1; print}'
}

cog::fn::review::finding_key() {
  local file="${1:-}" line_start="${2:-}" headline="${3:-}"
  local normalized_headline
  normalized_headline="$(cog::fn::review::normalize_headline "$headline")"
  printf '%s\t%s\t%s' "$file" "$line_start" "$normalized_headline" | sha256sum | awk '{print $1}'
}

cog::fn::review::severity_rank() {
  case "${1:-}" in
    blocking) printf '%s\n' 50 ;;
    important) printf '%s\n' 40 ;;
    nit) printf '%s\n' 30 ;;
    suggestion) printf '%s\n' 20 ;;
    question) printf '%s\n' 10 ;;
    praise) printf '%s\n' 0 ;;
    *) return 1 ;;
  esac
}
