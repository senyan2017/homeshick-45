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

# --- link / symlink ----------------------------------------------------------

@test 'link --dry-run reports new files but creates nothing' {
  castle 'rc-files'
  [ ! -e "$HOME/.bashrc" ]
  run homeshick --dry-run link rc-files
  assert_success
  assert_output --partial 'new'
  assert_output --partial '.bashrc'
  # The whole point of a dry run: nothing on disk changed.
  [ ! -e "$HOME/.bashrc" ]
  [ ! -L "$HOME/.bashrc" ]
}

@test 'link -n is short for --dry-run' {
  castle 'rc-files'
  run homeshick -n link rc-files
  assert_success
  assert_output --partial 'new'
  [ ! -e "$HOME/.bashrc" ]
}

@test 'link --dry-run leaves the home directory untouched' {
  castle 'rc-files'
  castle 'dotfiles'
  local before after
  before=$(find "$HOME" -mindepth 1 ! -path "$HOME/.homesick/*" | sort)
  homeshick --dry-run link rc-files dotfiles >/dev/null
  after=$(find "$HOME" -mindepth 1 ! -path "$HOME/.homesick/*" | sort)
  [ "$before" = "$after" ]
}

@test 'link --dry-run reports a conflict and keeps the existing file' {
  castle 'rc-files'
  echo 'original contents' > "$HOME/.bashrc"
  run homeshick --dry-run link rc-files
  assert_success
  assert_output --partial 'conflict'
  # the conflicting file must not be deleted, replaced or symlinked
  [ -f "$HOME/.bashrc" ]
  [ ! -L "$HOME/.bashrc" ]
  [ "$(cat "$HOME/.bashrc")" = 'original contents' ]
}

@test 'link --dry-run --force reports overwrite without deleting' {
  castle 'rc-files'
  echo 'original contents' > "$HOME/.bashrc"
  run homeshick --dry-run --force link rc-files
  assert_success
  assert_output --partial 'overwrite'
  [ "$(cat "$HOME/.bashrc")" = 'original contents' ]
  [ ! -L "$HOME/.bashrc" ]
}

@test 'link --dry-run --skip reports skip without deleting' {
  castle 'rc-files'
  echo 'original contents' > "$HOME/.bashrc"
  run homeshick --dry-run --skip link rc-files
  assert_success
  assert_output --partial 'skip'
  [ "$(cat "$HOME/.bashrc")" = 'original contents' ]
  [ ! -L "$HOME/.bashrc" ]
}

@test 'link --dry-run on an already-linked castle changes nothing' {
  castle 'rc-files'
  homeshick --batch link rc-files
  [ -L "$HOME/.bashrc" ]
  local inode_before inode_after
  inode_before=$(get_inode_no "$HOME/.bashrc")
  run homeshick --dry-run --verbose link rc-files
  assert_success
  assert_output --partial 'identical'
  inode_after=$(get_inode_no "$HOME/.bashrc")
  [ "$inode_before" -eq "$inode_after" ]
}

@test 'link --dry-run prints a change-plan summary' {
  castle 'rc-files'
  run homeshick --dry-run link rc-files
  assert_success
  assert_output --partial 'dry run'
  assert_output --partial 'nothing was modified'
}

@test 'link --dry-run --quiet prints nothing but stays non-destructive' {
  castle 'rc-files'
  run homeshick --dry-run --quiet link rc-files
  assert_success
  [ -z "$output" ]
  [ ! -e "$HOME/.bashrc" ]
}

# --- clone -------------------------------------------------------------------

@test 'clone --dry-run does not create the castle' {
  fixture 'rc-files'
  run homeshick --dry-run clone "$REPO_FIXTURES/rc-files"
  assert_success
  assert_output --partial 'clone'
  [ ! -e "$HOME/.homesick/repos/rc-files" ]
}

@test 'clone --dry-run reports a conflict when the target exists' {
  castle 'rc-files'
  local head_before
  head_before=$(cd "$HOME/.homesick/repos/rc-files" && git rev-parse HEAD)
  run homeshick --dry-run clone "$REPO_FIXTURES/rc-files"
  assert_success
  assert_output --partial 'conflict'
  # the pre-existing castle must be left exactly as it was
  [ -d "$HOME/.homesick/repos/rc-files" ]
  [ "$head_before" = "$(cd "$HOME/.homesick/repos/rc-files" && git rev-parse HEAD)" ]
}

# --- pull --------------------------------------------------------------------

@test 'pull --dry-run does not move HEAD or link new files' {
  castle 'rc-files'
  (cd "$HOME/.homesick/repos/rc-files" && git reset --hard HEAD~1 >/dev/null)
  homeshick link --batch --quiet rc-files
  local head_before
  head_before=$(cd "$HOME/.homesick/repos/rc-files" && git rev-parse HEAD)
  [ ! -e "$HOME/.gitignore" ]

  run homeshick --dry-run pull rc-files
  assert_success
  assert_output --partial 'pull'
  # HEAD must not have advanced (no real git pull happened) ...
  [ "$head_before" = "$(cd "$HOME/.homesick/repos/rc-files" && git rev-parse HEAD)" ]
  # ... and no new files should have been linked
  [ ! -e "$HOME/.gitignore" ]
}

@test 'pull --dry-run reports castles without an upstream' {
  castle 'rc-files'
  (cd "$HOME/.homesick/repos/rc-files" && git remote rm origin)
  run homeshick --dry-run pull rc-files
  assert_success
  assert_output --partial 'no upstream'
}

# --- refresh -----------------------------------------------------------------

@test 'refresh --dry-run does not create or touch FETCH_HEAD' {
  castle 'rc-files'
  local fetch_head="$HOME/.homesick/repos/rc-files/.git/FETCH_HEAD"
  # Guarantee a clean precondition regardless of how clone behaves.
  rm -f "$fetch_head"
  # threshold 0 marks the castle as outdated; a real interactive refresh would
  # create/touch FETCH_HEAD, but a dry run must leave it alone.
  run homeshick --dry-run refresh 0 rc-files <<<n
  [ ! -e "$fetch_head" ]
}
