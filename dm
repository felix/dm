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

# Default dotfiles path
DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
DOTFILES=$(realpath "${DOTFILES%/}")

# Show usage
usage() {
    printf "Manage your dotfiles\n"
    printf "usage: %s [opts] [sync|check|add]\n\n" "$0"
    printf "Options:\n"
    printf "\t-q        Be quiet\n"
    printf "\t-s <path> Set dotfile source path (default: %s)\n" "$DOTFILES"
    printf "\t-r        Remove existing symlinks if broken (sync)\n"
    printf "\t-f        Force overwriting existing files, implies -r (sync, add)\n"
    printf "\t-o        Skip backup of existing files (sync)\n"
    printf "\t-n        Dry run, don't actually do anything (sync, add)\n"
    printf "\t-h        This help\n"
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
    if [ -n "$REPLACE" ] || [ -n "$FORCE" ]; then
        linkcmd="$linkcmd -f"
    fi
    [ -z "$DRYRUN" ] && $linkcmd "$src" "$dest"
}

remove_file() {
    dest=$1; shift
    [ -z "$DRYRUN" ] && rm -f "$dest"
}

backup_file() {
    dest=$1; shift
    ts=$(date +%Y%m%dT%H%M%S)
    [ -z "$DRYRUN" ] && mv "$dest" "$dest.dm-$ts"
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
        [ -z "$QUIET" ] && printf "creating path %s\n" "$directory"
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
    dest=$HOME/$relative
    src=$DOTFILES/$relative

    # Nothing to copy
    if [ ! -e "$dest" ]; then
        printf "Cannot find %s\n" "$dest"
        return 1
    fi
    # Dotfile exists
    if [ -f "$src" ] && [ -z "$FORCE" ]; then
        printf "%s is already managed\n" "$dest"
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
    # link -> clear and link (if replace or forced)
    if [ -e "$dest" ]; then
        # Not forced
        if [ -z "$FORCE" ]; then
            #[ -z $QUIET] && [ "$ACTION" != "check" ] && printf "skipping %s\n" "$dest"
            return
        fi

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
                [ -z "$QUIET" ] && prinf "keeping %s\n" "$dest"
                return
            fi

        elif [ -f "$dest" ]; then
            # Regular file, take a backup
            if [ -z "$OVERWRITE" ] && [ "$ACTION" = "sync" ]; then
                [ -z "$QUIET" ] && printf "backing up %s\n" "$dest"
                backup_file "$dest"
            fi

        else
            # Unknown file?!?
            [ -z "$QUIET" ] && prinf "unknown type %s\n" "$dest"
            return 1
        fi
        [ -z "$QUIET" ] && printf "removing %s\n" "$dest"
        [ "$ACTION" = "sync" ] && remove_file "$dest"

    else
        # missing, create path maybe
        [ "$ACTION" = "sync" ] && ensure_path "$dest"
    fi

    case "$ACTION" in
        check)
            printf "%s\n" "$relative"
            ;;
        sync)
            printf "linking %s\n" "$relative"
            create_link "$src" "$dest"
            ;;
    esac
}

main() {
    while getopts ":fqdbnrs:" opt; do
        case $opt in
            f) FORCE=true
                ;;
            b) OVERWRITE=true
                ;;
            n) DRYRUN=true
                ;;
            q) QUIET=true
                ;;
            r) REPLACE=true
                ;;
            s) DOTFILES=$OPTARG
                ;;
            ?) usage
                ;;
        esac
    done

    # Shift the rest
    shift "$(($OPTIND - 1))"

    ACTION="$1"

    case "$ACTION" in
        check)
            scan
            ;;
        sync|link)
            ACTION="sync"
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
