#!/bin/bash
# Verify .env against .env.example: each VITE_* key listed in the example must be
# present and non-empty in .env (Vite inlines these at build time).
set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: $(basename "$0") [-h | --help] <project-directory>"
    echo "Ensure VITE_* keys from .env.example exist and are non-empty in .env."
    exit 0
fi

if [ $# -ne 1 ]; then
    echo "Usage: $(basename "$0") <project-directory>" >&2
    exit 1
fi

PROJECT_DIR="$1"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: not a directory: $PROJECT_DIR" >&2
    exit 1
fi

ENV_EXAMPLE="$PROJECT_DIR/.env.example"
ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$ENV_EXAMPLE" ]; then
    exit 0
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env not found in $PROJECT_DIR (copy from .env.example and fill values)." >&2
    exit 1
fi

while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        \#*|'') continue ;;
    esac
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    case "$line" in
        VITE_*=*)
            key="${line%%=*}"
            val_line=$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | tail -1 || true)
            if [ -z "$val_line" ]; then
                echo "Error: $key missing from .env (listed in .env.example)." >&2
                exit 1
            fi
            val="${val_line#*=}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%"${val##*[![:space:]]}"}"
            val="${val#\"}"
            val="${val%\"}"
            val="${val#\'}"
            val="${val%\'}"
            if [ -z "$val" ]; then
                echo "Error: $key is empty in .env." >&2
                exit 1
            fi
            ;;
    esac
done < "$ENV_EXAMPLE"
