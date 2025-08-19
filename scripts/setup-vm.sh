#!/bin/bash
set -e

# Script assumes it's being run from the repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${REPO_ROOT}/configs"

# Verify we have the configs directory
if [ ! -d "$CONFIG_DIR" ]; then
    echo "Error: configs directory not found. Are you running from the repository?"
    exit 1
fi

# Configuration variables
readonly NEW_USER="desmond"
readonly SSH_PORT="2020"
readonly SCRIPT_VERSION="1.0.0"

# ============================================
# SYSTEM UPDATES AND ESSENTIAL PACKAGES
# ============================================
echo "Starting system initialization (v${SCRIPT_VERSION})"

apt update && apt upgrade -y && apt-get dist-upgrade -y && apt-get autoremove -y
apt install -y ufw fail2ban unattended-upgrades sudo curl wget lynis nginx

# ============================================
# USER CREATION AND CONFIGURATION
# ============================================
echo "Creating user '${NEW_USER}' with sudo privileges..."

# Create new user with sudo privileges
useradd -m -s /bin/bash ${NEW_USER}

# Add ${NEW_USER} to sudo and www-data groups
usermod -aG sudo,www-data ${NEW_USER}

# Copy root's authorized_keys to ${NEW_USER}
mkdir -p /home/${NEW_USER}/.ssh
cp /root/.ssh/authorized_keys /home/${NEW_USER}/.ssh/
chown -R ${NEW_USER}:${NEW_USER} /home/${NEW_USER}/.ssh
chmod 700 /home/${NEW_USER}/.ssh
chmod 600 /home/${NEW_USER}/.ssh/authorized_keys

# ============================================
# FIREWALL CONFIGURATION
# ============================================
echo "Configuring UFW firewall..."

ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp  # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw --force enable

# ============================================
# SSH HARDENING
# ============================================
echo "Hardening SSH configuration..."

# Backup original SSH config
cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

# Basic SSH Configuration
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i "s/^#*Port.*/Port ${SSH_PORT}/" /etc/ssh/sshd_config # Use port ${SSH_PORT} for SSH

sed -i 's/^#*Protocol.*/Protocol 2/' /etc/ssh/sshd_config
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config
sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config

systemctl restart sshd

# ============================================
# FAIL2BAN CONFIGURATION
# ============================================
echo "Configuring fail2ban..."

# Sanity check: Validate that jail.local has the correct SSH port
if ! grep -q "port = ${SSH_PORT}" "${CONFIG_DIR}/fail2ban/jail.local"; then
    echo "Warning: fail2ban jail.local config doesn't contain port ${SSH_PORT}"
    echo "Please ensure jail.local is configured for the correct SSH port"
fi

# Copy the configuration
cp "${CONFIG_DIR}/fail2ban/jail.local" /etc/fail2ban/jail.local

# Enable and start fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

# ============================================
# AUTOMATIC UPDATES
# ============================================
echo "Configuring automatic security upgrades..."

cp "${CONFIG_DIR}/apt/50unattended-upgrades" /etc/apt/apt.conf.d/50unattended-upgrades
cp "${CONFIG_DIR}/apt/20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades

# ============================================
# SWAP CONFIGURATION
# ============================================
echo "Configuring swapfile..."
if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    # Make permanent
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    
    # Copy swappiness configuration
    cp "${CONFIG_DIR}/sysctl/99-swappiness.conf" /etc/sysctl.d/99-swappiness.conf
    sysctl -p /etc/sysctl.d/99-swappiness.conf
fi

echo "User Setup complete. You can now SSH as: ssh ${NEW_USER}@<server-ip> -p ${SSH_PORT}"
echo "To check for additional security issues, run:"
echo "  sudo lynis audit system"
