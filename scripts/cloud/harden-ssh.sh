#!/bin/bash
#
# VPS Security Hardening Script
# Compatible with Ubuntu 20.04, 22.04, 24.04
# Run as root or with sudo privileges
#
# Usage: ./harden-vps.sh

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
    echo ""
}

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    print_error "Please run as root or with sudo privileges"
    exit 1
fi

SUDO=""
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
fi

print_header "VPS Security Hardening Script"

# Security Audit
print_header "Step 1: Current Security Audit"

echo "Current user: $(whoami)"
echo "System: $(lsb_release -d | cut -f2)"
echo "Kernel: $(uname -r)"
echo ""

echo "SSH Configuration:"
$SUDO sshd -T 2>/dev/null | grep -E "passwordauthentication|permitrootlogin|pubkeyauthentication" || echo "Unable to check SSH config"
echo ""

echo "Fail2ban status:"
if systemctl is-active --quiet fail2ban 2>/dev/null; then
    print_status "Fail2ban is running"
else
    print_warning "Fail2ban is not running"
fi
echo ""

echo "UFW status:"
$SUDO ufw status 2>/dev/null | head -5 || echo "UFW not configured"
echo ""

echo "Attack attempts:"
failed_count=$($SUDO grep -c "Failed password\|Invalid user" /var/log/auth.log 2>/dev/null || echo 0)
echo "Failed login attempts: $failed_count"
echo ""

read -p "Continue with hardening? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Exiting."
    exit 0
fi

# Update system
print_header "Step 2: System Update"

print_status "Updating package lists..."
$SUDO apt update

print_status "Upgrading packages..."
DEBIAN_FRONTEND=noninteractive $SUDO apt upgrade -y

# Install required packages
print_header "Step 3: Installing Security Packages"

print_status "Installing ufw, fail2ban, curl..."
$SUDO apt install -y ufw fail2ban curl

# Create ubuntu user if needed
print_header "Step 4: User Configuration"

CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" = "root" ]; then
    if id "ubuntu" &>/dev/null; then
        print_status "Ubuntu user already exists"
    else
        print_status "Creating ubuntu user..."
        $SUDO adduser --disabled-password --gecos "Ubuntu User" ubuntu
        
        # Add to sudo group
        $SUDO usermod -aG sudo ubuntu
        
        # Setup passwordless sudo
        echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | $SUDO tee /etc/sudoers.d/ubuntu > /dev/null
        $SUDO chmod 440 /etc/sudoers.d/ubuntu
        
        print_status "Ubuntu user created with sudo access"
    fi
    
    # Copy SSH keys
    print_status "Setting up SSH keys for ubuntu user..."
    $SUDO mkdir -p /home/ubuntu/.ssh
    $SUDO chmod 700 /home/ubuntu/.ssh
    
    if [ -f /root/.ssh/authorized_keys ]; then
        $SUDO cp /root/.ssh/authorized_keys /home/ubuntu/.ssh/authorized_keys
        print_status "SSH keys copied from root"
    else
        print_warning "No SSH keys found in /root/.ssh/authorized_keys"
        echo ""
        read -p "Paste your SSH public key (or press Enter to skip): " ssh_key
        if [ -n "$ssh_key" ]; then
            echo "$ssh_key" | $SUDO tee /home/ubuntu/.ssh/authorized_keys > /dev/null
            print_status "SSH key added"
        else
            print_warning "No SSH key added - you'll need to add one manually"
        fi
    fi
    
    $SUDO chmod 600 /home/ubuntu/.ssh/authorized_keys 2>/dev/null
    $SUDO chown -R ubuntu:ubuntu /home/ubuntu/.ssh
else
    print_status "Running as non-root user: $CURRENT_USER"
fi

# Configure SSH hardening
print_header "Step 5: SSH Hardening"

# Backup SSH config
$SUDO cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d-%H%M%S)
print_status "SSH config backed up"

# Disable cloud-init SSH password auth (if cloud-init exists)
if [ -d /etc/cloud ]; then
    print_status "Configuring cloud-init to disable password auth..."
    $SUDO mkdir -p /etc/cloud/cloud.cfg.d
    cat | $SUDO tee /etc/cloud/cloud.cfg.d/99-disable-ssh-pw.cfg > /dev/null <<'EOF'
#cloud-config
ssh_pwauth: false
disable_root: true
EOF
    
    # Update existing cloud-init SSH config if it exists
    if [ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]; then
        $SUDO sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/50-cloud-init.conf
        if ! grep -q "PermitRootLogin" /etc/ssh/sshd_config.d/50-cloud-init.conf; then
            echo "PermitRootLogin no" | $SUDO tee -a /etc/ssh/sshd_config.d/50-cloud-init.conf > /dev/null
        fi
    fi
fi

# Create hardening config (ZZ prefix ensures it loads last)
print_status "Creating SSH hardening configuration..."
$SUDO mkdir -p /etc/ssh/sshd_config.d
cat | $SUDO tee /etc/ssh/sshd_config.d/ZZ-security-hardening.conf > /dev/null <<'EOF'
# Security Hardening - Loaded last (ZZ prefix)
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
X11Forwarding no
EOF

