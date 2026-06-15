# Contribution guidelines #

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

## Adding or changing commands ##

The command-line front-end is split into three layers with a deliberate
boundary between them. Keep new work on the correct side of that boundary so
the entry layer stays small and parsing/dispatch regressions stay easy to spot.

* `bin/homeshick` — a thin entry point. It sources the helpers, seeds the
  shared globals and calls the parser and dispatcher. It should not need to
  change when you add a command.
* `lib/parse.sh` — turns `"$@"` into a resolved request. It owns the **command
  registry** (`homeshick_command_spec`), the single source of truth for what
  each command accepts and how it is run. Option handling
  (`homeshick_apply_option`), combined short-option expansion, per-command
  argument collection and the "operate on every castle" defaults all live here.
* `lib/dispatch.sh` — runs the resolved request (once, or once per castle), runs
  any follow-up step and folds the per-item results into a single exit status.
* `lib/commands/*.sh` — the individual command implementations.

To **add a command**, add one row to the registry in `lib/parse.sh` and an
implementation in `lib/commands/`; only an unusual per-item invocation needs a
small addition to `lib/dispatch.sh`. Do not add another `while`/`case` branch to
the entry layer.

To **add an option**, add a single case to `homeshick_apply_option` in
`lib/parse.sh`. Nothing else should need to change.

The parser talks to the dispatcher only through the documented output contract
at the top of `lib/parse.sh` (`cmd`, `params`, `castle`, `threshhold`, the
runtime flags, ...). Avoid introducing new globals that reach across this
boundary.
