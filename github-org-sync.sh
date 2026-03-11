#!/usr/bin/env bash
set -euo pipefail

# Usage: ./github-org-sync.sh <org> [provider-dir]
# Requires: gh CLI (https://cli.github.com/) authenticated with `gh auth login`

ORG="${1:?Usage: $0 <github-org> [provider-dir]}"
PROVIDER_DIR="${2:-./providers}"
TARGET_DIR="${PROVIDER_DIR}/${ORG}"

mkdir -p "$TARGET_DIR"

echo "Fetching repos for org: ${ORG}"
mapfile -t REPOS < <(gh repo list "$ORG" --limit 1000 --json nameWithOwner,sshUrl --jq '.[].sshUrl')

TOTAL="${#REPOS[@]}"
if [[ "$TOTAL" -eq 0 ]]; then
    echo "No repos found. Make sure you're authenticated: gh auth login" >&2
    exit 1
fi

echo "Found ${TOTAL} repos → ${TARGET_DIR}/"
echo ""

ERRORS=0
for i in "${!REPOS[@]}"; do
    url="${REPOS[$i]}"
    name=$(basename "$url" .git)
    dest="${TARGET_DIR}/${name}"
    n=$((i + 1))

    if [[ -d "${dest}/.git" ]]; then
        echo "[${n}/${TOTAL}] pull  ${name}"
        git -C "$dest" pull --ff-only --quiet || { echo "  WARN: pull failed, skipping"; (( ERRORS++ )) || true; }
    else
        echo "[${n}/${TOTAL}] clone ${name}"
        git clone --quiet "$url" "$dest" || { echo "  WARN: clone failed"; (( ERRORS++ )) || true; }
    fi
done

echo ""
echo "Done — ${TOTAL} repos, ${ERRORS} error(s)."
