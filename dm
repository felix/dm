#!/bin/sh

# Dotfile Manager
#
# POSIX shell script to keep a central repo of dotfiles
# and link them into your home folder.

# Author: Felix Hanley <felix@userspace.com.au>

# Some things we need
readlink=$(command -v readlink)
if [ -z "$readlink" ]; then
   echo "Missing readlink, cannot continue."
   exit 1
fi
dirname=$(command -v dirname)
if [ -z "$dirname" ]; then
    echo "Missing dirname, cannot continue."
    exit 1
fi
find=$(command -v find)
if [ -z "$find" ]; then
   echo "Missing find, cannot continue."
   exit 1
fi

# Show usage
usage() {
    printf 'Manage your dotfiles\n'
    printf 'usage: dm [opts] [check|add|clean]\n'
    printf '\n'
    printf '  add\t\tadd a file to your dotfile repo\n'
    printf '  check\t\tlist files needing linking (same is -n flag)\n'
    printf '  clean\t\tlist and prompt to delete broken symlinks\n'
    printf '\n'
    printf 'Options:\n'
    printf '\t-s <path> Specify dotfile path (default: %s)\n' "$DOTFILES"
    printf '\t-n        Dry run. no changes (same as check command)\n'
    printf '\t-f        Force. Replace symlinks and no backups\n'
    printf '\t-h        This help\n'
}

# Provide a realpath implementation
realpath() {
    canonicalize_path "$(resolve_symlinks "$1")"
}
resolve_symlinks() {
    if path=$($readlink -- "$1"); then
        dir_context=$($dirname -- "$1")
        resolve_symlinks "$(_prepend_path_if_relative "$dir_context" "$path")"
    else
        printf '%s\n' "$1"
    fi
}
_prepend_path_if_relative() {
    case "$2" in
        /* ) printf '%s\n' "$2" ;;
         * ) printf '%s\n' "$1/$2" ;;
    esac
}
canonicalize_path() {
    if [ -d "$1" ]; then
        # Canonicalize dir path
        (cd "$1" 2>/dev/null && pwd -P)
    else
        # Canonicalize file path
        dir=$("$dirname" -- "$1")
        file=$(basename -- "$1")
        (cd "$dir" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$file")
    fi
}

# Perform the actual link creation
create_link() {
    src=$1; shift;
    dest=$1; shift;

    if [ -e "$dest" ] && [ -z "$DRYRUN" ] && [ -n "$BACKUP" ]; then
        printf 'backing up %s\n' "$dest"
        if ! cp -f "$dest" "$dest.dm-backup"; then
            printf 'failed to backup %s\n' "$dest"
            exit 1
        fi
    fi

    [ -z "$DRYRUN" ] && [ -f "$dest" ] && rm "$dest"

    if [ -L "$src" ]; then
        # The dotfile itself is a link, copy it
        src="$REALHOME/$($readlink -n "$src")"
    fi
    # Symbolic link command
    linkcmd="ln -s"
    if [ -z "$BACKUP" ]; then
        linkcmd="$linkcmd -f"
    fi
    printf 'linking %s\n' "$dest"
    [ -z "$DRYRUN" ] && $linkcmd "$src" "$dest"
}

ensure_path() {
    directory=$("$dirname" "$1")
    if [ ! -d "$directory" ]; then
        printf 'creating path %s\n' "$directory"
        [ -z "$DRYRUN" ] && mkdir -p "$($dirname "$1")" > /dev/null
    fi
}

scan() {
    # Each file and link in DOTFILES, excluding VCS
    # TODO enable configurable excludes
    filelist=$(find "$DOTFILES" \( -name .git -o -name .hg \) -prune -o \( -type f -print \) -o \( -type l -print \))
    for file in $filelist; do
        process "$file"
    done
}

add() {
    file=$1; shift
    if [ "$file" = "." ] || [ "$file" = ".." ]; then
        return
    fi
    relative=${file#${DOTFILES}/}
    # Note these are in 'sync' order
    dest=$REALHOME/$relative
    src=$DOTFILES/$relative

    # Nothing to copy
    if [ ! -e "$dest" ]; then
        printf 'Cannot find %s\n' "$dest"
        return 1
    fi
    # Dotfile exists
    if [ -f "$src" ]; then
        printf '%s is already managed\n' "$dest"
        return 1
    fi
    # De-reference home version
    if [ -L "$dest" ]; then
        dest=$(realpath "$dest")
    fi
    ensure_path "$src"
    mv "$dest" "$src" && create_link "$src" "$dest"
    return $?
}

# Updates a link from the dotfiles src to the home directory
# $1 is the file within the dotfile directory
process() {
    file=$1; shift
    if [ "$file" = "." ] || [ "$file" = ".." ]; then
        return
    fi
    relative=${file#${DOTFILES}/}
    dest=$REALHOME/$relative
    src=$DOTFILES/$relative

    #printf 'src=%s dest=%s relative=%s\n' "$src" "$dest" "$relative"

    ensure_path "$dest"

    # missing -> link
    if [ ! -e "$dest" ]; then
        create_link "$src" "$dest"
        return 0
    fi

    # symlink -> relink
    if [ -L "$dest" ]; then
        destlink=$(realpath "$($readlink -n "$dest")")
        srclink=$(realpath "$src")

        # Src is also a link
#        if [ -L "$src" ]; then
#            # FIXME
#            # Need to determine relative links
#            srclink=$(realpath "$($readlink -n "$src")")
#        fi

        if [ "$destlink" != "$srclink" ]; then
            create_link "$src" "$dest"
        fi
        return 0
    fi

    # regular file exists
    if [ -f "$dest" ]; then
        create_link "$src" "$dest"
        return 0
    fi

    printf 'unknown type %s\n' "$dest"
    return 1
}

main() {
    while getopts ":bns:" opt; do
        case $opt in
            b) BACKUP=true
                ;;
            n) DRYRUN=true
                ;;
            s) DOTFILES=$OPTARG
                ;;
            ?)
                usage
                exit 0
                ;;
        esac
    done

    # Shift the rest
    shift $((OPTIND - 1))

    REALHOME=$(realpath "$HOME")
    # Default dotfiles path
    DOTFILES=$(realpath "${DOTFILES:-$REALHOME/.dotfiles}/")

    case "$1" in
        check)
            DRYRUN=true
            scan
            ;;
        add)
            if [ -z "$2" ]; then
                echo "Missing required path"
                usage
                return 1
            fi
            add "$2"
            ;;
        clean)
            $find "$REALHOME" -type l -exec test ! -e '{}' \; -exec rm -i '{}' \;
            ;;
        *)
            scan
            ;;
    esac
    return $?
}

main "$@"
