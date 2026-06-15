#!/usr/bin/env bats

# Regression tests for the exit-status & reporting contract:
# a multi-castle run must never *look* finished while a conflict or failure was
# silently left behind. See CONTRIBUTING.md "Exit status & reporting".

load ../helper.sh

# run --separate-stderr (used below) needs bats >= 1.5.0
bats_require_minimum_version 1.5.0

setup() {
  create_test_dir
  # shellcheck source=../../homeshick.sh
  source "$HOMESHICK_DIR/homeshick.sh"
}

teardown() {
  delete_test_dir
}

@test 'link with a conflict under --batch reports EX_CONFLICT and still links other files' {
  castle 'rc-files'
  touch "$HOME/.bashrc" # pre-existing real file -> conflict
  run homeshick --batch link rc-files
  [ "$status" -eq 89 ] # EX_CONFLICT
  # the conflicting file is left untouched (never overwritten without consent)
  [ -f "$HOME/.bashrc" ]
  [ ! -L "$HOME/.bashrc" ]
  # but the non-conflicting files in the same castle are still linked
  [ -L "$HOME/.gitignore" ]
}

@test 'link conflict under --quiet --batch stays silent on stdout but reports on stderr' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run --separate-stderr homeshick --quiet --batch link rc-files
  [ "$status" -eq 89 ] # EX_CONFLICT - the run is still flagged
  [ -z "$output" ]     # --quiet converges: nothing on stdout
  [ -n "$stderr" ]     # ... but the conflict that needs a human is not hidden
  echo "$stderr" | grep -q 'not overwritten'
}

@test 'link with --skip skips all existing files, exits 0 and stays quiet' {
  castle 'rc-files'
  # pre-create every tracked home entry so all of them are skipped
  touch "$HOME/.bashrc" "$HOME/symlinked-file" "$HOME/symlinked-directory" \
        "$HOME/dead-symlink" "$HOME/.gitignore"
  run --separate-stderr homeshick --quiet --skip link rc-files
  [ "$status" -eq 0 ] # --skip is a resolution, so this is a clean success
  [ -z "$output" ]    # --quiet -> no stdout
  [ -z "$stderr" ]    # nothing needed attention -> no stderr either
  # none of the existing files were replaced by a symlink
  [ ! -L "$HOME/.bashrc" ]
  [ ! -L "$HOME/.gitignore" ]
}

@test 'link aggregates an earlier success and a later conflict into a non-zero exit' {
  castle 'dotfiles'
  castle 'rc-files'
  touch "$HOME/.bashrc" # conflict in the second castle only
  run homeshick --batch link dotfiles rc-files
  [ "$status" -eq 89 ] # later conflict is not masked by the earlier success
  # the earlier castle was linked despite the later failure
  [ -L "$HOME/.ssh/known_hosts" ]
  # the second castle's conflicting file is left untouched
  [ -f "$HOME/.bashrc" ]
  [ ! -L "$HOME/.bashrc" ]
}

@test 'link with --force overwrites a conflict and exits 0' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick --batch --force link rc-files
  [ "$status" -eq 0 ]      # --force resolves the conflict
  [ -L "$HOME/.bashrc" ]   # the file was overwritten with the symlink
}

@test 'link links a valid castle even when a later castle does not exist' {
  castle 'rc-files'
  run homeshick --batch link rc-files nonexistent
  [ "$status" -eq 1 ]      # EX_ERR from the missing castle
  [ -L "$HOME/.bashrc" ]   # the valid castle was still linked first
}
