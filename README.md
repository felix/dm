# dm: Dotfile Manager

A single-file "dotfile" manager written in POSIX shell. It creates and
synchronises symlinks in your home directory to a central dotfile
source.

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
        -v        Be noisy
        -s <path> Specify dotfile path (default: ~/.dotfiles)
        -f        Force. Replace symlinks and no backups (sync)
        -h        This help

## FAQs

Q: What about deeply nested files?

A: All parent directories that do not exist will be created in your home
directory.  This enables linking only files. For example:


    ~
    |-- blah
    \-- bin
        \-- nested
	        \-- foo -> ~/.dotfiles/bin/nested/foo

The `nested` and `foo` directories above will be created if need be.

Q: How do I clean up old symlinks?

A: Manually. I have not yet had the time/motivation to work out how to see if the
broken symlink is pointing to a missing file in the dotfiles source.

## Author

Felix Hanley <felix@userspace.com.au>

## License

MIT
