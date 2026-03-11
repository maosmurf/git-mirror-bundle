#!/usr/bin/env bash
set -euo pipefail

# Usage: ./github-org-sync.sh <org> [target-dir] [--dry-run]
# Requires: gh CLI (https://cli.github.com/) authenticated with `gh auth login`

ORG="${1:?Usage: $0 <github-org> [target-dir] [--dry-run]}"
TARGET_DIR="${2:-./providers}"
DRY_RUN=false
[[ "${*}" == *--dry-run* ]] && DRY_RUN=true

mkdir -p "$TARGET_DIR"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXCLUDED=()
for exclude_file in "$SCRIPT_DIR/excluded-github-repos.txt" "$SCRIPT_DIR/excluded-github-repos.local.txt"; do
    if [[ -f "$exclude_file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            EXCLUDED+=("$line")
        done < "$exclude_file"
    fi
done

is_excluded() {
    local name="$1"
    for ex in "${EXCLUDED[@]}"; do
        [[ "$name" == "$ex" ]] && return 0
    done
    return 1
}

echo "Fetching repos for org: ${ORG}"
mapfile -t REPOS < <(gh repo list "$ORG" --limit 1000 --json nameWithOwner,sshUrl --jq '.[].sshUrl')

TOTAL="${#REPOS[@]}"
if [[ "$TOTAL" -eq 0 ]]; then
    echo "No repos found. Make sure you're authenticated: gh auth login" >&2
    exit 1
fi

$DRY_RUN && echo "[DRY RUN] No changes will be made."
echo "Found ${TOTAL} repos → ${TARGET_DIR}/"
echo ""

ERRORS=0
for i in "${!REPOS[@]}"; do
    url="${REPOS[$i]}"
    name=$(basename "$url" .git)

    if is_excluded "$name"; then
        echo "[skip] ${name}"
        continue
    fi
    dest="${TARGET_DIR}/${name}"
    n=$((i + 1))

    if [[ -d "${dest}/.git" ]]; then
        echo "[${n}/${TOTAL}] fetch ${name}"
        $DRY_RUN || git -C "$dest" fetch --all --quiet || { echo "  WARN: fetch failed, skipping"; (( ERRORS++ )) || true; }
    else
        echo "[${n}/${TOTAL}] clone ${name}"
        $DRY_RUN || git clone --quiet "$url" "$dest" || { echo "  WARN: clone failed"; (( ERRORS++ )) || true; }
    fi
done

echo ""
echo "Done — ${TOTAL} repos, ${ERRORS} error(s)."
