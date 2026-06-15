#!/usr/bin/env bash

# Define some colors
txtdef="\e[0m"    # Revert to default
bldred="\e[1;31m" # Red - error
bldgrn="\e[1;32m" # Green - success
bldylw="\e[1;33m" # Yellow - warning
bldblu="\e[1;34m" # Blue - no action/ignored
bldcyn="\e[1;36m" # Cyan - pending action
bldwht="\e[1;37m" # White - info

err() {
  local exit_status=$1
  local reason="$2"
  shift 2
  if [[ $pending_status ]]; then
    # no args for fail
    # shellcheck disable=SC2119
    fail
  fi
  status "$bldred" "error" "$reason" >&2
  if [[ $# -gt 0 ]]; then
    printf "%s\n" "$@" >&2
  fi
  exit "$exit_status"
}

help_err() {
  # shellcheck source=commands/help.sh disable=SC2154
  source "$homeshick/lib/commands/help.sh"
  extended_help "$1"
  exit "$EX_USAGE"
}

status() {
  if $TALK; then
    printf "$1%13s$txtdef %s\n" "$2" "$3"
  fi
}

warn() {
  status "$bldylw" "$1" "$2"
}

info() {
  status "$bldwht" "$1" "$2"
}

pending_status=''
pending_message=''
pending() {
  pending_status="$1"
  pending_message="$2"
  if $TALK; then
    printf "$bldcyn%13s$txtdef %s" "$pending_status" "$pending_message"
  fi
}

# fail is used globally
# shellcheck disable=SC2120
fail() {
  [[ $1 ]] && pending_status=$1
  [[ $2 ]] && pending_message=$2
  status "\r$bldred" "$pending_status" "$pending_message"
  unset pending_status pending_message
}

ignore() {
  [[ $1 ]] && pending_status=$1
  [[ $2 ]] && pending_message=$2
  status "\r$bldblu" "$pending_status" "$pending_message"
  unset pending_status pending_message
}

success() {
  [[ $1 ]] && pending_status=$1
  [[ $2 ]] && pending_message=$2
  status "\r$bldgrn" "$pending_status" "$pending_message"
  unset pending_status pending_message
}

# Counters tallied while running in dry-run mode, summarized by dry_run_summary.
# These are reset on every invocation because log.sh is sourced anew each time.
dry_run_add=0
dry_run_clone=0
dry_run_modify=0
dry_run_conflict=0
dry_run_identical=0
dry_run_skip=0

# Print a single line describing an action that *would* be taken, without
# taking it. Colors mirror the regular status output so a dry run reads the
# same way a real run does:
#   new/directory -> green (a file or directory would be created)
#   clone         -> green (a castle would be cloned)
#   overwrite     -> yellow (an existing file would be replaced)
#   relink        -> yellow (a symlink would be rewritten)
#   conflict      -> yellow (an existing file is in the way, needs confirmation)
#   identical     -> blue   (already in place, nothing to do)
#   skip          -> blue   (left untouched on purpose)
dry_run() {
  local label=$1
  local message=$2
  local color
  case $label in
    new|directory) color=$bldgrn; dry_run_add=$((dry_run_add+1)) ;;
    clone)         color=$bldgrn; dry_run_clone=$((dry_run_clone+1)) ;;
    overwrite|relink) color=$bldylw; dry_run_modify=$((dry_run_modify+1)) ;;
    conflict)      color=$bldylw; dry_run_conflict=$((dry_run_conflict+1)) ;;
    identical)     color=$bldblu; dry_run_identical=$((dry_run_identical+1)) ;;
    skip)          color=$bldblu; dry_run_skip=$((dry_run_skip+1)) ;;
    *)             color=$bldcyn ;;
  esac
  status "$color" "$label" "$message"
}

# Print a one-line tally of everything a dry run would have done, so a change
# plan can be eyeballed at a glance before committing to a real run.
dry_run_summary() {
  local parts=()
  [[ $dry_run_clone     -gt 0 ]] && parts+=("$dry_run_clone to clone")
  [[ $dry_run_add       -gt 0 ]] && parts+=("$dry_run_add to add")
  [[ $dry_run_modify    -gt 0 ]] && parts+=("$dry_run_modify to overwrite")
  [[ $dry_run_conflict  -gt 0 ]] && parts+=("$dry_run_conflict in conflict")
  [[ $dry_run_identical -gt 0 ]] && parts+=("$dry_run_identical identical")
  [[ $dry_run_skip      -gt 0 ]] && parts+=("$dry_run_skip skipped")

  local msg=""
  local part
  for part in "${parts[@]}"; do
    [[ -n $msg ]] && msg="$msg, "
    msg="$msg$part"
  done
  if [[ -z $msg ]]; then
    msg="no changes - everything is already in place"
  fi
  info 'dry run' "$msg (nothing was modified)"
}
