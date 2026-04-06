#!/bin/bash
# Print absolute path to websites/<id>/<id>.json for a site id or JSON "name".
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSITES_DIR="$(cd "$SELF_DIR/../../websites" && pwd)"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: $(basename "$0") [-h | --help] <website-name>"
    echo "Resolve folder id (websites/foo/foo.json) or JSON \"name\" field to a JSON path."
    exit 0
fi

if [ $# -ne 1 ] || [ -z "$1" ]; then
    echo "Usage: $(basename "$0") <website-name>" >&2
    exit 2
fi

name="$1"

if [ -f "$WEBSITES_DIR/$name/$name.json" ]; then
    echo "$WEBSITES_DIR/$name/$name.json"
    exit 0
fi

parse_name_field() {
    local file="$1"
    if command -v jq &> /dev/null; then
        jq -r '.name // empty' "$file"
    else
        grep '"name"' "$file" | head -1 | sed 's/.*"name": *"\([^"]*\)".*/\1/'
    fi
}

while IFS= read -r json_path; do
    [ -z "$json_path" ] && continue
    if [ "$(parse_name_field "$json_path")" = "$name" ]; then
        echo "$json_path"
        exit 0
    fi
done < <("$SELF_DIR/list-website-json-files.sh")

echo "Error: no website metadata found for: $name" >&2
exit 1
