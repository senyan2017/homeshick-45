#!/usr/bin/env bash
#
# Command-line parsing for homeshick.
#
# This file owns everything that turns a raw "$@" into a fully resolved
# request: global option handling, combined short-option expansion,
# subcommand/alias resolution, per-command argument collection and the
# "operate on every castle" defaults.
#
# It deliberately knows nothing about *running* a command (see dispatch.sh).
# The boundary is: parse.sh decides WHAT was asked for, dispatch.sh carries
# it out, and lib/commands/*.sh implement the individual commands.
#
# ----------------------------------------------------------------------------
# Output contract
# ----------------------------------------------------------------------------
# homeshick_parse_arguments populates the following globals, which are the
# only channel between the parser and the dispatcher:
#
#   cmd          resolved command token (e.g. "pull"; aliases are kept as
#                typed so help text stays accurate, the spec carries the
#                canonical implementation)
#   params[]     positional arguments for the command (usually castle names)
#   castle       the castle for "track" (its leading, non-repeatable argument)
#   threshhold   the day threshold for "refresh", already converted to seconds
#   help_cmd     the task argument for "help"
#   TALK SKIP FORCE BATCH VERBOSE   runtime option flags
#   exit_status  pre-seeded result (only the require-defaults path touches it)
#
# These are owned by bin/homeshick, which initialises them before calling the
# parser. Nothing else should reach across this boundary.

# Several variables below are assigned here but consumed in dispatch.sh and in
# lib/commands/*.sh, which shellcheck cannot see across the source boundary.
# shellcheck disable=SC2034

# ----------------------------------------------------------------------------
# Command registry -- the single source of truth
# ----------------------------------------------------------------------------
# To add or change a command, edit THIS table and nothing else in the entry
# layer. Every column is consulted by the parser and/or the dispatcher, so a
# new command is one new row plus (if it needs unusual per-item handling) one
# small invoker in dispatch.sh -- never another branch sprinkled across a
# handful of while/case blocks.
#
# Fields set for the command in $1 (unknown command -> return 1):
#
#   spec_canonical  basename under lib/commands/ to source ('' = nothing to
#                   source, e.g. cd which is handled by the shell wrapper)
#   spec_function   function to invoke for the command ('' = none)
#   spec_argmode    how trailing positionals are collected:
#                     castles       -> appended to params[]
#                     days-castles  -> first is the refresh threshold (days),
#                                      the rest are castles
#                     castle-files  -> first is the castle, the rest are files
#                     none          -> no positionals allowed
#                     help          -> first is the task to describe
#   spec_empty      what to do when no positionals were given:
#                     all      -> expand to every cloned castle
#                     require   -> show the command's usage (it needs an arg)
#                     none      -> nothing special
#   spec_invoke     how the dispatcher runs it:
#                     each          -> once per param via spec_function
#                     each-refresh  -> once per param as: refresh THRESHOLD param
#                     each-track    -> once per param as: track CASTLE param
#                     each-pull     -> once per param, tracking what changed
#                     once          -> spec_function called a single time
#                     cd            -> print the cd help (shell-wrapper command)
#                     help          -> print usage for help_cmd
#   spec_subshell   'yes' to run each invocation in a subshell (isolates cd/exit)
#   spec_post       function run after the per-param loop ('' = none)
homeshick_command_spec() {
  spec_canonical=''
  spec_function=''
  spec_argmode=''
  spec_empty='none'
  spec_invoke=''
  spec_subshell='no'
  spec_post=''
  case $1 in
    cd)
      spec_argmode='castles'      spec_empty='require' spec_invoke='cd' ;;
    clone)
      spec_canonical='clone'   spec_function='clone'    spec_argmode='castles'      spec_empty='require' spec_invoke='each'         spec_post='symlink_cloned_files' ;;
    generate)
      spec_canonical='generate' spec_function='generate' spec_argmode='castles'     spec_empty='require' spec_invoke='each' ;;
    list | ls)
      spec_canonical='list'    spec_function='list'     spec_argmode='none'         spec_empty='none'    spec_invoke='once' ;;
    check | updates)
      spec_canonical='check'   spec_function='check'    spec_argmode='castles'      spec_empty='all'     spec_invoke='each'         spec_subshell='yes' ;;
    refresh)
      spec_canonical='refresh' spec_function='refresh'  spec_argmode='days-castles' spec_empty='all'     spec_invoke='each-refresh' spec_post='pull_outdated' ;;
    pull)
      spec_canonical='pull'    spec_function='pull'     spec_argmode='castles'      spec_empty='all'     spec_invoke='each-pull'    spec_post='symlink_new_files' ;;
    symlink | link)
      spec_canonical='link'    spec_function='symlink'  spec_argmode='castles'      spec_empty='all'     spec_invoke='each' ;;
    track)
      spec_canonical='track'   spec_function='track'    spec_argmode='castle-files' spec_empty='require' spec_invoke='each-track' ;;
    help)
      spec_canonical='help'    spec_function='help'     spec_argmode='help'         spec_empty='none'    spec_invoke='help' ;;
    *)
      return 1 ;;
  esac
  return 0
}

