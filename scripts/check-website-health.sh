#!/bin/bash
# Check HTTPS response for one website (--all: every configured site) and optional healthchecks.io ping.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTION | WEBSITE_NAME]

Check that each site responds over HTTPS and HTML contains healthCheck.expectedTexts
from websites/<id>/<id>.json.

  WEBSITE_NAME    Site folder id or JSON "name" field (e.g. automati-solutions)
  --all           Check every site; ping HEALTHCHECKS_PING_URL with aggregate result
  -h, --help      Show this help

Environment (required for --all only):
  HEALTHCHECKS_PING_URL   Base URL from healthchecks.io (no trailing slash)

Exit status: 0 if all checked sites pass, 1 if any check fails.
EOF
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

parse_json_field() {
    local file="$1"
    local field="$2"

    if command -v jq &> /dev/null; then
        jq -r ".$field // empty" "$file"
    else
        grep "\"$field\"" "$file" | head -1 | sed 's/.*"'"$field"'": *"\([^"]*\)".*/\1/'
    fi
}

parse_expected_texts() {
    local file="$1"

    if command -v jq &> /dev/null; then
        jq -r '.healthCheck.expectedTexts // empty | .[]?' "$file" 2>/dev/null
    else
        local line
        line=$(grep -o '"expectedTexts": *\[[^]]*\]' "$file" 2>/dev/null | head -1)
        if [ -n "$line" ]; then
            echo "$line" | sed 's/.*\[\(.*\)\]/\1/' | tr ',' '\n' | sed 's/^ *"//;s/" *$//'
        fi
    fi
}

check_website() {
    local domain="$1"
    local name="$2"
    local expected_texts="$3"

    log "Checking $name ($domain)..."

    local response
    if ! response=$(curl -s --max-time "$CURL_TIMEOUT" --retry "$CURL_RETRIES" "https://$domain" 2>&1); then
        log_error "$name: Failed to fetch https://$domain"
        return 1
    fi

    while IFS= read -r text; do
        if [ -z "$text" ]; then
            continue
        fi
        if ! echo "$response" | grep -q "$text"; then
            log_error "$name: Expected text not found: '$text'"
            return 1
        fi
    done <<< "$expected_texts"

    log "$name: OK"
    return 0
}

process_one_json() {
    local website_file="$1"
    local domain name expected_texts

    domain=$(parse_json_field "$website_file" "domain")
    name=$(parse_json_field "$website_file" "name")
    expected_texts=$(parse_expected_texts "$website_file")

    if [ -z "$expected_texts" ]; then
        log "Skipping $name (no healthCheck configured)"
        return 0
    fi

    if ! check_website "$domain" "$name" "$expected_texts"; then
        return 1
    fi
    return 0
}

CURL_TIMEOUT=15
CURL_RETRIES=2
MODE=""
WEBSITE_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --all)
            MODE="all"
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help >&2
            exit 1
            ;;
        *)
            if [ -n "$WEBSITE_ARG" ]; then
                log_error "Unexpected extra argument: $1"
                show_help >&2
                exit 1
            fi
            WEBSITE_ARG="$1"
            shift
            ;;
    esac
done

if [ -z "$MODE" ] && [ -z "$WEBSITE_ARG" ]; then
    show_help >&2
    exit 1
fi

if [ "$MODE" = "all" ] && [ -n "$WEBSITE_ARG" ]; then
    log_error "Use either --all or a website name, not both."
    exit 1
fi

if [ "$MODE" = "all" ]; then
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        echo "Error: .env not found at $PROJECT_ROOT/.env (copy from .env.example)." >&2
        exit 1
    fi
    set -a
    # shellcheck disable=SC1091
    . "$PROJECT_ROOT/.env"
    set +a
    : "${HEALTHCHECKS_PING_URL:?}"
fi

OVERALL_EXIT_CODE=0
FAILED_SITES=()

if [ "$MODE" = "all" ]; then
    log "Starting health checks (--all)..."
    while IFS= read -r website_file; do
        [ -z "$website_file" ] && continue
        if ! process_one_json "$website_file"; then
            OVERALL_EXIT_CODE=1
            FAILED_SITES+=("$(parse_json_field "$website_file" "name")")
        fi
    done < <("$SCRIPT_DIR/util/list-website-json-files.sh")

    echo ""
    if [ $OVERALL_EXIT_CODE -eq 0 ]; then
        log "All websites are healthy!"
    else
        log_error "Failed sites: ${FAILED_SITES[*]}"
    fi

    log "Pinging healthchecks.io..."
    if curl -s --retry 3 --max-time 10 "${HEALTHCHECKS_PING_URL}/${OVERALL_EXIT_CODE}" > /dev/null; then
        log "Healthchecks.io ping sent (exit code: $OVERALL_EXIT_CODE)"
    else
        log_error "Failed to ping healthchecks.io"
    fi

    exit $OVERALL_EXIT_CODE
fi

# Single-site mode: .env optional unless user relies on nothing from it
website_file="$("$SCRIPT_DIR/util/resolve-website-json.sh" "$WEBSITE_ARG")"

log "Starting health check for: $WEBSITE_ARG..."
if ! process_one_json "$website_file"; then
    exit 1
fi

exit 0
