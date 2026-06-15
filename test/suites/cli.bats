#!/usr/bin/env bats

# test/suites/cli.bats — Tests for CLI parsing and dispatch.
#
# These tests protect the argument parsing logic in lib/cli.sh and the
# dispatch logic in lib/dispatch.sh. They ensure that:
#   - Global flags are parsed correctly (before and after subcommand)
#   - Combined short flags are expanded
#   - Subcommand identification works
#   - Command-specific argument routing is correct
#   - Default behaviors (no args → help, no castles → all castles) work
#   - Exit statuses are correct

load ../helper.sh

setup() {
  create_test_dir
  # shellcheck source=../../homeshick.sh
  source "$HOMESHICK_DIR/homeshick.sh"
}

teardown() {
  delete_test_dir
}

# ---------------------------------------------------------------------------
# Help / no-argument behavior
# ---------------------------------------------------------------------------

@test 'no arguments shows help and exits 0' {
  run homeshick
  [ $status -eq 0 ]
  [[ $output == *"Tasks:"* ]]
}

@test '--help shows help and exits 0' {
  run homeshick --help
  [ $status -eq 0 ]
  [[ $output == *"Tasks:"* ]]
}

@test '-h shows help and exits 0' {
  run homeshick -h
  [ $status -eq 0 ]
  [[ $output == *"Tasks:"* ]]
}

@test 'help subcommand shows help' {
  run homeshick help
  [ $status -eq 0 ]
  [[ $output == *"Tasks:"* ]]
}

@test 'help for specific subcommand' {
  run homeshick help clone
  [ $status -eq 0 ]
  [[ $output == *"Clones URI"* ]]
}

@test 'help via -h before subcommand shows help for that subcommand' {
  run homeshick -h pull
  [ $status -eq 0 ]
  [[ $output == *"Updates a castle"* ]]
}

# ---------------------------------------------------------------------------
# Unknown commands and options
# ---------------------------------------------------------------------------

@test 'unknown command exits with EX_USAGE' {
  run homeshick nonexistent
  [ $status -eq 64 ]
}

@test 'unknown flag before subcommand exits with EX_USAGE' {
  run homeshick --unknown-flag list
  [ $status -eq 64 ]
}

@test 'unknown flag after subcommand exits with EX_USAGE' {
  run homeshick list --unknown-flag
  [ $status -eq 64 ]
}

# ---------------------------------------------------------------------------
# Combined short flags
# ---------------------------------------------------------------------------

@test 'combined short flags -qb are expanded' {
  castle 'rc-files'
  # -q = quiet, -b = batch. Should run without interactive prompts and no output
  run homeshick -qb link rc-files
  [ $status -eq 0 ]
  # quiet mode: no status output
  [[ -z "$output" || ! "$output" == *"symlink"* ]]
}

@test 'combined short flags -bv are expanded' {
  castle 'symlinks'
  homeshick link symlinks
  run homeshick -bv link symlinks
  [ $status -eq 0 ]
  # -b batch + -v verbose: should show "identical" messages
  [[ $output == *"identical"* ]]
}

# ---------------------------------------------------------------------------
# Flags before and after subcommand
# ---------------------------------------------------------------------------

@test 'quiet flag before subcommand suppresses output' {
  castle 'rc-files'
  run homeshick --quiet link rc-files
  [ $status -eq 0 ]
  [[ -z "$output" ]]
}

@test 'quiet flag after subcommand suppresses output' {
  castle 'rc-files'
  run homeshick link --quiet rc-files
  [ $status -eq 0 ]
  [[ -z "$output" ]]
}

@test 'batch flag before subcommand' {
  castle 'rc-files'
  run homeshick --batch link rc-files
  [ $status -eq 0 ]
}

@test 'batch flag after subcommand' {
  castle 'rc-files'
  run homeshick link --batch rc-files
  [ $status -eq 0 ]
}

# ---------------------------------------------------------------------------
# Commands that reject arguments
# ---------------------------------------------------------------------------

@test 'list with arguments exits with EX_USAGE' {
  run homeshick list somearg
  [ $status -eq 64 ]
}

@test 'ls with arguments exits with EX_USAGE' {
  run homeshick ls somearg
  [ $status -eq 64 ]
}

# ---------------------------------------------------------------------------
# Commands that require arguments (redirect to help)
# ---------------------------------------------------------------------------

@test 'clone with no args shows help for clone' {
  run homeshick clone
  [ $status -eq 0 ]
  [[ $output == *"Clones URI"* ]] || [[ $output == *"clone"* ]]
}

@test 'generate with no args shows help for generate' {
  run homeshick generate
  [ $status -eq 0 ]
  [[ $output == *"generate"* ]] || [[ $output == *"Generates"* ]]
}

@test 'track with no args shows help for track' {
  run homeshick track
  [ $status -eq 0 ]
  [[ $output == *"track"* ]] || [[ $output == *"Adds a file"* ]]
}

# ---------------------------------------------------------------------------
# Refresh argument parsing (DAYS vs castle name)
# ---------------------------------------------------------------------------

@test 'refresh with numeric DAYS and castle name' {
  castle 'rc-files'
  homeshick pull rc-files
  run homeshick -b refresh 7 rc-files
  [ $status -eq 0 ]
}

@test 'refresh with only castle name (no DAYS) uses default threshold' {
  castle 'rc-files'
  homeshick pull rc-files  # creates FETCH_HEAD
  run homeshick -b refresh rc-files
  [ $status -eq 0 ]
}

@test 'refresh with castle name containing spaces (no DAYS)' {
  castle 'repo with spaces in name'
  homeshick pull "repo with spaces in name"  # creates FETCH_HEAD
  run homeshick -b refresh "repo with spaces in name"
  [ $status -eq 0 ]
}

# ---------------------------------------------------------------------------
# Batch expansion (no castle args → all castles)
# ---------------------------------------------------------------------------

@test 'check with no args runs on all castles' {
  castle 'rc-files'
  castle 'dotfiles'
  run homeshick -b check
  [ $status -eq 0 ]
  [[ $output == *"rc-files"* ]]
  [[ $output == *"dotfiles"* ]]
}

@test 'link with no args runs on all castles' {
  castle 'rc-files'
  castle 'dotfiles'
  run homeshick -b link
  [ $status -eq 0 ]
}

# ---------------------------------------------------------------------------
# Exit status aggregation
# ---------------------------------------------------------------------------

@test 'check exits with non-zero when castle is behind' {
  fixture 'rc-files'
  homeshick --batch clone "$REPO_FIXTURES/rc-files"
  # Modify the remote to create a "behind" state
  (cd "$REPO_FIXTURES/rc-files" && git commit --allow-empty -m "new commit")
  run homeshick check rc-files
  [ $status -ne 0 ]
}

@test 'link non-existent castle exits with EX_ERR' {
  run homeshick link nonexistent
  [ $status -eq 1 ]
}
