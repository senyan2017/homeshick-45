#!/usr/bin/env bats

load ../helper.sh

setup() {
  create_test_dir
  # shellcheck source=../../homeshick.sh
  source "$HOMESHICK_DIR/homeshick.sh"
}

teardown() {
  delete_test_dir
}

# =============================================================================
# Clone dry-run tests
# =============================================================================

@test 'dry-run clone shows target path without cloning' {
  fixture 'rc-files'
  run homeshick --dry-run clone "$REPO_FIXTURES/rc-files"
  assert_success
  assert_output -p 'clone'
  assert_output -p 'rc-files'
  # The repo directory should NOT have been created
  [ ! -d "$HOME/.homesick/repos/rc-files" ]
}

@test 'dry-run clone shows skip message for existing castle' {
  castle 'rc-files'
  run homeshick --dry-run clone "$REPO_FIXTURES/rc-files"
  assert_success
  assert_output -p 'would skip'
  assert_output -p 'already exists'
}

@test 'dry-run clone with github shorthand' {
  run homeshick --dry-run clone andsens/rc-files
  assert_success
  assert_output -p 'https://github.com/andsens/rc-files.git'
  [ ! -d "$HOME/.homesick/repos/rc-files" ]
}

# =============================================================================
# Link dry-run tests - core safety: no files should be modified
# =============================================================================

@test 'dry-run link does not create any symlinks' {
  castle 'rc-files'
  run homeshick --dry-run --batch link rc-files
  assert_success
  # None of the files should actually exist
  [ ! -e "$HOME/.bashrc" ]
  [ ! -e "$HOME/symlinked-file" ]
  [ ! -e "$HOME/symlinked-directory" ]
  [ ! -e "$HOME/dead-symlink" ]
  [ ! -e "$HOME/.gitignore" ]
}

@test 'dry-run link does not create any directories' {
  castle 'dotfiles'
  run homeshick --dry-run --batch link dotfiles
  assert_success
  # .ssh should not have been created as a directory
  [ ! -e "$HOME/.ssh" ]
  [ ! -e "$HOME/.config" ]
}

@test 'dry-run link shows symlink for new files' {
  castle 'rc-files'
  run homeshick --dry-run --batch link rc-files
  assert_success
  assert_output -p 'symlink'
  assert_output -p '.bashrc'
}

@test 'dry-run link shows directory for new directories' {
  castle 'dotfiles'
  run homeshick --dry-run --batch link dotfiles
  assert_success
  assert_output -p 'directory'
  assert_output -p '.ssh'
}

@test 'dry-run link shows identical for already-linked files' {
  castle 'rc-files'
  homeshick --batch --quiet link rc-files
  run homeshick --dry-run --verbose link rc-files
  assert_success
  assert_output -p 'identical'
  assert_output -p '.bashrc'
  # Verify the existing symlinks are untouched
  [ -L "$HOME/.bashrc" ]
}

@test 'dry-run link shows skip for existing files with --skip' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick --dry-run --skip link rc-files
  assert_success
  assert_output -p 'skip'
  assert_output -p '.bashrc'
  # The original file should still be a regular file, not a symlink
  [ -f "$HOME/.bashrc" ]
  [ ! -L "$HOME/.bashrc" ]
}

@test 'dry-run link shows overwrite for existing files with --force' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick --dry-run --force link rc-files
  assert_success
  assert_output -p 'overwrite'
  assert_output -p '.bashrc'
  # The original file should still be untouched
  [ -f "$HOME/.bashrc" ]
  [ ! -L "$HOME/.bashrc" ]
}

@test 'dry-run link shows conflict for existing files without flags' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick --dry-run --batch link rc-files
  assert_success
  assert_output -p 'conflict'
  assert_output -p '.bashrc'
  assert_output -p 'would prompt'
  # The original file should still be untouched
  [ -f "$HOME/.bashrc" ]
  [ ! -L "$HOME/.bashrc" ]
}

@test 'dry-run link handles mixed scenario: some new, some existing' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick --dry-run --batch link rc-files
  assert_success
  # .bashrc should show as conflict (exists, batch default = no overwrite)
  assert_output -p '.bashrc'
  # symlinked-file should show as new symlink
  assert_output -p 'symlinked-file'
  # Nothing should have changed
  [ -f "$HOME/.bashrc" ]
  [ ! -L "$HOME/.bashrc" ]
  [ ! -e "$HOME/symlinked-file" ]
}

@test 'dry-run link works with multiple castles' {
  castle 'rc-files'
  castle 'dotfiles'
  run homeshick --dry-run --batch link rc-files dotfiles
  assert_success
  assert_output -p '.bashrc'
  assert_output -p '.ssh'
  # Nothing should have been created
  [ ! -e "$HOME/.bashrc" ]
  [ ! -e "$HOME/.ssh" ]
}

