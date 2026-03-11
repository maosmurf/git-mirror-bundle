#!/usr/bin/env bash
set -euo pipefail

# Usage: ./gitlab-group-sync.sh <group> [target-dir] [--dry-run] [--archived] [-q|--quiet] [--host <host>] [--token <token>]
# Requires: curl, jq, git
# Auth: GITLAB_TOKEN env var or --token flag

GROUP="${1:?Usage: $0 <gitlab-group> [target-dir] [--dry-run] [--archived] [-q|--quiet]}"
TARGET_DIR="${2:-./providers}"
DRY_RUN=false
[[ "${*}" == *--dry-run* ]] && DRY_RUN=true
INCLUDE_ARCHIVED=false
[[ "${*}" == *--archived* ]] && INCLUDE_ARCHIVED=true
QUIET_FLAG=""
[[ "${*}" == *--quiet* || "${*}" == *\ -q* ]] && QUIET_FLAG="--quiet"

GITLAB_HOST="gitlab.com"
TOKEN="${GITLAB_TOKEN:-}"
args=("$@")
for i in "${!args[@]}"; do
    case "${args[$i]}" in
        --host)  GITLAB_HOST="${args[$((i+1))]}" ;;
        --token) TOKEN="${args[$((i+1))]}" ;;
    esac
done

if [[ -z "$TOKEN" ]]; then
    echo "Missing GitLab token. Set GITLAB_TOKEN env var or use --token <token>." >&2
    exit 1
fi

GREEN='\033[0;32m'
PURPLE='\033[0;35m'
YELLOW='\033[0;33m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXCLUDED=()
for exclude_file in "$SCRIPT_DIR/excluded-gitlab-repos.txt" "$SCRIPT_DIR/excluded-gitlab-repos.local.txt"; do
    if [[ -f "$exclude_file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            EXCLUDED+=("$line")
        done < "$exclude_file"
    fi
done

# Matches against:
#   - relative path  e.g. "data-platform/trainer/anyline-studio"
#   - subgroup prefix e.g. "data-platform/trainer" (excludes all repos underneath)
#   - repo name only  e.g. "anyline-studio"
is_excluded() {
    local rel_path="$1"
    local name
    name=$(basename "$rel_path")
    for ex in "${EXCLUDED[@]}"; do
        [[ "$rel_path" == "$ex" || "$rel_path" == "$ex/"* || "$name" == "$ex" ]] && return 0
    done
    return 1
}

API_BASE="https://${GITLAB_HOST}/api/v4"
ENCODED_GROUP="${GROUP//\//%2F}"
ARCHIVED_PARAM=""
$INCLUDE_ARCHIVED || ARCHIVED_PARAM="&archived=false"

echo "Fetching projects for group: ${GROUP}"

fetch_projects() {
    local page=1
    while true; do
        local batch
        batch=$(curl -sf \
            -H "PRIVATE-TOKEN: ${TOKEN}" \
            "${API_BASE}/groups/${ENCODED_GROUP}/projects?include_subgroups=true&with_statistics=true&per_page=100&page=${page}${ARCHIVED_PARAM}" \
        ) || { echo "GitLab API request failed" >&2; exit 1; }

        [[ $(echo "$batch" | jq 'length') -eq 0 ]] && break

        echo "$batch" | jq -r \
            --arg root "$GROUP" \
            '.[] | .ssh_url_to_repo
                 + "|" + (.path_with_namespace | ltrimstr($root + "/"))
                 + "|" + ((.statistics.repository_size // 0) | tostring)
                 + "|" + (.archived | tostring)'

        (( page++ ))
    done
}

mapfile -t REPOS < <(fetch_projects)

TOTAL="${#REPOS[@]}"
if [[ "$TOTAL" -eq 0 ]]; then
    echo "No projects found. Check the group name and your token permissions." >&2
    exit 1
fi

$DRY_RUN && echo "[DRY RUN] No changes will be made."
echo "Found ${TOTAL} repos → ${TARGET_DIR}/"
echo ""

ERRORS=0
for i in "${!REPOS[@]}"; do
    IFS='|' read -r url rel_path size_bytes is_archived <<< "${REPOS[$i]}"
    archived_label=""
    [[ "$is_archived" == "true" ]] && archived_label=" ${YELLOW}[archived]${RESET}"
    n=$((i + 1))

    if is_excluded "$rel_path"; then
        echo -e "[skip] ${rel_path}"
        continue
    fi

    dest="${TARGET_DIR}/${rel_path}"
    mkdir -p "$(dirname "$dest")"

    if [[ -d "${dest}/.git" ]]; then
        echo -e "[${n}/${TOTAL}] ${PURPLE}fetch${RESET} ${rel_path}${archived_label}"
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
        size=$(numfmt --to=si "$size_bytes" 2>/dev/null || echo "?")
        echo -e "[${n}/${TOTAL}] ${GREEN}clone${RESET} ${rel_path} (~${size})${archived_label}"
        $DRY_RUN || git clone $QUIET_FLAG "$url" "$dest" || { echo "  WARN: clone failed"; (( ERRORS++ )) || true; }
    fi
done

echo ""
echo "Done — ${TOTAL} repos, ${ERRORS} error(s)."