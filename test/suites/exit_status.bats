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

# ---------------------------------------------------------------------------
# Exit code aggregation
# ---------------------------------------------------------------------------

@test 'link returns EX_CONFLICT (84) when files are skipped with --skip' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick --skip link rc-files
  [ $status -eq 84 ] # EX_CONFLICT
}

@test 'link returns EX_CONFLICT (84) when files are skipped in batch mode' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick --batch link rc-files
  [ $status -eq 84 ] # EX_CONFLICT
}

@test 'link returns success when --force overwrites all conflicts' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick --force link rc-files
  [ $status -eq 0 ] # EX_SUCCESS
  [ -L "$HOME/.bashrc" ]
}

@test 'link returns success when no conflicts exist' {
  castle 'rc-files'
  run homeshick --batch link rc-files
  [ $status -eq 0 ] # EX_SUCCESS
}

# ---------------------------------------------------------------------------
# Partial success across multiple castles
# ---------------------------------------------------------------------------

@test 'link processes all castles even when one does not exist' {
  castle 'rc-files'
  castle 'dotfiles'
  run homeshick --batch link nonexistent rc-files dotfiles
  [ $status -eq 1 ] # EX_ERR from nonexistent
  # rc-files and dotfiles should still be linked
  [ -L "$HOME/.bashrc" ]
  [ -L "$HOME/.ssh/known_hosts" ]
}

@test 'link reports conflict exit code when one castle has conflicts among many' {
  castle 'rc-files'
  castle 'dotfiles'
  castle 'nodirs'
  touch "$HOME/.bashrc"
  run homeshick --skip link nodirs rc-files dotfiles
  [ $status -eq 84 ] # EX_CONFLICT from rc-files skip
  # nodirs and dotfiles should still be linked
  [ -L "$HOME/.file1" ]
  [ -L "$HOME/.ssh/known_hosts" ]
}

@test 'pull processes all castles even when one does not exist' {
  castle 'rc-files'
  castle 'dotfiles'
  run homeshick --batch pull nonexistent rc-files dotfiles
  [ $status -eq 1 ] # EX_ERR from nonexistent
}

@test 'pull returns worst exit code when multiple castles fail differently' {
  castle 'pull-test'
  castle 'nodirs'
  # Set up pull-test to fail
  (cd "$HOME/.homesick/repos/pull-test" && git reset --hard HEAD~1 >/dev/null)
  (cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase false && git config pull.ff only)
  # Add a local commit that conflicts with upstream
  (
    cd "$HOME/.homesick/repos/pull-test" &&
    git config user.name "Test" && git config user.email "test@test" &&
    echo "conflict" > home/.bashrc &&
    git add home/.bashrc && git commit -m "conflict" >/dev/null
  )
  run homeshick --batch pull nodirs pull-test
  [ $status -eq 70 ] # EX_SOFTWARE from pull-test failure
}

# ---------------------------------------------------------------------------
# Quiet mode behavior
# ---------------------------------------------------------------------------

@test 'quiet mode suppresses normal output but shows errors' {
  run homeshick --quiet --batch link nonexistent
  [ $status -eq 1 ] # EX_ERR
  # Error message should still be present
  [[ "$output" == *"error"* ]]
}

@test 'quiet mode shows conflict messages in batch mode' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick --quiet --batch link rc-files
  [ $status -eq 84 ] # EX_CONFLICT
  # The conflict/skip info should be visible even in quiet mode
  [[ "$output" == *"exists"* ]]
}

@test 'quiet mode shows conflict messages with --skip' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick --quiet --skip link rc-files
  [ $status -eq 84 ] # EX_CONFLICT
  [[ "$output" == *"exists"* ]]
}

@test 'quiet+batch mode: pull failure still shows error' {
  castle 'pull-test'
  (cd "$HOME/.homesick/repos/pull-test" && git reset --hard HEAD~1 >/dev/null)
  (cd "$HOME/.homesick/repos/pull-test" && git config pull.rebase false && git config pull.ff only)
  (
    cd "$HOME/.homesick/repos/pull-test" &&
    git config user.name "Test" && git config user.email "test@test" &&
    echo "conflict" > home/.bashrc &&
    git add home/.bashrc && git commit -m "conflict" >/dev/null
  )
  run homeshick --quiet --batch pull pull-test
  [ $status -eq 70 ] # EX_SOFTWARE
  [[ "$output" == *"error"* ]]
}

# ---------------------------------------------------------------------------
# Batch + skip/force combinations
# ---------------------------------------------------------------------------

@test 'batch+skip: existing files are skipped, exit code reflects conflict' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  touch "$HOME/.gitignore"
  run homeshick --batch --skip link rc-files
  [ $status -eq 84 ] # EX_CONFLICT
  [ -f "$HOME/.bashrc" ] && [ ! -L "$HOME/.bashrc" ]
  [ -f "$HOME/.gitignore" ] && [ ! -L "$HOME/.gitignore" ]
}

@test 'batch+force: existing files are overwritten, exit code is success' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  touch "$HOME/.gitignore"
  run homeshick --batch --force link rc-files
  [ $status -eq 0 ] # EX_SUCCESS
  [ -L "$HOME/.bashrc" ]
  [ -L "$HOME/.gitignore" ]
}

@test 'skip takes priority over force when both specified' {
  castle 'rc-files'
  touch "$HOME/.bashrc"
  run homeshick --skip --force link rc-files
  [ $status -eq 84 ] # EX_CONFLICT (skip wins)
  [ -f "$HOME/.bashrc" ] && [ ! -L "$HOME/.bashrc" ]
}

# ---------------------------------------------------------------------------
# Clone fault tolerance
# ---------------------------------------------------------------------------

@test 'clone processes all URIs even when one fails' {
  fixture 'rc-files'
  fixture 'dotfiles'
  run homeshick --batch clone "$REPO_FIXTURES/nonexistent" "$REPO_FIXTURES/rc-files" "$REPO_FIXTURES/dotfiles"
  [ $status -ne 0 ]
  # The successful clones should still have happened
  [ -d "$HOME/.homesick/repos/rc-files" ]
  [ -d "$HOME/.homesick/repos/dotfiles" ]
}

# ---------------------------------------------------------------------------
# Generate fault tolerance
# ---------------------------------------------------------------------------

@test 'generate processes all castles even when one already exists' {
  castle 'rc-files'
  run homeshick --batch generate rc-files newcastle
  [ $status -eq 1 ] # EX_ERR from rc-files conflict
  # newcastle should still be created
  [ -d "$HOME/.homesick/repos/newcastle" ]
}

# ---------------------------------------------------------------------------
# Track fault tolerance
# ---------------------------------------------------------------------------

@test 'track does not abort entire script on git add failure' {
  castle 'rc-files'
  touch "$HOME/.newfiletotrack"
  run homeshick track rc-files "$HOME/.newfiletotrack"
  [ $status -eq 0 ] # EX_SUCCESS
  [ -f "$HOME/.homesick/repos/rc-files/home/.newfiletotrack" ]
}

# ---------------------------------------------------------------------------
# Exit code priority (worst wins)
# ---------------------------------------------------------------------------

@test 'exit code reflects worst failure across mixed results' {
  castle 'rc-files'
  castle 'dotfiles'
  # Create a conflict for rc-files
  touch "$HOME/.bashrc"
  # dotfiles links without conflict
  run homeshick --skip link dotfiles rc-files
  [ $status -eq 84 ] # EX_CONFLICT from rc-files
  # dotfiles should still be linked
  [ -L "$HOME/.ssh/known_hosts" ]
}
