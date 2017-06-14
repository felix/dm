#!/bin/sh

# Dotfile Manager
#
# POSIX shell script to keep a central repo of dotfiles and link them into your
# home folder.

# Author: Felix Hanley <felix@userspace.com.au>

# Some things we need
readlink=$(which readlink)
[ -z $readlink ] && echo "Missing readlink, cannot continue."
dirname=$(which dirname)
[ -z $dirname ] && echo "Missing dirname, cannot continue."
find=$(which find)
[ -z $find ] && echo "Missing find, cannot continue."

# Show usage
usage() {
    echo "Manage your dotfiles\n"
    echo "usage: $0 [opts] [sync|check|add]"
    echo "\nOptions:"
    echo "\t-q\tBe quiet"
    echo "\t-s <path> Set dotfile source path (default: $DOTFILES)"
    echo "\t-r\tRemove existing symlinks if broken (sync)"
    echo "\t-f\tForce overwriting existing files, implies -r (sync, add)"
    echo "\t-o\tSkip backup of existing files (sync)"
    echo "\t-n\tDry run, don't actually do anything (sync, add)"
    echo "\t-h\tThis help"
    exit 1
}

# Perform the actual link creation
create_link() {
    local src=$1; shift;
    local dest=$1; shift;

    if [ -h $src ]; then
        # The dotfile itself is a link, copy it
        src="$HOME/$($readlink -n "$src")"
    fi
    # Symbolic link command
    linkcmd="ln -s"
    if [ -n $REPLACE ] || [ -n $FORCE]; then
        linkcmd="$linkcmd -f"
    fi
    [ -z $DRYRUN ] && $linkcmd "$src" "$dest"
}

remove_file() {
    local dest=$1; shift
    [ -z $DRYRUN ] && rm -f "$dest"
}

backup_file() {
    local dest=$1; shift
    ts=$(date +%Y%m%dT%H%M%S)
    [ -z $DRYRUN ] && mv "$dest" "$dest.dm-$ts"
}

# Provide a realpath implementation
realpath() {
    canonicalize_path "$(resolve_symlinks "$1")"
}
resolve_symlinks() {
    local dir_context path
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
        local dir file
        dir=$($dirname -- "$1")
        file=$(basename -- "$1")
        (cd "$dir" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$file")
    fi
}

scan() {
    # Each file and link in DOTFILES, excluding VCS
    # TODO enable configurable excludes
    local find_opts="! -path '*.git*' -path '*.hg*')"
    local filelist=$(find $DOTFILES \( -name .git -o -name .hg \) -prune -o \( -type f -print \) -o \( -type l -print \))
    for file in $filelist; do
        process $file
    done
}

add() {
    local file=$1; shift
    if [ $file = "." -o $file = ".." ]; then
        return
    fi
    local relative=${file#${DOTFILES}/}
    local dest=$HOME/$relative
    local src=$DOTFILES/$relative

    # Nothing to copy
    if [ ! -e $dest ]; then
        printf "Cannot find %s\n" $dest
        return 1
    fi
    # Dotfile exists
    if [ -f $src ] && [ -z $FORCE ]; then
        printf "%s is already managed\n" $dest
        return 1
    fi
    # De-reference home version
    if [ -h $dest ]; then
        dest=$(realpath "$dest")
    fi
    mv $dest $src && create_link $src $dest
    return $?
}

# Updates a link from the dotfiles src to the home directory
# $1 is the file within the dotfile directory
process() {
    local file=$1; shift
    if [ $file = "." -o $file = ".." ]; then
        return
    fi
    local relative=${file#${DOTFILES}/}
    local dest=$HOME/$relative
    local src=$DOTFILES/$relative

    # There are only 4 cases:
    # missing -> link
    # symlink -> relink
    # file -> clear and link (if forced)
    # link -> clear and link (if replace or forced)
    if [ -e "$dest" ]; then
        # Not forced
        if [ -z $FORCE ]; then
            #[ -z $QUIET] && [ $ACTION != "check" ] && printf "skipping %s\n" $dest
            return
        fi

        # Existing symlink
        if [ -h "$dest" ]; then
            local destlink=$($readlink -n "$dest")

            if [ -h $src ]; then
                # If src is also a link, don't dereference it
                local srclink=$HOME/$($readlink -n "$src")
            else
                local destlink=$(realpath "$destlink")
                local srclink="$src"
            fi
            if [ "$destlink" = "$srclink" ]; then
                [ -z $QUIET ] && prinf "keeping %s\n" $dest
                return
            fi

        elif [ -f "$dest" ]; then
            # Regular file, take a backup
            if [ -z $OVERWRITE ] && [ $ACTION = "sync" ]; then
                [ -z $QUIET] && printf "backing up %s\n" $dest
                backup_file $dest
            fi

        else
            # Unknown file?!?
            [ -z $QUIET ] && prinf "unknown type %s\n" $dest
            return 1
        fi
        [ -z $QUIET] && printf "removing %s\n" $dest
        [ $ACTION = "sync" ] && remove_file $dest

    else
        # missing, create path maybe
        local directory=$($dirname $dest)
        if [ ! -d $directory ]; then
            [ -z $QUIET] && printf "creating path %s\n" $directory
            [ -z $DRYRUN ] && mkdir -p $($dirname $dest) > /dev/null
        fi
    fi

    case $ACTION in
        check)
            printf "%s\n" $relative
            ;;
        sync)
            printf "linking %s\n" $relative
            create_link $src $dest
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
    shift $(($OPTIND - 1))

    ACTION=$1

    # Default dotfiles path
    DOTFILES=${DOTFILES:-$HOME/.dotfiles}
    DOTFILES=$(realpath "${DOTFILES%/}")

    case $ACTION in
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
            add $1
            ;;
        *)
            usage
            ;;
    esac
    return $?
}

main "$@"
