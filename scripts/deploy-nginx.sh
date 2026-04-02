#!/bin/bash
# Deploy nginx configurations to Archeplex server

set -euo pipefail

SERVER="149.28.63.63"
USER="desmond"
SSH_PORT="2020"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if SSH agent is running and has keys loaded
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
trap "rm -rf $TEMP_DIR" EXIT

echo "Generating domain-specific nginx configurations..."

generate_custom_route_blocks() {
    local website_file="$1"
    local route_entries route_entry route_path route_file

    # This keeps parsing grep-friendly for speed right now.
    # // TODO consider jq for robust JSON parsing as route rules evolve.
    route_entries=$(
        awk '
            /"customStaticRoutes"[[:space:]]*:/ { in_routes=1; next }
            in_routes && /\]/ { in_routes=0; next }
            in_routes { print }
        ' "$website_file" \
        | grep -o '"[^"]*"' \
        | tr -d '"' \
        | sort
    )

    [ -z "$route_entries" ] && return

    echo "    # Custom static route overrides"
    echo "    # HACK: This exists primarily for AutomatiSolutions OG route HTML files."
    while IFS= read -r route_entry; do
        [ -z "$route_entry" ] && continue
        route_path="${route_entry%%=>*}"
        route_file="${route_entry#*=>}"

        if [ "$route_path" = "$route_file" ]; then
            echo "  Skipping invalid custom route entry in $website_file: $route_entry" >&2
            continue
        fi

        printf '    location = %s {\n' "$route_path"
        printf '        try_files %s /index.html;\n' "$route_file"
        printf '    }\n\n'
    done <<< "$route_entries"
}

shopt -s nullglob
website_files=( "$PROJECT_ROOT"/websites/*.json )
IFS=$'\n' website_files=( $(printf '%s\n' "${website_files[@]}" | sort) )
unset IFS

# Iterate through websites directory in stable order and generate configs
for website_file in "${website_files[@]}"; do
    # Extract domain from JSON
    domain=$(grep -o '"domain": "[^"]*"' "$website_file" | cut -d'"' -f4)

    if [ -n "$domain" ]; then
        echo "  Generating config for domain: $domain"

        # Create domain-specific config from template
        sed "s/example\.com/$domain/g" "$PROJECT_ROOT/nginx/conf.d/site-template.conf" > "$TEMP_DIR/$domain.conf"

        # Update root path in the generated config
        sed -i "s|/var/www/example.com|/var/www/$domain|g" "$TEMP_DIR/$domain.conf"

        custom_route_blocks="$(generate_custom_route_blocks "$website_file")"
        if [ -n "$custom_route_blocks" ]; then
            awk -v blocks="$custom_route_blocks" '
                /# Main location block/ && !inserted {
                    print blocks
                    inserted=1
                }
                { print }
            ' "$TEMP_DIR/$domain.conf" > "$TEMP_DIR/$domain.conf.tmp"
            mv "$TEMP_DIR/$domain.conf.tmp" "$TEMP_DIR/$domain.conf"
        fi
    fi
done

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
