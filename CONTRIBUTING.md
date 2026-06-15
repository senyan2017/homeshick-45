# Contribution guidelines #

## Architecture overview ##

The entry point `bin/homeshick` is intentionally thin. It orchestrates three
clearly separated concerns:

| Layer | File | Responsibility |
|-------|------|----------------|
| Environment setup | `bin/homeshick` | Source libraries, init globals, call the pipeline |
| CLI parsing | `lib/cli.sh` | Flag expansion, subcommand identification, argument collection, defaults |
| Dispatch | `lib/dispatch.sh` | Command loading, per-castle iteration, exit status aggregation, post-actions |
| Command implementation | `lib/commands/*.sh` | Individual command logic (one function per file) |

### Adding a new subcommand

1. Create `lib/commands/<name>.sh` with a function `<name>()` that takes a
   single castle name as its first argument.
2. Add `<name>` to the `HS_VALID_COMMANDS` array in `lib/cli.sh`.
3. If the command operates on castles and should run on all castles when none
   are specified, add it to `HS_BATCH_COMMANDS` in `lib/cli.sh`.
4. If the command requires at least one argument, add it to
   `HS_REQUIRED_COMMANDS` in `lib/cli.sh`.
5. If the command needs special argument parsing (like `refresh` with its
   optional DAYS parameter or `track` with its castle-then-files pattern),
   add a branch in the `case $cmd in` block inside `hs_collect_positional()`
   in `lib/cli.sh`.
6. If the command needs a post-loop action (like `clone` calling
   `symlink_cloned_files`), add the hook in `hs_dispatch()` in `lib/dispatch.sh`.

No changes to `bin/homeshick` should be needed for a new command.

### CLI parsing conventions

- Global flags (`-q`, `-s`, `-f`, `-b`, `-v`, `-h`) are accepted both before
  and after the subcommand.
- Combined short flags (e.g. `-qb`) are expanded into individual flags
  (`-q -b`) during parsing.
- Command-specific arguments are collected after the subcommand token.
  Each command defines its own argument routing in `hs_collect_positional()`.

### Boundaries

- **Public dispatch layer** (`lib/cli.sh`, `lib/dispatch.sh`, `bin/homeshick`):
  Flag parsing, argument collection, command loading, iteration over castles,
  exit status aggregation, post-loop hooks.
- **Command internals** (`lib/commands/*.sh`): Everything else — git operations,
  file manipulation, prompting within a single castle's context.
- Command implementations may read the global flags (`TALK`, `SKIP`, `FORCE`,
  `BATCH`, `VERBOSE`) and environment (`repos`, `homeshick`, `T_START`,
  `GIT_VERSION`) but should not modify the dispatch flow.

## Reporting issues ##
Make sure that what you are experiencing is actually an error and that it lies
with homeshick (often it can be a git configuration error)

### Questions ###
If you have a question be sure to read
[the documentation](https://github.com/andsens/homeshick/wiki) first.
Often you will find the answer to it there.

### Description ###
As with bug reports everywhere else:

* state the action(s) you took
* explain what outcome you expected
* describe the actual result

You will also need to report which operating system you encountered the issue on
and which shell you used (type `echo $SHELL` in your terminal if you are unsure).

### Reproducing ###
Unless you ran in to a [heisenbug](http://en.wikipedia.org/wiki/Heisenbug),
it should be possible to reproduce the
bug in a testing environment. To that end run
`$HOME/.homesick/repos/homeshick/test/interactive` and reproduce the bug.  This
script drops you into a new shell where `$HOME` is set to an (almost) empty
temporary folder. If you cannot reproduce the bug there, the error is likely
with your setup and not homeshick. Otherwise attach the commands you executed
in that environment to the issue.

## Pull requests ##

### Branching
**Work from and create pull requests on `development`, not `master`.**

`master` always represents the latest release since that is the way homeshick
updates itself. The `development` branch is where work is done for the next
release version of homeshick.

### Code style ###
* Indent with 2 spaces.
* Always use double brackets for `if` blocks
* Run your changes through
[shellcheck](https://www.shellcheck.net/) with `test/shellcheck`
and the [bats](https://github.com/sstephenson/bats) testsuite with `test/run`

Use the supplied [editorconfig](http://editorconfig.org) file.
Most editors have [editorconfig plugins](http://editorconfig.org/#download)
to apply these settings.

### Content ###
**Every PR should only contain one feature change, bug fix or typo correction.**

Commits should be atomic units of work, if they are not you should rebase them
so that they are (typo corrections from a previous change for example do not
justify a commit).

### Description ###
The PR should clearly describe what problem the change fixes.
A feature addition with no justification and use-case will be rejected.

### Testing ###
Unless the code-change is a refactor, you should always add unit tests.  When
fixing a bug there should be a new test case that fails with the old code and
succeeds with the new code. When introducing a new feature, it should be
tested extensively, a single test case will not suffice.

Note that bats does not fail a test case when using double brackets.
To assert variable values and file existance you *must* use single brackets!

Also consider negative test cases (e.g. what happens when a non-existing
castlename is passed as an argument?).

You can read about the details of the testing framework in the
[testing documentation](https://github.com/andsens/homeshick/wiki/Testing).
