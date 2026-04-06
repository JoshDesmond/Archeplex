#!/bin/bash
# Deploy website to Archeplex server
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

show_help() {
    cat <<EOF
Usage: $(basename "$0") [-h | --help] <website-path>

Build the site locally, rsync static output to the server under /var/www/<domain>.

  <website-path>   Directory containing package.json (project root)
  -h, --help       Show this help

Requires .env: ARCHEPLEX_SERVER, ARCHEPLEX_SSH_USER, ARCHEPLEX_SSH_PORT
EOF
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

run_health_phase() {
    local phase="$1"
    local site="$2"
    log "[$phase] Website health check ($site)..."
    if "$SCRIPT_DIR/check-website-health.sh" "$site"; then
        log "[$phase] Health check: OK"
    else
        log "[$phase] Health check: FAILED"
        return 1
    fi
}

WEBSITE_PATH=""
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 1
            ;;
        *)
            if [ -n "$WEBSITE_PATH" ]; then
                echo "Unexpected extra argument: $1" >&2
                show_help >&2
                exit 1
            fi
            WEBSITE_PATH="$1"
            shift
            ;;
    esac
done

if [ -z "$WEBSITE_PATH" ]; then
    show_help >&2
    exit 1
fi

if [ ! -f "$PROJECT_ROOT/.env" ]; then
    echo "Error: .env not found at $PROJECT_ROOT/.env (copy from .env.example)." >&2
    exit 1
fi
set -a
# shellcheck disable=SC1091
. "$PROJECT_ROOT/.env"
set +a
: "${ARCHEPLEX_SERVER:?}" "${ARCHEPLEX_SSH_USER:?}" "${ARCHEPLEX_SSH_PORT:?}"
SERVER="$ARCHEPLEX_SERVER"
USER="$ARCHEPLEX_SSH_USER"
SSH_PORT="$ARCHEPLEX_SSH_PORT"

if [ ! -f "$WEBSITE_PATH/package.json" ]; then
    echo "Error: package.json not found in $WEBSITE_PATH"
    exit 1
fi

PACKAGE_NAME=$(grep '"name"' "$WEBSITE_PATH/package.json" | head -1 | sed 's/.*"name": *"\([^"]*\)".*/\1/')

if [ -z "$PACKAGE_NAME" ]; then
    echo "Error: Could not extract package name from package.json"
    exit 1
fi

DOMAIN=""
while IFS= read -r website_file; do
    [ -z "$website_file" ] && continue
    file_name=$(grep '"name"' "$website_file" | head -1 | sed 's/.*"name": *"\([^"]*\)".*/\1/')
    if [ "$file_name" = "$PACKAGE_NAME" ]; then
        DOMAIN=$(grep '"domain"' "$website_file" | head -1 | sed 's/.*"domain": *"\([^"]*\)".*/\1/')
        break
    fi
done < <("$SCRIPT_DIR/util/list-website-json-files.sh")

if [ -z "$DOMAIN" ]; then
    echo "Error: No domain configuration found for package: $PACKAGE_NAME"
    exit 1
fi

if ! run_health_phase "pre-deploy" "$PACKAGE_NAME"; then
    log "Pre-deploy health check failed (continuing deployment)."
fi

echo "Deploying $PACKAGE_NAME to $DOMAIN"

echo "Building website..."
"$SCRIPT_DIR/util/verify-dotenv.sh" "$WEBSITE_PATH"
cd "$WEBSITE_PATH"

if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
fi

npm run build

BUILD_DIR=""
for dir in "dist" "build" "out" ".next"; do
    if [ -d "$dir" ]; then
        BUILD_DIR="$dir"
        break
    fi
done

if [ -z "$BUILD_DIR" ]; then
    echo "Error: Build directory not found."
    exit 1
fi

echo "Build completed. Found build directory: $BUILD_DIR"

echo "Testing SSH connection..."
if ! ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o BatchMode=yes "$USER@$SERVER" exit 2>/dev/null; then
    echo "Error: Cannot connect to $USER@$SERVER:$SSH_PORT"
    echo "Please ensure SSH agent is running and keys are loaded:"
    echo "  eval \$(ssh-agent -s) && ssh-add ~/.ssh/<your-key>"
    exit 1
fi

echo "Deploying files to /var/www/$DOMAIN..."
rsync -avz --delete --mkpath \
    -e "ssh -p $SSH_PORT" \
    "$BUILD_DIR/" \
    "$USER@$SERVER:/var/www/$DOMAIN/"

echo "Deployment complete! Website deployed to /var/www/$DOMAIN"

if ! run_health_phase "post-deploy" "$PACKAGE_NAME"; then
    log "Post-deploy health check failed."
    exit 1
fi
