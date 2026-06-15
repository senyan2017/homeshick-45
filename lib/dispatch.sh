#!/usr/bin/env bash

# lib/dispatch.sh — Command loading, dispatch, and exit status aggregation.
#
# Responsibilities:
#   1. Source the implementation file for the resolved subcommand
#   2. Invoke the command function for each collected parameter
#   3. Aggregate exit statuses across iterations
#   4. Run post-command hooks (symlink after clone, pull_outdated after refresh, etc.)
#
# This module expects the following globals to be set by lib/cli.sh:
#   cmd, params, threshhold, castle, help_cmd, exit_status
#
# It also relies on:
#   homeshick  — base directory (for sourcing command files)
#   repos      — castle repos directory
#   EX_*       — exit status constants from lib/exit_status.sh

# ---------------------------------------------------------------------------
# hs_load_command
#
# Sources the implementation file for the current `$cmd`.
# Alias mapping:
#   symlink → link.sh
#   updates → check.sh
#   ls      → list.sh
#   cd      → (no file; implemented by the shell wrapper)
# ---------------------------------------------------------------------------
hs_load_command() {
  case $cmd in
    cd)
      # cd is implemented in homeshick.{sh,csh,fish}; nothing to load
      ;;
    symlink)
      # shellcheck source=commands/link.sh
      source "$homeshick/lib/commands/link.sh"
      ;;
    updates)
      # shellcheck source=commands/check.sh
      source "$homeshick/lib/commands/check.sh"
      ;;
    ls)
      # shellcheck source=commands/list.sh
      source "$homeshick/lib/commands/list.sh"
      ;;
    *)
      # shellcheck disable=SC1090
      source "$homeshick/lib/commands/$cmd.sh"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# hs_update_exit_status RESULT
#
# Merge a per-iteration result into the global exit_status.
# EX_USAGE causes an immediate exit (invalid usage should abort).
# ---------------------------------------------------------------------------
hs_update_exit_status() {
  local result=$1
  if [[ $result -eq $EX_USAGE ]]; then
    exit "$EX_USAGE"
  fi
  if [[ $exit_status -eq 0 && $result -ne 0 ]]; then
    exit_status=$result
  fi
}

# ---------------------------------------------------------------------------
# hs_dispatch
#
# Top-level dispatch entry point. Called from bin/homeshick after
# hs_parse_args and hs_load_command have run.
#
# Reads globals: cmd, params, threshhold, castle, help_cmd, exit_status
# Writes: exit_status (aggregated)
# ---------------------------------------------------------------------------
hs_dispatch() {
  # --- Special commands that don't iterate over params ---
  case $cmd in
    list | ls)
      list
      return $?
      ;;
    cd)
      # cd is implemented by the shell wrapper; just show help
      help cd
      return $?
      ;;
    help)
      # shellcheck disable=SC2086
      help $help_cmd
      return $?
      ;;
  esac

  # --- Iterate over params ---
  local pull_completed=()

  for param in "${params[@]}"; do
    case $cmd in
      clone)
        clone "$param"
        ;;
      generate)
        generate "$param"
        ;;
      check | updates)
        # Run in a subshell to isolate side-effects
        (check "$param")
        ;;
      refresh)
        # Run in a subshell to isolate side-effects
        # shellcheck disable=SC2086
        (refresh $threshhold "$param")
        ;;
      pull)
        local prev_hash
        prev_hash=$(cd "$repos/$param" && git rev-parse HEAD -- 2>/dev/null)
        (pull "$param")
        local pull_result=$?
        if [[ $pull_result -eq 0 ]]; then
          local curr_hash
          curr_hash=$(cd "$repos/$param" && git rev-parse HEAD --)
          [[ "$prev_hash" != "$curr_hash" ]] && pull_completed+=("$param")
        fi
        (exit $pull_result)
        ;;
      symlink | link)
        symlink "$param"
        ;;
      track)
        track "$castle" "$param"
        ;;
    esac
    local result=$?
    hs_update_exit_status "$result"
  done

  # --- Post-loop actions ---
  local post_result=0
  case $cmd in
    clone)
      symlink_cloned_files "${params[@]}"
      post_result=$?
      ;;
    refresh)
      pull_outdated "$threshhold" "${params[@]}"
      post_result=$?
      ;;
    pull)
      symlink_new_files "${pull_completed[@]}"
      post_result=$?
      ;;
  esac

  if [[ $exit_status -eq 0 && $post_result -ne 0 ]]; then
    exit_status=$post_result
  fi
}
