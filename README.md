# dm: Dotfile Manager

A single-file "dotfile" manager written in POSIX shell. It creates and
synchronises symlinks in your home directory to a central dotfile
source.

## Installation

Copy the file to somewhere in your path and ensure it is executable:

    $ curl -L -o ~/bin/ https://git.userspace.com.au/dm/plain/dm
    $ chmod +x ~/bin/dm

## Usage

The script expects your dotfiles master to be in `~/.dotfiles` or have the ENV
variable `DOTFILES` set to the path. This master path can then be kept in
revision control and be kept clean. The script will symbolically link files
from the master path to your home directory.

`dm check` will list all files needing linking.

`dm sync` will link all files to your home directory.

`dm add <file>` will move the file into the master and then link it.

Each command has optional flags which modify the default behaviour as the usage
help describes below:

    Options:
        -q        Be quiet
        -s <path> Set dotfile source path (default: ~/.dotfiles)
        -r        Remove existing symlinks if broken (sync)
        -f        Force overwriting existing files, implies -r (sync, add)
        -o        Skip backup of existing files (sync)
        -n        Dry run, don't actually do anything (sync, add)
        -h        This help

## FAQs

Q: What about deeply nested files?

All parent directories that do not exist will be created in your home
directory.  This enables linking only files. For example:


    ~
    |-- blah
    \-- bin
        \-- nested
	        \-- foo -> ~/.dotfiles/bin/foo

The `nested` and `foo` directories above will be created if need be.

## Author

Felix Hanley <felix@userspace.com.au>
