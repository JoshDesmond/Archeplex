#!/bin/bash
# Check uptime of all configured websites and ping healthchecks.io
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables from .env
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    echo "Error: .env not found at $PROJECT_ROOT/.env (copy from .env.example)." >&2
    exit 1
fi
set -a
# shellcheck disable=SC1091
. "$PROJECT_ROOT/.env"
set +a
: "${HEALTHCHECKS_PING_URL:?}"

# Configuration
CURL_TIMEOUT=15
CURL_RETRIES=2

# Track overall status
OVERALL_EXIT_CODE=0
FAILED_SITES=()

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Parse JSON - uses jq if available, otherwise falls back to grep/sed
parse_json_field() {
    local file="$1"
    local field="$2"
    
    if command -v jq &> /dev/null; then
        jq -r ".$field // empty" "$file"
    else
        grep "\"$field\"" "$file" | head -1 | sed 's/.*"'"$field"'": *"\([^"]*\)".*/\1/'
    fi
}

# Parse expectedTexts array - returns newline-separated values
parse_expected_texts() {
    local file="$1"
    
    if command -v jq &> /dev/null; then
        jq -r '.healthCheck.expectedTexts // empty | .[]?' "$file" 2>/dev/null
    else
        # Fallback: extract texts from the JSON array using grep/sed
        # This handles the format: "expectedTexts": ["Text1", "Text2"]
        local line
        line=$(grep -o '"expectedTexts": *\[[^]]*\]' "$file" 2>/dev/null | head -1)
        if [ -n "$line" ]; then
            # Extract array contents and split by comma
            echo "$line" | sed 's/.*\[\(.*\)\]/\1/' | tr ',' '\n' | sed 's/^ *"//;s/" *$//'
        fi
    fi
}

# Check a single website
check_website() {
    local domain="$1"
    local name="$2"
    local expected_texts="$3"  # Newline-separated list
    
    log "Checking $name ($domain)..."
    
    # Fetch the website
    local response
    if ! response=$(curl -s --max-time "$CURL_TIMEOUT" --retry "$CURL_RETRIES" "https://$domain" 2>&1); then
        log_error "$name: Failed to fetch https://$domain"
        return 1
    fi
    
    # Check for each expected text
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

# Main loop through all website configurations
log "Starting uptime checks..."

while IFS= read -r website_file; do
    [ -z "$website_file" ] && continue

    domain=$(parse_json_field "$website_file" "domain")
    name=$(parse_json_field "$website_file" "name")
    expected_texts=$(parse_expected_texts "$website_file")
    
    # Skip if no health check configured
    if [ -z "$expected_texts" ]; then
        log "Skipping $name (no healthCheck configured)"
        continue
    fi
    
    # Check the website
    if ! check_website "$domain" "$name" "$expected_texts"; then
        OVERALL_EXIT_CODE=1
        FAILED_SITES+=("$name")
    fi
done < <("$SCRIPT_DIR/util/list-website-json-files.sh")

# Report results
echo ""
if [ $OVERALL_EXIT_CODE -eq 0 ]; then
    log "All websites are healthy!"
else
    log_error "Failed sites: ${FAILED_SITES[*]}"
fi

# Ping healthchecks.io with the result
log "Pinging healthchecks.io..."
if curl -s --retry 3 --max-time 10 "${HEALTHCHECKS_PING_URL}/${OVERALL_EXIT_CODE}" > /dev/null; then
    log "Healthchecks.io ping sent (exit code: $OVERALL_EXIT_CODE)"
else
    log_error "Failed to ping healthchecks.io"
fi

exit $OVERALL_EXIT_CODE