print_status "SSH hardening configured"

# Test SSH configuration
print_status "Testing SSH configuration..."
if $SUDO sshd -t; then
    print_status "SSH configuration is valid"
else
    print_error "SSH configuration has errors!"
    exit 1
fi

# Show effective configuration
echo ""
echo "Effective SSH configuration:"
$SUDO sshd -T | grep -E "passwordauthentication|permitrootlogin|pubkeyauthentication"
echo ""

# Configure Fail2ban
print_header "Step 6: Fail2ban Configuration"

print_status "Configuring fail2ban for SSH protection..."
cat | $SUDO tee /etc/fail2ban/jail.d/sshd.conf > /dev/null <<'EOF'
[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

$SUDO systemctl enable fail2ban
$SUDO systemctl restart fail2ban
print_status "Fail2ban configured and started"

# Configure UFW
print_header "Step 7: Firewall Configuration"

print_status "Configuring UFW firewall..."

# Reset UFW to clean state
$SUDO ufw --force reset > /dev/null

# Set defaults
$SUDO ufw default deny incoming
$SUDO ufw default allow outgoing

# Allow SSH
$SUDO ufw allow 22/tcp comment 'SSH'

# Allow Tailscale (if you plan to use it)
# $SUDO ufw allow 41641/udp comment 'Tailscale'

# Enable UFW
echo "y" | $SUDO ufw enable > /dev/null

print_status "UFW firewall configured and enabled"

# Enable IP forwarding (for VPN/Tailscale exit nodes)
print_header "Step 8: Network Configuration"

print_status "Enabling IP forwarding for VPN functionality..."
cat | $SUDO tee /etc/sysctl.d/99-ip-forwarding.conf > /dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

$SUDO sysctl -p /etc/sysctl.d/99-ip-forwarding.conf > /dev/null
print_status "IP forwarding enabled"

# Restart SSH
print_header "Step 9: Applying Changes"

print_warning "About to restart SSH service..."
echo ""
echo "CRITICAL: Before proceeding, verify in a NEW terminal that you can:"
echo "  1. SSH as ubuntu user: ssh -i your-key ubuntu@$(hostname -I | awk '{print $1}')"
echo "  2. Use sudo: sudo whoami"
echo ""
read -p "Have you tested and confirmed access works? (yes/no): " ssh_confirm

if [ "$ssh_confirm" = "yes" ]; then
    print_status "Restarting SSH service..."
    $SUDO systemctl restart ssh 2>/dev/null || $SUDO systemctl restart sshd
    print_status "SSH service restarted"
else
    print_warning "SSH not restarted. Restart manually when ready:"
    echo "  sudo systemctl restart ssh"
fi

# Final security audit
print_header "Step 10: Final Security Audit"

echo "SSH Configuration:"
$SUDO sshd -T | grep -E "passwordauthentication|permitrootlogin|pubkeyauthentication"
echo ""

echo "Fail2ban Status:"
$SUDO systemctl status fail2ban --no-pager | grep "Active:"
$SUDO fail2ban-client status sshd 2>/dev/null || echo "SSH jail status not available yet"
echo ""

echo "UFW Status:"
$SUDO ufw status verbose | head -10
echo ""

# Success message
print_header "✓ Security Hardening Complete!"

cat << 'EOF'
Security improvements applied:
  ✓ System updated to latest packages
  ✓ Ubuntu user created (if needed) with sudo access
  ✓ SSH password authentication DISABLED
  ✓ Root login via SSH DISABLED
  ✓ SSH key authentication ENABLED
  ✓ Fail2ban installed and monitoring SSH
  ✓ UFW firewall configured and active
  ✓ IP forwarding enabled (for VPN use)

IMPORTANT REMINDERS:
  • Always connect as: ssh -i your-key ubuntu@YOUR_IP
  • Root SSH login is now blocked (use: sudo su -)
  • Password SSH login is now blocked (keys only)
  • Failed login attempts are auto-banned by fail2ban

CONNECTION COMMANDS:
  Normal SSH:     ssh -i your-key ubuntu@YOUR_IP
  Become root:    sudo su -
  Run as root:    sudo your-command

MONITORING:
  Check attacks:  sudo grep "Failed" /var/log/auth.log | tail -20
  Banned IPs:     sudo fail2ban-client status sshd
  Firewall:       sudo ufw status
  Updates:        sudo apt update && sudo apt list --upgradable

If you get locked out:
  • Use your cloud provider's console/VNC access
  • Restore SSH config: sudo cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
  • Restart SSH: sudo systemctl restart ssh

Next steps (optional):
  • Install Tailscale for secure VPN: curl -fsSL https://tailscale.com/install.sh | sh
  • Setup automatic security updates
  • Configure monitoring/alerting

Stay secure! 🔒
EOF