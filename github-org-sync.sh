#!/usr/bin/env bash
set -euo pipefail

# Usage: ./github-org-sync.sh <org> [target-dir] [--dry-run] [--archived] [-q|--quiet]
# Requires: gh CLI (https://cli.github.com/) authenticated with `gh auth login`

ORG="${1:?Usage: $0 <github-org> [target-dir] [--dry-run]}"
TARGET_DIR="${2:-./providers}"
DRY_RUN=false
[[ "${*}" == *--dry-run* ]] && DRY_RUN=true
INCLUDE_ARCHIVED=false
[[ "${*}" == *--archived* ]] && INCLUDE_ARCHIVED=true
QUIET_FLAG=""
[[ "${*}" == *--quiet* || "${*}" == *\ -q* ]] && QUIET_FLAG="--quiet"

GREEN='\033[0;32m'
PURPLE='\033[0;35m'
YELLOW='\033[0;33m'
RESET='\033[0m'

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
ARCHIVED_FLAG="--no-archived"
$INCLUDE_ARCHIVED && ARCHIVED_FLAG=""
mapfile -t REPOS < <(gh repo list "$ORG" --limit 1000 $ARCHIVED_FLAG --json sshUrl,diskUsage,isArchived --jq '.[] | .sshUrl + "|" + (.diskUsage | tostring) + "|" + (.isArchived | tostring)')

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
    IFS='|' read -r url disk_kb is_archived <<< "${REPOS[$i]}"
    name=$(basename "$url" .git)
    archived_label=""
    [[ "$is_archived" == "true" ]] && archived_label=" ${YELLOW}[archived]${RESET}"

    if is_excluded "$name"; then
        echo "[skip] ${name}"
        continue
    fi
    dest="${TARGET_DIR}/${name}"
    n=$((i + 1))

    if [[ -d "${dest}/.git" ]]; then
        echo -e "[${n}/${TOTAL}] ${PURPLE}fetch${RESET} ${name}${archived_label}"
        if $DRY_RUN; then
            fetch_output=$(git -C "$dest" fetch --all --dry-run 2>&1) || { echo "  WARN: fetch dry-run failed"; (( ERRORS++ )) || true; }
            if [[ -z "$fetch_output" ]]; then
                echo "  (up to date)"
            else
                echo "$fetch_output" | sed 's/^/  /'
            fi
        else
            git -C "$dest" fetch --all $QUIET_FLAG || { echo "  WARN: fetch failed, skipping"; (( ERRORS++ )) || true; }
        fi
    else
        size=$(numfmt --to=si --from-unit=1024 "$disk_kb" 2>/dev/null || echo "? KB")
        echo -e "[${n}/${TOTAL}] ${GREEN}clone${RESET} ${name} (~${size})${archived_label}"
        $DRY_RUN || git clone $QUIET_FLAG "$url" "$dest" || { echo "  WARN: clone failed"; (( ERRORS++ )) || true; }
    fi
done

echo ""
echo "Done — ${TOTAL} repos, ${ERRORS} error(s)."
