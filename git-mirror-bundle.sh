#!/bin/zsh

# We use "$@" instead of $* to preserve argument-boundary information
ARGS=$(getopt -o 'g:r:' --long 'gstorage:,remote:' -- "$@") || exit
eval "set -- $ARGS"

while true; do
    case $1 in
      (-g|--gstorage)
            GSTORAGE=$2; shift 2;;
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

TMP=$(mktemp -d -t 'git-mirror-bundle.XXXXXXXXXX')
cd $TMP

echo "Cloning ${REPO} into $(pwd)"
git clone --mirror ${REMOTE} "${REPO}"

cd "${REPO}"
BUNDLE="${REPO}.bundle"
git bundle create "${BUNDLE}" --all

BUNDLE_FILE=$(realpath ${BUNDLE})
echo "bundle ${BUNDLE_FILE}"

ARCHIVE_FILE="${BUNDLE_FILE}.gz"
gzip -9 "${BUNDLE_FILE}"
echo "archived ${ARCHIVE_FILE}"

if [ "$GSTORAGE" ]; then
   gsutil mv "${ARCHIVE_FILE}" "${GSTORAGE}"
fi
