#!/bin/sh

# Dotfile Manager
#
# POSIX shell script to keep a central repo of dotfiles and link them into your
# home folder.

# Author: Felix Hanley <felix@userspace.com.au>

# Some things we need
readlink=$(which readlink)
[ -z "$readlink" ] && echo "Missing readlink, cannot continue."
dirname=$(which dirname)
[ -z "$dirname" ] && echo "Missing dirname, cannot continue."
find=$(which find)
[ -z "$find" ] && echo "Missing find, cannot continue."

# Show usage
usage() {
    printf 'Manage your dotfiles\n'
    printf 'usage: dm [opts] [sync|check|add]\n\n'
    printf 'Options:\n'
    printf '\t-v        Be noisy\n'
    printf '\t-s <path> Specify dotfile path (default: %s)\n' "$DOTFILES"
    printf '\t-f        Force. Replace symlinks and no backups (sync)\n'
    printf '\t-h        This help\n'
    exit 1
}

# Perform the actual link creation
create_link() {
    src=$1; shift;
    dest=$1; shift;

    if [ -h "$src" ]; then
        # The dotfile itself is a link, copy it
        src="$HOME/$($readlink -n "$src")"
    fi
    # Symbolic link command
    linkcmd="ln -s"
    if [ -n "$FORCE" ]; then
        linkcmd="$linkcmd -f"
    fi
    printf 'linking %s\n' "$dest"
    $linkcmd "$src" "$dest"
}

ensure_dest() {
    dest=$1; shift
    ts=$(date +%Y%m%dT%H%M%S)
    [ ! -e "$dest" ] && return

    if [ -n "$FORCE" ]; then
        rm "$dest"
    else
        printf 'backing up %s\n' "$dest"
        r = $(mv "$dest" "$dest.dm-$ts")
        if [ "$r" -ne 0 ]; then
            printf 'failed to backup %s\n' "$dest"
            exit 1
        fi
    fi
}

# Provide a realpath implementation
realpath() {
    canonicalize_path "$(resolve_symlinks "$1")"
}
resolve_symlinks() {
    path=$($readlink -- "$1")
    if [ $? -eq 0 ]; then
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

ensure_path() {
    directory=$("$dirname" "$1")
    if [ ! -d "$directory" ]; then
        [ -n "$VERBOSE" ] && printf 'creating path %s\n' "$directory"
        mkdir -p "$($dirname "$1")" > /dev/null
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
    dest=$HOME/$relative
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
    if [ -h "$dest" ]; then
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
    dest=$HOME/$relative
    src=$DOTFILES/$relative

    # There are only 4 cases:
    # missing -> link
    # symlink -> relink
    # file -> clear and link (if forced)
    # link -> clear and link (if forced)
    if [ -e "$dest" ]; then

        # Existing symlink
        if [ -h "$dest" ]; then
            destlink=$($readlink -n "$dest")

            if [ -h "$src" ]; then
                # If src is also a link, don't dereference it
                srclink=$HOME/$($readlink -n "$src")
            else
                destlink=$(realpath "$destlink")
                srclink="$src"
            fi
            if [ "$destlink" = "$srclink" ]; then
                [ -n "$VERBOSE" ] && printf 'keeping %s\n' "$dest"
            fi

        elif [ -f "$dest" ] && [ "$ACTION" = "check" ]; then
            # Regular file
            printf "existing %s\n" "$dest"

        else
            # Unknown file?!?
            printf 'unknown type %s\n' "$dest"
            return 1
        fi
    fi

    if [ "$ACTION" = "sync" ]; then
        ensure_path "$dest" &&
            ensure_dest "$dest" &&
            create_link "$src" "$dest"
    fi
}

# Default dotfiles path
DOTFILES=$(realpath "${DOTFILES:-$HOME/.dotfiles}/")

main() {
    while getopts ":vdfs:" opt; do
        case $opt in
            v) VERBOSE=true
                ;;
            f) FORCE=true
                ;;
            s) DOTFILES=$OPTARG
                ;;
            ?) usage
                ;;
        esac
    done

    # Shift the rest
    shift $(($OPTIND - 1))

    ACTION="$1"

    case "$ACTION" in
        check|sync)
            scan
            ;;
        add)
            if [ -z "$2" ]; then
                echo "Missing required path"
                return 1
            fi
            shift
            add "$1"
            ;;
        *)
            usage
            ;;
    esac
    return $?
}

main "$@"
