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

# Iterate through websites directory and generate configs
for website_file in "$PROJECT_ROOT"/websites/*.json; do
    if [ -f "$website_file" ]; then
        # Extract domain from JSON
        domain=$(grep -o '"domain": "[^"]*"' "$website_file" | cut -d'"' -f4)
        
        if [ -n "$domain" ]; then
            echo "  Generating config for domain: $domain"
            
            # Create domain-specific config from template
            sed "s/example\.com/$domain/g" "$PROJECT_ROOT/nginx/conf.d/site-template.conf" > "$TEMP_DIR/$domain.conf"
            
            # Update root path in the generated config
            sed -i "s|/var/www/example.com|/var/www/$domain|g" "$TEMP_DIR/$domain.conf"
        fi
    fi
done

# Deploy main nginx.conf
echo "Deploying main nginx.conf..."
scp -P "$SSH_PORT" "$PROJECT_ROOT/nginx/nginx.conf" "$USER@$SERVER:/tmp/nginx.conf"
ssh -p "$SSH_PORT" -t -q "$USER@$SERVER" "sudo mv /tmp/nginx.conf /etc/nginx/nginx.conf"

# Deploy generated domain configs
echo "Deploying generated domain configurations..."
for config_file in "$TEMP_DIR"/*.conf; do
    if [ -f "$config_file" ]; then
        filename=$(basename "$config_file")
        echo "  Deploying $filename..."
        scp -P "$SSH_PORT" "$config_file" "$USER@$SERVER:/tmp/$filename"
        ssh -p "$SSH_PORT" -t -q "$USER@$SERVER" "sudo mv /tmp/$filename /etc/nginx/conf.d/$filename"
    fi
done

# Reload nginx to apply changes
echo "Reloading nginx..."
ssh -p "$SSH_PORT" -t -q "$USER@$SERVER" "sudo systemctl reload nginx"

echo "Deployment complete!"
