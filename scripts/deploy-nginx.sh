#!/bin/bash
# Deploy nginx configurations to Archeplex server (one site or all).
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTION | WEBSITE_NAME]

Generate nginx conf.d snippets from websites metadata and push to the server.

  WEBSITE_NAME    Deploy only this site (folder id or JSON "name")
  --all           Regenerate and deploy configs for every site (default)
  -h, --help      Show this help

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

WEBSITE_NAME=""
DEPLOY_ALL=1

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --all)
            DEPLOY_ALL=1
            WEBSITE_NAME=""
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 1
            ;;
        *)
            if [ -n "$WEBSITE_NAME" ]; then
                echo "Unexpected extra argument: $1" >&2
                show_help >&2
                exit 1
            fi
            WEBSITE_NAME="$1"
            DEPLOY_ALL=0
            shift
            ;;
    esac
done

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

if [ "$DEPLOY_ALL" -eq 0 ]; then
    if ! run_health_phase "pre-deploy" "$WEBSITE_NAME"; then
        log "Pre-deploy health check failed (continuing nginx deploy)."
    fi
fi

if ! ssh-add -l >/dev/null 2>&1; then
    echo "SSH agent is not running or has no keys loaded."
    echo "Please run: eval \$(ssh-agent -s) && ssh-add ~/.ssh/<your-key>"
    exit 1
fi

# Test SSH connection
echo "Testing SSH connection..."
if ! ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o BatchMode=yes "$USER@$SERVER" exit 2>/dev/null; then
    echo "Cannot connect to $USER@$SERVER:$SSH_PORT"
    echo "SSH authentication failed. Please check your SSH key setup."
    exit 1
fi

# Create a temporary directory for generated configs
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

SINGLE_SITE_JSON=""

inject_optional_site_nginx() {
    local conf_path="$1"
    local website_json="$2"
    local snippet="${website_json%.json}.nginx.conf"
    local blocks

    [ ! -f "$snippet" ] && return 0

    blocks=$(cat "$snippet")
    [ -z "$blocks" ] && return 0

    awk -v blocks="$blocks" '
        /# Main location block/ && !inserted {
            print blocks
            inserted=1
        }
        { print }
    ' "$conf_path" > "$conf_path.tmp"
    mv "$conf_path.tmp" "$conf_path"
}

generate_for_json() {
    local website_file="$1"
    local domain
    domain=$(grep -o '"domain": "[^"]*"' "$website_file" | cut -d'"' -f4)
    if [ -z "$domain" ]; then
        echo "Error: missing domain in $website_file" >&2
        return 1
    fi
    echo "  Generating config for domain: $domain"
    sed "s/example\.com/$domain/g" "$PROJECT_ROOT/nginx/conf.d/site-template.conf" > "$TEMP_DIR/$domain.conf"
    sed -i "s|/var/www/example.com|/var/www/$domain|g" "$TEMP_DIR/$domain.conf"
    inject_optional_site_nginx "$TEMP_DIR/$domain.conf" "$website_file"
}

echo "Generating domain-specific nginx configurations..."

if [ "$DEPLOY_ALL" -eq 1 ]; then
    while IFS= read -r website_file; do
        [ -z "$website_file" ] && continue
        generate_for_json "$website_file"
    done < <("$SCRIPT_DIR/util/list-website-json-files.sh")
else
    SINGLE_SITE_JSON="$("$SCRIPT_DIR/util/resolve-website-json.sh" "$WEBSITE_NAME")"
    generate_for_json "$SINGLE_SITE_JSON"
fi

# Create a deployment script on the fly
cat > "$TEMP_DIR/deploy.sh" << 'EOF'
#!/bin/bash
set -e

# Move nginx.conf
sudo mv /tmp/nginx.conf /etc/nginx/nginx.conf

# Move all domain configs
for config in /tmp/*.conf; do
    if [ -f "$config" ]; then
        sudo mv "$config" /etc/nginx/conf.d/
    fi
done

# Validate nginx config before reload
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
EOF

# Copy all files at once
echo "Copying files to server..."
scp -P "$SSH_PORT" "$PROJECT_ROOT/nginx/nginx.conf" "$USER@$SERVER:/tmp/nginx.conf"
scp -P "$SSH_PORT" "$TEMP_DIR"/*.conf "$USER@$SERVER:/tmp/"

# Execute deployment script (single sudo prompt)
echo "Deploying configurations..."
scp -P "$SSH_PORT" "$TEMP_DIR/deploy.sh" "$USER@$SERVER:/tmp/deploy.sh"
ssh -p "$SSH_PORT" -t "$USER@$SERVER" "bash /tmp/deploy.sh && rm /tmp/deploy.sh"

echo "Deployment complete!"

if [ "$DEPLOY_ALL" -eq 1 ]; then
    echo ""
    echo "Re-run certify-website.sh (or certbot) per domain to restore TLS if configs changed."
else
    domain=$(grep -o '"domain": "[^"]*"' "$SINGLE_SITE_JSON" | cut -d'"' -f4)
    if ! run_health_phase "post-deploy" "$WEBSITE_NAME"; then
        log "Post-deploy health check failed."
        exit 1
    fi
    echo ""
    echo "If TLS is new or broken for $domain, run on the server: sudo certify-website.sh $domain"
fi
