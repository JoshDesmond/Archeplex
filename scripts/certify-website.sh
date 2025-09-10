#!/bin/bash
set -e

# Script to generate SSL certificates for websites using Let's Encrypt/Certbot
# Usage: ./certify-website.sh <domain>
# Example: ./certify-website.sh automatisolutions.com

# Configuration variables
readonly SCRIPT_VERSION="1.0.0"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Check if domain argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <domain>"
    echo "Example: $0 automatisolutions.com"
    exit 1
fi

DOMAIN="$1"

# Validate domain format (basic check)
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    echo "Error: Invalid domain format: $DOMAIN"
    exit 1
fi

echo "Starting SSL certification for domain: $DOMAIN (v${SCRIPT_VERSION})"

# Check if nginx configuration exists for the domain
if [ ! -f "/etc/nginx/conf.d/${DOMAIN}.conf" ]; then
    echo "Error: Nginx configuration not found at /etc/nginx/conf.d/${DOMAIN}.conf"
    echo "Please ensure the website is deployed first using deploy-nginx.sh"
    exit 1
fi

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot and nginx plugin..."
    apt update
    apt install -y certbot python3-certbot-nginx
else
    echo "Certbot is already installed"
fi

# Check if the domain is accessible on port 80
echo "Verifying domain accessibility on port 80..."
if ! curl -s --connect-timeout 10 "http://${DOMAIN}" > /dev/null; then
    echo "Warning: Domain ${DOMAIN} is not accessible on port 80"
    echo "This may prevent certificate generation. Please ensure:"
    echo "1. DNS is properly configured and pointing to this server"
    echo "2. Port 80 is open in the firewall"
    echo "3. Nginx is running and serving the site"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Generate SSL certificate using certbot
echo "Generating SSL certificate for ${DOMAIN}..."
if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email developerdesmond@gmail.com; then
    echo "SSL certificate generated successfully!"
else
    echo "Error: Failed to generate SSL certificate"
    echo "Please check the certbot output above for details"
    exit 1
fi

# Test nginx configuration
echo "Testing nginx configuration..."
if nginx -t; then
    echo "Nginx configuration is valid"
else
    echo "Error: Nginx configuration is invalid"
    echo "Please check the configuration and try again"
    exit 1
fi

# Reload nginx to apply changes
echo "Reloading nginx..."
systemctl reload nginx


# Display certificate information
echo ""
echo "=== SSL Certificate Information ==="
echo "Domain: $DOMAIN"
echo "Certificate expires: $(openssl x509 -in /etc/letsencrypt/live/${DOMAIN}/cert.pem -noout -enddate | cut -d= -f2)"
echo ""

# Verify HTTPS is working
echo "Testing HTTPS connection..."
if curl -s --connect-timeout 10 "https://${DOMAIN}" > /dev/null; then
    echo "✅ HTTPS is working correctly for ${DOMAIN}"
else
    echo "⚠️  HTTPS test failed. Please check the configuration"
fi

echo ""
echo "SSL certification complete for ${DOMAIN}!"
echo "Your website is now accessible via HTTPS: https://${DOMAIN}"
echo ""
echo "You can manually renew with: sudo certbot renew" 
