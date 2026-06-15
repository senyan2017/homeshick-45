#!/usr/bin/env bash

ask_symlink() {
  if [[ $# -gt 0 ]]; then
    if [[ $# == 1 ]]; then
      msg="The castle $1 has new files."
    else
      OIFS=$IFS
      IFS=,
      msg="The castles $* have new files."
      IFS=$OIFS
    fi
    if prompt_no 'updates' "$msg" 'symlink?'; then
      # shellcheck source=commands/link.sh disable=SC2154
      source "$homeshick/lib/commands/link.sh"
      for castle in "$@"; do
        symlink "$castle"
      done
    fi
  fi
  return "$EX_SUCCESS"
}


# Singleline prompt that stays on the same line even if you press enter.
# Automatically colors the line according to the answer the user gives.
# Currently homeshick only has prompts with "no" as the default,
# so there's no reason to implement prompt_yes right now
prompt_no() {
  local OTALK=$TALK
  # Disable the quiet flag while prompting in interactive mode
  if ! $BATCH; then
    TALK=true
  fi

  local status=$1
  local message=$2
  local prompt=$3
  local batch_default=${4:-2}
  local result=-1

  # Always show the prompt message, even in quiet mode.
  # Conflicts and important prompts must remain visible so that users and
  # automation can diagnose issues (exit code alone is not always enough).
  # We use printf directly instead of status() to bypass the TALK check.
  # shellcheck disable=SC2154
  printf "$bldwht%13s$txtdef %s\n" "$status" "$message"
  if ! $BATCH; then
    pending "$prompt" "[yN] "
    while true; do
      local answer=""
      local char=""
      while true; do
        read -s -n 1 -r char
        if [[ $char == "" ]]; then
          break
        fi
        printf "%c" "$char"
        answer="${answer}${char}"
      done
      case $answer in
        Y|y) result=0 ;;
        N|n) result=1 ;;
        "")  result=2 ;;
      esac
      [[ $result -ge 0 ]] && break
      for (( i=0; i<${#answer}; i++ )) ; do
        printf "\b"
      done
      printf "%${#answer}s\r"
      # global vars
      # shellcheck disable=SC2154
      pending "$pending_status" "$pending_message"
    done
  else
    result=$batch_default
    if $TALK; then
      local response_txt
      response_txt=$(if [[ $result == 0 ]]; then echo Yes; else echo No; fi)
      pending "$prompt" "BATCH - $response_txt"
    else
      # In quiet+batch mode, still show the result so that
      # skipped conflicts are not completely invisible
      local response_txt
      response_txt=$(if [[ $result == 0 ]]; then echo Yes; else echo No; fi)
      printf "$bldwht%13s$txtdef %s\n" "$prompt" "BATCH - $response_txt"
    fi
  fi
  if [[ $result == 0 ]]; then
    success
  else
    fail
  fi
  TALK=$OTALK
  return "$result"
}
