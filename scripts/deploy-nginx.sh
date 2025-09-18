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
