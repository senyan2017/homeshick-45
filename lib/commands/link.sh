#!/usr/bin/env bash

symlink() {
  [[ ! $1 ]] && help symlink
  local castle=$1
  castle_exists 'link' "$castle"
  # repos is a global variable
  # shellcheck disable=SC2154
  local repo="$repos/$castle"
  if [[ ! -d $repo/home ]]; then
    if $VERBOSE; then
      ignore 'ignored' "$castle"
    fi
    return "$EX_SUCCESS"
  fi
  # Run through the repo files using process substitution.
  # The get_repo_files call is at the bottom of this loop.
  # We set the IFS to nothing and the separator for `read' to NUL so that we
  # don't separate files with newlines in their name into two iterations.
  # `read's stdin comes from a third unused file descriptor because we are
  # using the real stdin for prompting whether the user wants to
  # overwrite or skip on conflicts.
  while IFS= read -d $'\0' -r relpath <&3 ; do
    local repopath="$repo/home/$relpath"
    local homepath="$HOME/$relpath"
    local rel_repopath
    local rel_repopath_status
    # Capture stderr together with stdout: on success create_rel_path prints
    # only the relative path (nothing on stderr); on failure it prints only its
    # diagnostic. Grabbing stderr here keeps a dry run's expected "parent
    # missing" message from leaking into the otherwise clean preview output.
    rel_repopath=$(create_rel_path "$(dirname "$homepath")/" "$repopath" 2>&1)
    rel_repopath_status=$?
    if [[ $rel_repopath_status -ne 0 ]]; then
      # create_rel_path only fails when the parent directory is missing. During
      # a dry run we never create parent directories, so a deeper entry whose
      # parent is itself part of the plan lands here - it is, by definition,
      # something that would be newly created. Report it and move on instead of
      # aborting the whole preview.
      if $DRYRUN; then
        if [[ ! -d $repopath || -L $repopath ]]; then
          dry_run 'new' "$relpath"
        else
          dry_run 'directory' "$relpath"
        fi
        continue
      fi
      # Genuine failure (not a dry run): surface the diagnostic we captured
      # above, then abort exactly as before.
      printf "%s\n" "$rel_repopath" >&2
      return "$rel_repopath_status"
    fi

    if [[ -e $homepath || -L $homepath ]]; then
      # $homepath exists (but may be a dead symlink)
      if [[ -L $homepath && $(readlink "$homepath") == "$rel_repopath" ]]; then
        # $homepath symlinks to $repopath.
        if $VERBOSE; then
          if $DRYRUN; then
            dry_run 'identical' "$relpath"
          else
            ignore 'identical' "$relpath"
          fi
        fi
        continue
      elif [[ $(readlink "$homepath") == "$repopath" ]]; then
        # $homepath is an absolute symlink to $repopath, it would be replaced
        # with a relative symlink (or a directory, for legacy layouts).
        if $DRYRUN; then
          dry_run 'relink' "$relpath"
          continue
        fi
        if [[ -d $repopath && ! -L $repopath ]]; then
          # $repopath is a directory, but $homepath is a symlink -> legacy handling.
          rm "$homepath"
        else
          # replace it with a relative symlink
          rm "$homepath"
        fi
      else
        # $homepath does not symlink to $repopath
        # check if we should delete $homepath
        if [[ -d $homepath && -d $repopath && ! -L $repopath ]]; then
          # $repopath is a real directory while
          # $homepath is a directory or a symlinked directory
          # we do not take any action regardless of which it is.
          if $VERBOSE; then
            if $DRYRUN; then
              dry_run 'identical' "$relpath"
            else
              ignore 'identical' "$relpath"
            fi
          fi
          continue
        elif $SKIP; then
          if $DRYRUN; then
            dry_run 'skip' "$relpath"
          else
            ignore 'exists' "$relpath"
          fi
          continue
        elif $DRYRUN; then
          # Never prompt or delete during a dry run; just report what the
          # conflict would lead to given the current flags.
          if $FORCE; then
            dry_run 'overwrite' "$relpath"
          else
            dry_run 'conflict' "$relpath"
          fi
          continue
        elif ! $FORCE; then
          prompt_no 'conflict' "$relpath exists" "overwrite?" || continue
        fi
        # Delete $homepath.
        rm -rf "$homepath"
      fi
    fi

    if $DRYRUN; then
      if [[ ! -d $repopath || -L $repopath ]]; then
        dry_run 'new' "$relpath"
      else
        dry_run 'directory' "$relpath"
      fi
      continue
    fi

    if [[ ! -d $repopath || -L $repopath ]]; then
      # $repopath is not a real directory so we create a symlink to it
      pending 'symlink' "$relpath"
      ln -s "$rel_repopath" "$homepath"
    else
      pending 'directory' "$relpath"
      mkdir "$homepath"
    fi

    success
  # Fetch the repo files and redirect the output into file descriptor 3
  done 3< <(get_repo_files "$repo")
  return "$EX_SUCCESS"
}

# Fetches all files and folders in a repository that are tracked by git
# Works recursively on submodules as well
# Disable SC2154, we cannot do it inline where $homeshick is used.
# shellcheck disable=SC2154
get_repo_files() {
  # Resolve symbolic links
  # e.g. on osx $TMPDIR is in /var/folders...
  # which is actually /private/var/folders...
  # We do this so that the root part of $toplevel can be replaced
  # git resolves symbolic links before it outputs $toplevel
  local root
  root=$(cd "$1" && pwd -P)
  (
    local path
    while IFS= read -d $'\0' -r path; do
      # Remove quotes from ls-files
      # (used when there are newlines in the path)
      path=${path/#\"/}
      path=${path/%\"/}
      # Check if home/ is a submodule
      [[ $path == 'home' ]] && continue
      # Remove the home/ part
      path=${path/#home\//}
      # Print the file path (NUL separated because \n can be used in filenames)
      printf "%s\0" "$path"
      # Get the path of all the parent directories
      # up to the repo root.
      while true; do
        path=$(dirname "$path")
        # If path is '.' we're done
        [[ $path == '.' ]] && break
        # Print the path
        printf "%s\0" "$path"
      done
    # Enter the repo, list the repo root files in home
    # and do the same for any submodules
    done < <(cd "$root" &&
             git ls-files -z 'home/' &&
             git submodule --quiet foreach --recursive \
             "$homeshick/lib/submodule_files.sh \"$root\" \"\$toplevel\" \"\$path\"")
    # Unfortunately we have to use an external script for `git submodule foreach'
    # because versions prior to ~ 2.0 use `eval' to execute the argument.
    # This somehow messes quite badly with string substitution.
  ) | sort -zu # sort the results and make the list unique (-u), NUL is the line separator (-z)
}
