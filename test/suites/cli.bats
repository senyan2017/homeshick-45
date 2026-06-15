#!/usr/bin/env bats

# Characterization tests for the homeshick entry layer (bin/homeshick).
#
# These pin down the behaviour of the command-line front-end itself:
# global option parsing, combined short options, subcommand/alias
# resolution, per-command argument collection, the "operate on every
# castle" default and exit-status reporting. They intentionally assert on
# observable behaviour (exit status and output) rather than internals, so
# the entry layer can be refactored freely as long as the CLI contract holds.

load ../helper.sh

setup() {
  create_test_dir
  # shellcheck source=../../homeshick.sh
  source "$HOMESHICK_DIR/homeshick.sh"
}

teardown() {
  delete_test_dir
}

# --- Unknown input -----------------------------------------------------------

@test 'cli: unknown command exits with EX_USAGE' {
  run homeshick boguscommand
  [ "$status" -eq 64 ]
}

@test 'cli: unknown option exits with EX_USAGE' {
  run homeshick --definitely-not-an-option
  [ "$status" -eq 64 ]
}

# --- help / usage ------------------------------------------------------------

@test 'cli: bare invocation prints usage' {
  run homeshick
  [ "$status" -eq 0 ]
  [[ $output == *'Usage: homeshick'* ]]
}

@test 'cli: -h prints usage' {
  run homeshick -h
  [ "$status" -eq 0 ]
  [[ $output == *'Usage: homeshick'* ]]
}

@test 'cli: --help prints usage' {
  run homeshick --help
  [ "$status" -eq 0 ]
  [[ $output == *'Usage: homeshick'* ]]
}

@test 'cli: help TASK prints task-specific usage' {
  run homeshick help clone
  [ "$status" -eq 0 ]
  [[ $output == *'clone'* ]]
}

# --- combined short options --------------------------------------------------

@test 'cli: combined short options are split (-qv)' {
  castle 'rc-files'
  # -q (quiet) + -v (verbose); quiet wins, so the only proof the cluster was
  # understood is that it does NOT fail as an unknown option.
  run homeshick -qv link rc-files
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test 'cli: combined short options are order independent (-vq)' {
  castle 'rc-files'
  run homeshick -vq link rc-files
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- option position ---------------------------------------------------------

@test 'cli: global option before the subcommand is honoured' {
  castle 'rc-files'
  run homeshick -q link rc-files
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test 'cli: option after the subcommand is honoured' {
  castle 'rc-files'
  run homeshick link -q rc-files
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- aliases -----------------------------------------------------------------

@test 'cli: ls is an alias for list' {
  castle 'rc-files'
  run homeshick ls
  [ "$status" -eq 0 ]
  [[ $output == *'rc-files'* ]]
}

@test 'cli: updates routes to the check implementation' {
  run homeshick updates nonexistent
  local updates_status=$status
  run homeshick check nonexistent
  [ "$updates_status" -eq "$status" ]
  [ "$status" -eq 1 ]
}

@test 'cli: symlink routes to the link implementation' {
  run homeshick symlink nonexistent
  local symlink_status=$status
  run homeshick link nonexistent
  [ "$symlink_status" -eq "$status" ]
  [ "$status" -eq 1 ]
}

# --- argument-count rules ----------------------------------------------------

@test 'cli: list rejects positional arguments' {
  run homeshick list extra
  [ "$status" -eq 64 ]
}

@test 'cli: ls rejects positional arguments' {
  run homeshick ls extra
  [ "$status" -eq 64 ]
}

@test 'cli: clone without arguments shows its usage' {
  run homeshick clone
  [ "$status" -eq 0 ]
  [[ $output == *'clone'* ]]
}

@test 'cli: generate without arguments shows its usage' {
  run homeshick generate
  [ "$status" -eq 0 ]
  [[ $output == *'generate'* ]]
}

@test 'cli: track without arguments shows its usage' {
  run homeshick track
  [ "$status" -eq 0 ]
  [[ $output == *'track'* ]]
}

@test 'cli: cd without arguments shows its usage' {
  run homeshick cd
  [ "$status" -eq 0 ]
  [[ $output == *'castle'* ]]
}

@test 'cli: cd with an argument via bin exits cleanly' {
  # The cd subcommand cannot change the parent shell from a subprocess, so the
  # binary just prints help. Invoked directly (not via the shell function).
  run "$HOMESHICK_DIR/bin/homeshick" cd somecastle
  [ "$status" -eq 0 ]
}

# --- operate-on-every-castle default ----------------------------------------

@test 'cli: check without arguments iterates every castle' {
  castle 'rc-files'
  castle 'dotfiles'
  run homeshick check
  [ "$status" -eq 0 ]
  [[ $output == *'rc-files'* ]]
  [[ $output == *'dotfiles'* ]]
}

# --- per-command leading argument (refresh DAYS) -----------------------------

@test 'cli: refresh treats the first argument as DAYS, not a castle' {
  castle 'rc-files'
  run homeshick -b refresh 7 rc-files
  # "7" must be consumed as the day threshold; the castle that gets processed
  # is rc-files, never a bogus castle named "7".
  [[ $output == *'rc-files'* ]]
  [[ $output != *'refresh 7'* ]]
  [[ $output != *"Could not refresh 7"* ]]
}

@test 'cli: refresh treats a non-numeric first argument as a castle' {
  castle 'repo with spaces in name'
  # A castle name -- especially one with spaces -- must never reach the day-
  # threshold arithmetic; doing so aborts the parser with a shell arithmetic
  # error (the "<name> * 86400" expression). It has to be collected as a
  # castle and actually processed instead.
  run homeshick -b refresh 'repo with spaces in name'
  [[ $output != *'86400'* ]]
  [[ $output == *'repo with spaces in name'* ]]
}