@test 'dry-run link all castles when no castle specified' {
  castle 'rc-files'
  castle 'dotfiles'
  run homeshick --dry-run --batch link
  assert_success
  assert_output -p '.bashrc'
  assert_output -p '.ssh'
  [ ! -e "$HOME/.bashrc" ]
  [ ! -e "$HOME/.ssh" ]
}

# =============================================================================
# Pull dry-run tests
# =============================================================================

@test 'dry-run pull shows up-to-date for current castle' {
  castle 'rc-files'
  run homeshick --dry-run pull rc-files
  assert_success
  assert_output -p 'up-to-date'
}

@test 'dry-run pull does not modify HEAD' {
  castle 'pull-test'
  # Reset to an earlier commit so there are updates available
  (cd "$HOME/.homesick/repos/pull-test" && git reset --hard HEAD~1 >/dev/null)
  local head_before
  head_before=$(cd "$HOME/.homesick/repos/pull-test" && git rev-parse HEAD)
  run homeshick --dry-run pull pull-test
  assert_success
  local head_after
  head_after=$(cd "$HOME/.homesick/repos/pull-test" && git rev-parse HEAD)
  # HEAD should not have changed
  [ "$head_before" = "$head_after" ]
}

@test 'dry-run pull shows behind count' {
  castle 'pull-test'
  # Reset to an earlier commit so there are updates available
  (cd "$HOME/.homesick/repos/pull-test" && git reset --hard HEAD~1 >/dev/null)
  run homeshick --dry-run pull pull-test
  assert_success
  assert_output -p 'behind'
}

@test 'dry-run pull skips castles with no upstream' {
  castle 'rc-files'
  (cd "$HOME/.homesick/repos/rc-files" && git remote rm origin)
  run homeshick --dry-run pull rc-files
  assert_success
  assert_output -p 'no upstream'
}

# =============================================================================
# Refresh dry-run tests
# =============================================================================

@test 'dry-run refresh does not touch FETCH_HEAD' {
  castle 'rc-files'
  # Make the castle outdated by removing FETCH_HEAD
  local fetch_head="$HOME/.homesick/repos/rc-files/.git/FETCH_HEAD"
  rm -f "$fetch_head"
  run homeshick --dry-run refresh 7 rc-files
  # refresh returns EX_TH_EXCEEDED (87) for outdated castles, even in dry-run
  [ $status -eq 87 ]
  # FETCH_HEAD should not have been created/touched
  [ ! -e "$fetch_head" ]
}

@test 'dry-run refresh shows outdated castles' {
  castle 'rc-files'
  # Make the castle outdated by removing FETCH_HEAD
  rm -f "$HOME/.homesick/repos/rc-files/.git/FETCH_HEAD"
  run homeshick --dry-run refresh 7 rc-files
  [ $status -eq 87 ]
  # refresh should show the castle as outdated
  assert_output -p 'outdated'
}

@test 'dry-run refresh shows fresh castles' {
  castle 'rc-files'
  # Touch FETCH_HEAD to make it fresh
  touch "$HOME/.homesick/repos/rc-files/.git/FETCH_HEAD"
  run homeshick --dry-run refresh 7 rc-files
  assert_success
  assert_output -p 'fresh'
}

# =============================================================================
# Combined flag tests
# =============================================================================

@test 'dry-run with short flag -n works' {
  castle 'rc-files'
  run homeshick -n link rc-files
  assert_success
  assert_output -p 'symlink'
  [ ! -e "$HOME/.bashrc" ]
}

@test 'dry-run combined with batch flag -nb' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick -nb link rc-files
  assert_success
  # Should show conflict for .bashrc (batch default = no overwrite)
  assert_output -p 'conflict'
  [ -f "$HOME/.bashrc" ]
  [ ! -L "$HOME/.bashrc" ]
}

@test 'dry-run combined with verbose flag' {
  castle 'rc-files'
  homeshick --batch --quiet link rc-files
  run homeshick --dry-run --verbose link rc-files
  assert_success
  # With verbose, identical symlinks should be shown
  assert_output -p 'identical'
}

@test 'dry-run combined with skip flag' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick -ns link rc-files
  assert_success
  assert_output -p 'skip'
  [ -f "$HOME/.bashrc" ]
  [ ! -L "$HOME/.bashrc" ]
}

@test 'dry-run combined with force flag' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick -nf link rc-files
  assert_success
  assert_output -p 'overwrite'
  [ -f "$HOME/.bashrc" ]
  [ ! -L "$HOME/.bashrc" ]
}

# =============================================================================
# Help text includes dry-run
# =============================================================================

@test 'help output includes dry-run option' {
  run homeshick help
  assert_success
  assert_output -p '--dry-run'
}