# ----------------------------------------------------------------------------
# Option handling
# ----------------------------------------------------------------------------

# Expand combined short options (e.g. `-qb' -> `-q -b') across the whole
# argument vector in one pass, so the rest of the parser only ever sees single
# options. Only clusters of two or more letters are split, exactly like the
# long-hand expansion the entry layer used to do twice; long options (`--foo')
# and single options (`-q') pass through untouched. The result is left in the
# global array _homeshick_argv.
homeshick_normalize_argv() {
  _homeshick_argv=()
  local token
  for token in "$@"; do
    while [[ $token =~ ^-[a-z][a-z]+ ]]; do
      _homeshick_argv+=("${token:0:2}")
      token="-${token:2}"
    done
    _homeshick_argv+=("$token")
  done
}

# Apply a single option token to the runtime flags. Called from both parsing
# phases so the set of recognised options lives in exactly one place.
homeshick_apply_option() {
  case $1 in
    -h | --help)    cmd='help' ;;
    -q | --quiet)   TALK=false ;;
    -s | --skip)    SKIP=true ;;
    -f | --force)   FORCE=true ;;
    -b | --batch)   BATCH=true ;;
    -v | --verbose) VERBOSE=true ;;
    *)
      # EX_USAGE comes from the sourced exit_status.sh
      # shellcheck disable=SC2154
      err "$EX_USAGE" "Unknown option '$1'" ;;
  esac
}

# ----------------------------------------------------------------------------
# Argument collection
# ----------------------------------------------------------------------------

# Consume a single positional argument according to the current command's
# argmode. The rules for every command live in the registry above, so this is
# one switch instead of one branch per command scattered through the parser.
homeshick_collect_argument() {
  case $spec_argmode in
    castles)
      params+=("$1") ;;
    days-castles)
      # The first positional is the refresh threshold in days; everything
      # after it is a castle. Only a purely numeric token is taken as the
      # threshold -- handing a non-numeric value (a castle name, which may
      # even contain spaces) to $(( )) raises a fatal arithmetic-expansion
      # error from inside this function, so anything that is not a number
      # falls through to params as a castle.
      if [[ ! $threshhold && $1 =~ ^[0-9]+$ ]]; then
        threshhold=$(($1 * 86400))
      else
        params+=("$1")
      fi ;;
    castle-files)
      if [[ ! $castle ]]; then
        castle=$1
      else
        params+=("$1")
      fi ;;
    none)
      # shellcheck disable=SC2154
      err "$EX_USAGE" "The '$1' command does not take any arguments" ;;
    help)
      [[ $help_cmd ]] || help_cmd=$1 ;;
  esac
}

# When a command was given no positionals, apply its default behaviour.
homeshick_apply_empty_default() {
  [[ ${#params[@]} -eq 0 ]] || return 0
  case $spec_empty in
    all)
      # Run the command against every cloned castle.
      local name
      while IFS= read -d $'\n' -r name; do
        params+=("$name")
      done < <(list_castle_names) ;;
    require)
      # The command needs an argument; show its usage instead. help() exits 0
      # after printing, which mirrors the long-standing behaviour, but we still
      # record EX_USAGE for callers that inspect $exit_status before then.
      help_cmd=$cmd
      cmd='help'
      # shellcheck disable=SC2154
      exit_status=$EX_USAGE ;;
    none)
      : ;;
  esac
}

# ----------------------------------------------------------------------------
# Top-level parser
# ----------------------------------------------------------------------------

# Turn "$@" into the output-contract globals documented at the top of the file.
homeshick_parse_arguments() {
  homeshick_normalize_argv "$@"
  set -- "${_homeshick_argv[@]}"

  # Phase 1: options that precede the subcommand.
  while [[ $# -gt 0 && $1 == -* ]]; do
    homeshick_apply_option "$1"
    shift
  done

  # Resolve the subcommand. -h/--help may already have selected "help"; with no
  # arguments at all we also default to help.
  if [[ ! $cmd ]]; then
    if [[ $# -eq 0 ]]; then
      cmd='help'
    else
      # shellcheck disable=SC2154
      homeshick_command_spec "$1" || err "$EX_USAGE" "Unknown command '$1'"
      cmd=$1
      shift
    fi
  fi
  # Load the spec for the resolved command (covers the -h => help case too).
  homeshick_command_spec "$cmd" || err "$EX_USAGE" "Unknown command '$cmd'"

  # Phase 2: remaining options and positional arguments, in any order. A late
  # -h flips the command to help, so re-resolve the spec to pick up its argmode.
  while [[ $# -gt 0 ]]; do
    if [[ $1 == -* ]]; then
      homeshick_apply_option "$1"
      homeshick_command_spec "$cmd"
      shift
      continue
    fi
    homeshick_collect_argument "$1"
    shift
  done

  homeshick_apply_empty_default

  # The refresh threshold defaults to one week when none was given.
  [[ $threshhold ]] || threshhold=$((7 * 86400))
}
