#!/usr/bin/env bash
#
# Command dispatch for homeshick.
#
# This file owns everything that happens *after* parsing: sourcing the right
# implementation, running it (once, or once per castle), running any follow-up
# step and folding the individual results into a single exit status.
#
# It reads the output-contract globals documented in parse.sh and the command
# registry (homeshick_command_spec) -- it never re-derives command behaviour on
# its own, so the registry stays the single source of truth.

# This file's whole purpose is to act on globals owned by bin/homeshick and the
# parser (cmd, params, spec_*, repos, exit_status, ...), which shellcheck cannot
# track across the source boundary.
# shellcheck disable=SC2154

# Source the implementation file for the resolved command, if it has one.
homeshick_load_command() {
  [[ $spec_canonical ]] || return 0
  # The path is built from the registry, not user input.
  # shellcheck disable=SC1090
  source "$homeshick/lib/commands/$spec_canonical.sh"
}

# Fold a single command result into the overall exit status, matching the
# long-standing rules: a usage error aborts immediately, otherwise the first
# non-zero result is the one that sticks.
homeshick_record_result() {
  local result=$1
  if [[ $result == "$EX_USAGE" ]]; then
    exit "$EX_USAGE"
  fi
  if [[ $exit_status == 0 && $result != 0 ]]; then
    exit_status=$result
  fi
}

# Pull a single castle, remembering the ones whose HEAD actually moved so that
# only those get re-symlinked afterwards.
homeshick_pull_one() {
  local castle=$1
  local prev_hash curr_hash result
  prev_hash=$(cd "$repos/$castle" && git rev-parse HEAD -- 2>/dev/null)
  (pull "$castle")
  result=$?
  if [[ $result -eq 0 ]]; then
    curr_hash=$(cd "$repos/$castle" && git rev-parse HEAD --)
    [[ $prev_hash != "$curr_hash" ]] && pull_completed+=("$castle")
  fi
  return "$result"
}

# Run the command once per positional argument and aggregate the results.
homeshick_run_each() {
  local param result
  # Consumed by homeshick_pull_one and homeshick_run_post via dynamic scope.
  pull_completed=()
  for param in "${params[@]}"; do
    case $spec_invoke in
      each-pull)
        homeshick_pull_one "$param" ;;
      each-refresh)
        ("$spec_function" "$threshhold" "$param") ;;
      each-track)
        "$spec_function" "$castle" "$param" ;;
      each)
        if [[ $spec_subshell == yes ]]; then
          ("$spec_function" "$param")
        else
          "$spec_function" "$param"
        fi ;;
    esac
    result=$?
    homeshick_record_result "$result"
  done
  homeshick_run_post
}

# Run the command's follow-up step, if any, and fold its result in too.
homeshick_run_post() {
  [[ $spec_post ]] || return 0
  local result
  case $spec_post in
    pull_outdated)
      pull_outdated "$threshhold" "${params[@]}" ;;
    symlink_new_files)
      symlink_new_files "${pull_completed[@]}" ;;
    symlink_cloned_files)
      symlink_cloned_files "${params[@]}" ;;
  esac
  result=$?
  if [[ $exit_status == 0 && $result != 0 ]]; then
    exit_status=$result
  fi
}

# Entry point for the dispatcher. Resolves the final command's spec, loads its
# implementation and hands off to the matching invocation style.
homeshick_run() {
  homeshick_command_spec "$cmd"
  homeshick_load_command
  case $spec_invoke in
    cd)
      # cd is realised by the shell wrapper; the binary can only show help.
      help cd ;;
    help)
      help "$help_cmd" ;;
    once)
      "$spec_function" ;;
    *)
      homeshick_run_each ;;
  esac
}
