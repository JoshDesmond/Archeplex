#!/bin/bash

# Example Website Deployment Script
# Builds and deploys a Vite React app to VPS
set -euo pipefail

# Configuration - EDIT THESE VALUES
VPS_HOST="107.191.41.97"
VPS_USER="web"
VPS_PORT="22"
REMOTE_DIR="/var/www/html"
LOCAL_BUILD_DIR="dist"  # Vite default build directory

# Note: Actual Script should deploy to 149.28.63.63, port 2020, /var/www/example.com, and user: desmond

# Note: colors or print_ functions - just use echo

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}→${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_info "Checking prerequisites..."
if ! command -v npm &> /dev/null; then
    print_error "npm is not installed. Please install Node.js and npm."
    exit 1
fi

if ! command -v ssh &> /dev/null; then
    print_error "ssh is not installed."
    exit 1
fi

if ! command -v rsync &> /dev/null; then
    print_warning "rsync is not installed. Falling back to scp (slower)."
    USE_SCP=true
else
    USE_SCP=false
fi

# Check if package.json exists
if [ ! -f "package.json" ]; then
    print_error "package.json not found. Are you in the project directory?"
    exit 1
fi

# Build the project
print_info "Building the project..."

# Install dependencies if node_modules doesn't exist
if [ ! -d "node_modules" ]; then
    print_info "Installing dependencies..."
    npm install
fi

# Run build
npm run build

if [ $? -ne 0 ]; then
    print_error "Build failed!"
    exit 1
fi

print_status "Build completed successfully"

# Check if build directory exists
if [ ! -d "$LOCAL_BUILD_DIR" ]; then
    print_error "Build directory '$LOCAL_BUILD_DIR' not found. Did the build succeed?"
    exit 1
fi

# Test SSH connection
print_info "Testing SSH connection..."
if ! ssh -p "$VPS_PORT" -o ConnectTimeout=5 -o BatchMode=yes "$VPS_USER@$VPS_HOST" exit 2>/dev/null; then
    print_error "Cannot connect to $VPS_USER@$VPS_HOST:$VPS_PORT"
    print_error "SSH authentication failed. This could be due to:"
    print_error "  1. SSH agent not running - run 'eval \$(ssh-agent -s)' and 'ssh-add ~/.ssh/your_key'"
    print_error "  2. SSH key not added to agent - run 'ssh-add ~/.ssh/your_key'"
    print_error "  3. SSH key not authorized on server - add your public key to ~/.ssh/authorized_keys on the server"
    print_error "  4. Incorrect SSH configuration - check your ~/.ssh/config file"
    print_error ""
    print_error "To start SSH agent and add your key:"
    print_error "  eval \$(ssh-agent -s)"
    print_error "  ssh-add ~/.ssh/id_rsa  # or your specific key file"
    exit 1
fi
print_status "SSH connection successful"

# Deploy files
print_info "Deploying files to $VPS_HOST..."

rsync -avz --delete \
    -e "ssh -p $VPS_PORT" \
    "$LOCAL_BUILD_DIR/" \
    "$VPS_USER@$VPS_HOST:$REMOTE_DIR/"

if [ $? -eq 0 ]; then
    print_status "Deployment completed successfully with rsync"
else
    print_error "Deployment failed"
    exit 1
fi

# Set proper permissions
print_info "Setting permissions..."
ssh -p "$VPS_PORT" "$VPS_USER@$VPS_HOST" "
    find $REMOTE_DIR -type f -exec chmod 644 {} \;
    find $REMOTE_DIR -type d -exec chmod 755 {} \;
"

# Test the deployment
print_info "Testing deployment..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$VPS_HOST/" || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    print_status "Website is accessible!"
    print_info "Visit http://$VPS_HOST to see your site"
else
    print_warning "Website returned HTTP status: $HTTP_STATUS"
    print_warning "This might be normal if you haven't configured DNS/HTTPS yet"
fi

# Show deployment summary
echo ""
echo "======================================"
print_status "Deployment Summary"
echo "======================================"
echo "• Files deployed to: $VPS_USER@$VPS_HOST:$REMOTE_DIR"
echo "• Website URL: http://$VPS_HOST"
echo "======================================"

print_status "Deployment complete!"
