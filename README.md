homeshick ![Lint & test](https://github.com/andsens/homeshick/workflows/Lint%20&%20test/badge.svg)
=========
In Unix, configuration files are king.  
Tailoring tools to suit your needs through configuration can be empowering.  
An immense number of hours is spent on getting these adjustments just right,
but once you leave the confines of your own computer, these local optimizations are left behind.

By the power of git, homeshick enables you to bring the symphony of settings
you have poured your heart into with you to remote computers.
With it you can begin to focus even more energy on bettering your work environment
since the benefits are reaped on whichever machine you are using.

However bare bones these machines are, provided that at least Bash 3 and Git 1.5 are available you can use homeshick.
homeshick can handle multiple dotfile repositories. This means that you can install
larger frameworks like [oh-my-zsh](https://github.com/robbyrussell/oh-my-zsh)
or a multitude of emacs or vim plugins alongside your own customizations without clutter.

For detailed [installation instructions](https://github.com/andsens/homeshick/wiki/Installation), [tutorials](https://github.com/andsens/homeshick/wiki/Tutorials) and [tips](https://github.com/andsens/homeshick/wiki/Automatic-deployment) & [tricks](https://github.com/andsens/homeshick/wiki/Symlinking) have a look at the [wiki](https://github.com/andsens/homeshick/wiki).

Quick install
-------------

homeshick is installed to your own home directory and does not require root privileges to be installed.
```sh
git clone https://github.com/andsens/homeshick.git $HOME/.homesick/repos/homeshick
```
*Note: If you'd like to help testing new features before they are released use `git clone --branch testing https://...`*

To invoke homeshick, source the `homeshick.sh` script from your rc-script:
```sh
# from sh and its derivates (bash, dash, ksh, zsh etc.)
printf '\nsource "$HOME/.homesick/repos/homeshick/homeshick.sh"' >> $HOME/.bashrc
# csh and derivatives (i.e. tcsh)
printf '\nalias homeshick source "$HOME/.homesick/repos/homeshick/homeshick.csh"\n' >> $HOME/.cshrc
# fish shell
echo \n'source "$HOME/.homesick/repos/homeshick/homeshick.fish"' >> "$HOME/.config/fish/config.fish"
```

Previewing changes (dry run)
----------------------------

Before homeshick touches anything on a fresh machine, you can preview exactly
what it would do by adding `--dry-run` (or `-n`) to `clone`, `link`/`symlink` or `pull`:
```sh
homeshick --dry-run clone https://github.com/you/dotfiles.git
homeshick --dry-run link dotfiles
```
Nothing is written to disk. Instead homeshick prints a per-file plan showing
which files would be **added**, which already-present files would be
**overwritten** or are in **conflict**, and which are left untouched, followed
by a one-line summary. This makes it safe to audit a change plan before rolling
homeshick out across many machines, rather than backing up the whole box just in case.

`--dry-run` composes with the usual `--force`, `--skip` and `--quiet` flags, so
e.g. `homeshick -n -f link` previews what a forced run would overwrite.

Contributing
------------

Before submitting pull requests or reporting bugs, please make sure to read
the [contribution guidelines](CONTRIBUTING.md).
