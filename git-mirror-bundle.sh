#!/bin/zsh

# We use "$@" instead of $* to preserve argument-boundary information
ARGS=$(getopt -o 'r:' --long 'remote:' -- "$@") || exit
eval "set -- $ARGS"

while true; do
    case $1 in
      (-r|--remote)
            REMOTE=$2; shift 2;;
      (--)  shift; break;;
      (*)   exit 1;;           # error
    esac
done

if [ -z "$REMOTE" ]; then
        echo 'Missing --remote' >&2
        exit 1
fi

REPO=$(basename ${REMOTE} ".git")

git clone --mirror ${REMOTE} "${REPO}"
