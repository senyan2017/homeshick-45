#!/usr/bin/env bash

pull() {
  [[ ! $1 ]] && help_err pull
  local castle=$1
  # repos is a global variable
  # shellcheck disable=SC2154
  local repo="$repos/$castle"
  castle_exists 'pull' "$castle"
  if ! repo_has_upstream "$repo"; then
    if $DRY_RUN; then
      dry_run_info 'pull' "would skip $castle (no upstream)"
    else
      pending 'pull' "$castle"
      ignore 'no upstream' "Could not pull $castle, it has no upstream"
    fi
    return "$EX_SUCCESS"
  fi

  if $DRY_RUN; then
    # Fetch remote refs (non-destructive: only updates remote-tracking branches)
    local git_out
    git_out=$(cd "$repo" && git fetch 2>&1) || true

    local upstream
    upstream=$(cd "$repo" && git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
    local head_hash upstream_hash
    head_hash=$(cd "$repo" && git rev-parse HEAD 2>/dev/null)
    upstream_hash=$(cd "$repo" && git rev-parse '@{upstream}' 2>/dev/null)

    if [[ "$head_hash" == "$upstream_hash" ]]; then
      dry_run_info 'pull' "$castle (already up-to-date)"
    else
      local behind_count ahead_count
      behind_count=$(cd "$repo" && git rev-list --count HEAD..'@{upstream}' 2>/dev/null)
      ahead_count=$(cd "$repo" && git rev-list --count '@{upstream}'..HEAD 2>/dev/null)
      local detail="$castle ($upstream"
      if [[ $behind_count -gt 0 ]]; then
        detail="$detail, $behind_count commit(s) behind"
      fi
      if [[ $ahead_count -gt 0 ]]; then
        detail="$detail, $ahead_count commit(s) ahead"
      fi
      detail="$detail)"
      dry_run_info 'pull' "$detail"
    fi
    return "$EX_SUCCESS"
  fi

  pending 'pull' "$castle"

  local git_out
  git_out=$(cd "$repo" && git pull 2>&1) || \
    err "$EX_SOFTWARE" "Unable to pull $repo. Git says:" "$git_out"

  version_compare "$GIT_VERSION" 1.6.5
  if [[ $? != 2 ]]; then
    git_out=$(cd "$repo" && git submodule update --recursive --init 2>&1) || \
      err "$EX_SOFTWARE" "Unable update submodules for $repo. Git says:" "$git_out"
  else
    git_out=$(cd "$repo" && git submodule update --init 2>&1) || \
      err "$EX_SOFTWARE" "Unable update submodules for $repo. Git says:" "$git_out"
  fi
  success
  return "$EX_SUCCESS"
}

symlink_new_files() {
  # Safety: skip entirely in dry-run mode
  $DRY_RUN && return "$EX_SUCCESS"
  local updated_castles=()
  while [[ $# -gt 0 ]]; do
    local castle=$1
    shift
    local repo="$repos/$castle"
    if [[ ! -d $repo/home ]]; then
      continue;
    fi
    # @{1} refers to the previous reflog entry on the current branch, which
    # will be right before the pull
    if ! git_out=$(cd "$repo" && git diff --name-only --diff-filter=AR '@{1}' HEAD -- home 2>/dev/null | wc -l 2>&1); then
      continue  # Ignore errors, this operation is not mission critical
    fi
    if [[ $git_out -gt 0 ]]; then
      updated_castles+=("$castle")
    fi
  done
  ask_symlink "${updated_castles[@]}"
  return "$EX_SUCCESS"
}
