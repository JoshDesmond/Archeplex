#!/bin/bash
# Print sorted paths to website metadata JSON files.
# Layout: websites/<site-id>/<site-id>.json
set -euo pipefail

# Resolves websites/ from this script's location (scripts/util -> repo root -> websites).
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSITES_DIR="$(cd "$SELF_DIR/../../websites" && pwd)"

shopt -s nullglob
files=()
for site_dir in "$WEBSITES_DIR"/*/; do
    site_id=$(basename "$site_dir")
    json="${site_dir}${site_id}.json"
    if [ -f "$json" ]; then
        files+=("$json")
    fi
done
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
    exit 0
fi
printf '%s\n' "${files[@]}" | LC_ALL=C sort
