#!/usr/bin/env bash

# lib/cli.sh — Centralized CLI parsing for homeshick.
#
# Responsibilities:
#   1. Expand combined short flags (e.g. -qb → -q -b)
#   2. Parse global flags (--quiet, --skip, --force, --batch, --verbose, --help)
#   3. Identify the subcommand
#   4. Collect positional arguments with command-specific rules
#   5. Apply defaults (expand empty castle lists, default threshold)
#
# After hs_parse_args returns, the following globals are set:
#   cmd         — the resolved subcommand name
#   params      — array of positional arguments for the command
#   threshhold  — seconds (only meaningful for refresh)
#   castle      — castle name (only meaningful for track)
#   help_cmd    — subcommand to show help for (only meaningful when cmd=help)
#   exit_status — may be set to EX_USAGE when redirecting to help
#
# Globals consumed (must be set before calling hs_parse_args):
#   TALK, SKIP, FORCE, BATCH, VERBOSE — flag targets, initialized by the caller

# All recognized subcommands.
HS_VALID_COMMANDS=(cd clone generate list ls check updates refresh pull symlink link track help)

# Commands that accept batch castle expansion (run on all castles when no args given).
HS_BATCH_COMMANDS=(check updates refresh pull symlink link)

# Commands that require at least one argument; redirect to help otherwise.
HS_REQUIRED_COMMANDS=(cd clone generate track)

# ---------------------------------------------------------------------------
# hs_try_expand_combined FLAG_TOKEN
#
# If FLAG_TOKEN is a combined short flag like "-qb", splits it in-place
# by prepending the two halves to the positional parameters ($@).
#
# Usage:
#   if hs_try_expand_combined "$1"; then
#     shift  # remove original token, expanded parts are now in $1 $2
#   fi
#
# Returns 0 if expansion was performed, 1 otherwise.
# ---------------------------------------------------------------------------
hs_try_expand_combined() {
  local token="$1"
  if [[ $token =~ ^-[a-z]{2,} ]]; then
    # shellcheck disable=SC2034
    __hs_expanded_first="${token:0:2}"
    __hs_expanded_rest="-${token:2}"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# hs_parse_flag TOKEN
#
# If TOKEN is a recognized global flag, apply its side-effect and return 0.
# If TOKEN starts with "-" but is unknown, exit with EX_USAGE.
# If TOKEN is not a flag at all, return 1.
# ---------------------------------------------------------------------------
hs_parse_flag() {
  local token="$1"
  [[ $token =~ ^- ]] || return 1

  case $token in
    -h | --help)    cmd="help" ;;
    -q | --quiet)   TALK=false ;;
    -s | --skip)    SKIP=true ;;
    -f | --force)   FORCE=true ;;
    -b | --batch)   BATCH=true ;;
    -v | --verbose) VERBOSE=true ;;
    *)              err "$EX_USAGE" "Unknown option '$token'" ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# hs_apply_defaults
#
# After argument collection, fill in defaults:
#   - Commands that operate on castles get all castles when none specified.
#   - Commands that require arguments redirect to help.
#   - refresh gets a default threshold of 7 days.
# ---------------------------------------------------------------------------
hs_apply_defaults() {
  # Default: expand to all castles when params is empty
  if [[ ${#params[@]} -eq 0 ]]; then
    local is_batch=false
    local bc
    for bc in "${HS_BATCH_COMMANDS[@]}"; do
      [[ $bc == "$cmd" ]] && is_batch=true && break
    done
    if $is_batch; then
      while IFS= read -d $'\n' -r name; do
        params+=("$name")
      done < <(list_castle_names)
    fi

    local is_required=false
    local rc
    for rc in "${HS_REQUIRED_COMMANDS[@]}"; do
      [[ $rc == "$cmd" ]] && is_required=true && break
    done
    if $is_required; then
      help_cmd="$cmd"
      cmd="help"
      exit_status=$EX_USAGE
    fi
  fi

  # Default threshold for refresh: 7 days
  [[ ! $threshhold ]] && threshhold=$((7 * 86400))
}

# ---------------------------------------------------------------------------
# hs_parse_args ARGS...
#
# Main entry point for CLI parsing. Called from bin/homeshick with the
# full argument list.
#
# Parsing happens in three phases:
#   Phase 1 — consume leading flags (before the subcommand token)
#   Phase 2 — identify the subcommand
#   Phase 3 — collect remaining args (flags still accepted here for
#             backward compatibility)
#
# Sets: cmd, params, threshhold, castle, help_cmd, exit_status.
# ---------------------------------------------------------------------------
hs_parse_args() {
  cmd=""
  params=()
  threshhold=""
  castle=""
  help_cmd=""

  # ---- Phase 1: leading flags ----
  while [[ $# -gt 0 ]]; do
    if [[ $1 =~ ^- ]]; then
      # Expand combined short flags (e.g. -qb → -q -b)
      if hs_try_expand_combined "$1"; then
        shift
        set -- "$__hs_expanded_first" "$__hs_expanded_rest" "$@"
        continue
      fi

      if hs_parse_flag "$1"; then
        shift; continue
      fi
    else
      break
    fi
  done

  # No arguments at all → show help
  [[ $# -gt 0 ]] || cmd="help"

  # ---- Phase 2: identify subcommand ----
  if [[ ! $cmd ]]; then
    local token="$1"; shift
    local found=false
    local vc
    for vc in "${HS_VALID_COMMANDS[@]}"; do
      if [[ $vc == "$token" ]]; then
        found=true; break
      fi
    done
    if $found; then
      cmd="$token"
    else
      err "$EX_USAGE" "Unknown command '$token'"
    fi
  fi

  # ---- Phase 3: collect remaining arguments ----
  while [[ $# -gt 0 ]]; do
    # Flag expansion (flags are accepted after the subcommand too)
    if [[ $1 =~ ^- ]]; then
      if hs_try_expand_combined "$1"; then
        shift
        set -- "$__hs_expanded_first" "$__hs_expanded_rest" "$@"
        continue
      fi

      if hs_parse_flag "$1"; then
        shift; continue
      fi
    fi

    # Command-specific argument routing
    case $cmd in
      cd | clone | generate | check | updates | pull | symlink | link)
        params+=("$1")
        ;;
      refresh)
        # First positional arg is DAYS only if it looks like a positive integer.
        # Otherwise it is a castle name (the original code relied on arithmetic
        # failure + short-circuit; we check explicitly for clarity).
        if [[ ! $threshhold && $1 =~ ^[0-9]+$ ]]; then
          threshhold=$(( $1 * 86400 ))
        else
          params+=("$1")
        fi
        ;;
      track)
        if [[ ! $castle ]]; then
          castle="$1"
        else
          params+=("$1")
        fi
        ;;
      list | ls)
        err "$EX_USAGE" "The '$1' command does not take any arguments"
        ;;
      help)
        if [[ ! $help_cmd ]]; then
          help_cmd="$1"
        fi
        ;;
      *)
        err "$EX_USAGE" "Unknown command '$cmd'"
        ;;
    esac
    shift
  done

  # ---- Defaults ----
  hs_apply_defaults
}
