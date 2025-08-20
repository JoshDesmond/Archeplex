#!/bin/bash
# Deploy website to Archeplex server
set -euo pipefail

SERVER="149.28.63.63"
USER="desmond"
SSH_PORT="2020"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if website path argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <website-path>"
    echo "Example: $0 /home/jdesmond/Code/personal/AutomatiSolutions/AutomatiSolutions"
    exit 1
fi

WEBSITE_PATH="$1"

# Verify website path exists and contains package.json
if [ ! -f "$WEBSITE_PATH/package.json" ]; then
    echo "Error: package.json not found in $WEBSITE_PATH"
    exit 1
fi

# Extract package name from package.json
PACKAGE_NAME=$(grep '"name"' "$WEBSITE_PATH/package.json" | head -1 | sed 's/.*"name": *"\([^"]*\)".*/\1/')

if [ -z "$PACKAGE_NAME" ]; then
    echo "Error: Could not extract package name from package.json"
    exit 1
fi

# Look up domain from websites configuration
DOMAIN=""
for website_file in "$PROJECT_ROOT"/websites/*.json; do
    if [ -f "$website_file" ]; then
        file_name=$(grep '"name"' "$website_file" | head -1 | sed 's/.*"name": *"\([^"]*\)".*/\1/')
        if [ "$file_name" = "$PACKAGE_NAME" ]; then
            DOMAIN=$(grep '"domain"' "$website_file" | head -1 | sed 's/.*"domain": *"\([^"]*\)".*/\1/')
            break
        fi
    fi
done

if [ -z "$DOMAIN" ]; then
    echo "Error: No domain configuration found for package: $PACKAGE_NAME"
    exit 1
fi

echo "Deploying $PACKAGE_NAME to $DOMAIN"

# Build the website
echo "Building website..."
cd "$WEBSITE_PATH"

if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
fi

npm run build

# TODO: all websites are vite, so, the default is just "dist"? No need to user anything else
# Check if build directory exists (try common names)
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

# Test SSH connection
echo "Testing SSH connection..."
if ! ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o BatchMode=yes "$USER@$SERVER" exit 2>/dev/null; then
    echo "Error: Cannot connect to $USER@$SERVER:$SSH_PORT"
    echo "Please ensure SSH agent is running and keys are loaded:"
    echo "  eval \$(ssh-agent -s) && ssh-add ~/.ssh/<your-key>"
    exit 1
fi

# Deploy files
echo "Deploying files to /var/www/$DOMAIN..."
rsync -avz --delete --mkpath \
    -e "ssh -p $SSH_PORT" \
    "$BUILD_DIR/" \
    "$USER@$SERVER:/var/www/$DOMAIN/"

echo "Deployment complete! Website deployed to /var/www/$DOMAIN"
