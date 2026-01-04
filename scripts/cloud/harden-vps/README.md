# VPS Security Hardening

Automated security hardening for cloud servers. Hardens SSH, configures firewall, sets up fail2ban, and optionally installs Tailscale VPN.

>[!WARNING]
> **This tool represents an opinionated approach to VPS security hardening based on my specific needs and use cases.** 
>
> **Before using this tool:**
> - Review the security settings and understand what they do
> - Consider your specific threat model and compliance requirements
> - Consult your organization's security policies if applicable
> - This is a starting point, not a complete security solution
> - Adapt the configurations to match your own needs and use cases
>
> **What this tool does:**
> - Provides a baseline security configuration that works for my use cases
> - Makes reasonable security improvements for general VPS deployments
> - Offers a quick way to harden a new or existing server
> - Reflects my preferences and requirements (which may differ from yours)
>
> **What this tool doesn't do:**
> - Replace a comprehensive security audit
> - Guarantee compliance with specific standards (PCI-DSS, HIPAA, etc.)
> - Account for all possible threat vectors
> - Replace ongoing security monitoring and maintenance
> - Absolutely not "one true way" to secure a server
>
> Use at your own discretion and adapt as needed for your environment and requirements.

---

## What is this?

When you create a new server in the cloud (like DigitalOcean, Oracle Cloud, or Racknerd), it often comes with default settings that aren't secure. This tool automatically hardens your server to prevent unauthorized access using an opinionated set of security configurations.

---

## Why use this?

**Default server configurations are often insecure:**
- Password authentication allows brute-force attacks
- Root login is enabled by default
- Firewall may be inactive or misconfigured
- No protection against repeated login attempts

**This tool addresses these issues:**
- Disables password authentication (SSH keys only) - Prevents brute-force attacks since keys can't be guessed
- Disables root login - Reduces attack surface by removing the most privileged account from direct access
- Configures firewall (UFW) with secure defaults - Blocks unauthorized network access, only allows approved services
- Sets up fail2ban to block attackers after failed attempts - Automatically bans IPs that show malicious behavior
- Enables automatic security updates - Keeps system patched against known vulnerabilities without manual intervention

---

## Usage

### Method 1: Run the Script (For Existing Servers)

**Use this if:** You already have a server running and want to secure it now.

```bash
# 1. Download the script
wget https://your-repo.com/harden-vps.sh

# 2. Make it runnable
chmod +x harden-vps.sh

# 3. Run it (it will ask you questions)
sudo ./harden-vps.sh
```

The script will:
1. Audit current security configuration
2. Prompt for optional features (automatic updates, Tailscale)
3. Apply security hardening
4. Display connection information

Preview changes without applying them:
```bash
sudo ./harden-vps.sh --dry-run --verbose
```

---

### Method 2: Cloud-Init (For New Servers)

**Use this if:** You're creating a brand new server and want it secure from the start.

**Steps:**

1. **Get your SSH key**
   ```bash
   # On your computer, run:
   cat ~/.ssh/id_ed25519.pub
   
   # If that doesn't work:
   cat ~/.ssh/id_rsa.pub
   
   # No file found? Create a key:
   ssh-keygen -t ed25519
   ```
   
   Copy the entire output (starts with `ssh-ed25519` or `ssh-rsa`)

2. **Edit the cloud-init file**
   - Open `cloud-init.yaml`
   - Find this line: `- YOUR_SSH_PUBLIC_KEY_HERE`
   - Replace it with your actual SSH key
   - Save the file

3. **Use it when creating your server**
   - In DigitalOcean: Paste into "User Data" box
   - In Oracle Cloud: Paste into "Cloud-Init Script" box
   - In Vultr: Paste into "Startup Script" box

4. **Wait 3-5 minutes** after server starts for setup to complete

5. **Log in!**
   ```bash
   ssh ubuntu@YOUR_SERVER_IP
   ```

---

## Key Concepts

### What is SSH?

SSH is how you control your server remotely. It's like remote desktop, but for command-line access to servers.

**Two authentication methods:**
1. **Password** - Vulnerable to brute-force attacks
2. **SSH Key** - Cryptographically secure, private key stays on your computer

This tool enforces SSH key authentication only.

### What is a Firewall?

A firewall controls which network connections are allowed and which are blocked.

This tool configures the firewall to:
- Block all incoming connections by default
- Allow only SSH (port 22) and Tailscale (if installed)

### What is Fail2ban?

Fail2ban monitors login attempts and automatically blocks IP addresses that show suspicious behavior.

**How it works:**
- Monitors failed login attempts
- After 5 failures within 10 minutes, bans the IP for 1 hour
- Ban time doubles for repeat offenders (up to 24 hours)

---

## What This Tool Does

When you run the script, it performs these steps:

1. **Security Audit** - Analyzes current configuration and displays findings
2. **System Updates** - Updates all packages and optionally enables automatic security updates
3. **Install Tools** - Installs ufw (firewall), fail2ban, and curl
4. **User Setup** - Ensures a non-root user exists with sudo access and SSH keys
5. **SSH Hardening** - Disables password and root login, enforces key-only authentication, limits login attempts
6. **Fail2ban Configuration** - Sets up automatic IP banning after failed login attempts
7. **Firewall Setup** - Configures UFW with deny-by-default, allows SSH only
8. **Tailscale (Optional)** - Installs and configures Tailscale VPN, optionally as exit node
9. **Apply Changes** - Reloads SSH service to apply new configuration
10. **Final Report** - Displays summary of changes and connection information

---

## Common Questions

### Q: Will I get locked out?

>[!TIP]
> **A:** No! The script is designed to prevent lockout:
> - It makes sure you have a working SSH key before changing anything
> - It creates a safe user account before disabling root
> - It validates all changes before applying them
> - It uses "reload" instead of "restart" for SSH (keeps you connected)
>
> **If something goes wrong**, you can still access your server through your cloud provider's web console.

### Q: What if I don't have an SSH key?

**A:** The script will help you:
1. It checks if you have SSH keys
2. If not, it asks you to create one
3. Or you can paste a key you made on your computer

**To create a key on your computer:**
```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

### Q: Can I run this multiple times?

**A:** Yes! The script is idempotent, which means:
- Running it multiple times won't break anything
- It checks what's already configured and skips those steps
- Safe to re-run after updates or changes

### Q: What's the difference between the script and cloud-init?

| Feature | Script | Cloud-Init |
|---------|--------|------------|
| When to use | Existing servers | New servers |
| Interactive | Yes (asks questions) | No (fully automatic) |
| Dry-run mode | Yes | No |
| Tailscale setup | Asks you | Must configure in file |

### Q: What is Tailscale and do I need it?

**Tailscale** is a private VPN that creates a secure network between your devices.

**Features:**
- Encrypted connections between devices
- Each device gets a permanent IP (100.x.x.x range)
- Exit node: Route all internet traffic through the VPS (useful for accessing region-locked content)

**Use cases:**
- Access servers securely from anywhere
- Connect multiple servers privately
- Route traffic through specific geographic locations

**Not required if:**
- You only need a basic secure server
- You access from a single location
- Regular SSH access is sufficient

The script prompts before installing Tailscale and separately asks about exit node configuration.

### Q: How do I know it worked?

**Quick audit script:**

Run the security audit script to verify your configuration. See [`sec-audit.sh`](../sec-audit.sh) for the script.

```bash
curl -fsSL https://raw.githubusercontent.com/jianjacob/dotfiles/main/scripts/cloud/sec-audit.sh | bash
```

This script checks:
- SSH password authentication status
- Root login configuration
- Public key authentication
- Fail2ban installation and status
- UFW firewall status
- Recent authentication attempts

**Manual verification:**

```bash
# 1. Check SSH security
sudo sshd -T | grep -E "passwordauth|rootlogin"
# Should show:
# passwordauthentication no
# permitrootlogin no

# 2. Check firewall
sudo ufw status
# Should show: Status: active

# 3. Check fail2ban
sudo fail2ban-client status sshd
# Should show the jail is active

# 4. Check Tailscale (if installed)
sudo tailscale status
# Should show your device with an IP like 100.x.x.x

# 5. Check for attacks
sudo grep "Failed password" /var/log/auth.log | wc -l
# Shows how many attacks were blocked
```

### Q: What if something breaks?

>[!TIP]
> **The script makes backups!**
>
> ```bash
> # SSH config backup
> ls /etc/ssh/sshd_config.backup.*
>
> # To restore:
> sudo cp /etc/ssh/sshd_config.backup.YYYYMMDD-HHMMSS /etc/ssh/sshd_config
> sudo systemctl restart ssh
> ```
>
> **Use your cloud provider's console:**
> - Oracle Cloud: Instance → Console Connection
> - DigitalOcean: Droplet → Access → Recovery Console
> - Vultr: Instance → View Console

---

## Useful Commands

### Check Your Security Status

```bash
# Full security audit
sudo ./harden-vps.sh --dry-run --verbose

# SSH settings
sudo sshd -T | grep -E "passwordauth|rootlogin|pubkeyauth"

# Firewall status
sudo ufw status verbose

# Fail2ban status
sudo fail2ban-client status sshd

# See banned IPs
sudo fail2ban-client status sshd | grep "Banned IP"

# See attack attempts
sudo grep "Failed password" /var/log/auth.log | tail -20
```

### Connect to Your Server

```bash
# Normal SSH
ssh ubuntu@YOUR_SERVER_IP

# With specific key
ssh -i ~/.ssh/your-key ubuntu@YOUR_SERVER_IP

# Become root (if needed)
sudo su -
```

### Manage Services

```bash
# Restart SSH
sudo systemctl restart ssh

# Restart fail2ban
sudo systemctl restart fail2ban

# Restart firewall
sudo ufw disable
sudo ufw enable

# Check service status
sudo systemctl status ssh
sudo systemctl status fail2ban
sudo systemctl status ufw
```

---

## Quick Start

### For Existing Server:
```bash
wget https://your-repo.com/harden-vps.sh
chmod +x harden-vps.sh
sudo ./harden-vps.sh
```

### For New Server:
1. Get SSH key: usually `cat ~/.ssh/id_ed25519.pub`
2. Edit `cloud-init.yaml`
3. Paste key where it says `YOUR_SSH_PUBLIC_KEY_HERE`
4. **Optional:** Configure Tailscale:
   - Set `INSTALL_TAILSCALE=true` (in bootcmd section)
   - Set `SETUP_EXIT_NODE=true` (for VPN exit node functionality)
   - Add your auth key: `TAILSCALE_AUTH_KEY=tskey-auth-xxxxx`
5. Use file in cloud provider's "User Data" field
6. Wait 5 minutes
7. SSH in: `ssh ubuntu@YOUR_IP`

---

## Troubleshooting

**Something not working?**

1. Check the logs:
   ```bash
   # Script log
   cat /var/log/vps-hardening.log
   
   # Tailscale log (if installed)
   cat /var/log/tailscale-setup.log
   
   # Cloud-init log
   cat /var/log/cloud-init-output.log
   ```

2. Test your SSH config:
   ```bash
   sudo sshd -t
   ```

3. Verify you can become root:
   ```bash
   sudo whoami
   # Should output: root
   ```

**Still stuck?**
- Check the PRD document for technical details
- Review the script source code
- Access server through cloud provider's console

---

>[!WARNING]
> **Important Warnings:**
>
> 1. **ALWAYS test SSH access** before closing your current session
> 2. **Save your SSH private key** in a secure location
> 3. **Don't delete your SSH key** - you'll be locked out!
> 4. **Use cloud provider console** as backup access method
> 5. **The script blocks root login** - use your regular user + sudo

---

## Verification

Your server is properly hardened if you can:
- SSH into your server as a non-root user
- Run `sudo whoami` and see `root`
- See `sudo ufw status` showing active
- See `sudo fail2ban-client status sshd` working
- (optional) [SSH via Tailscale](https://tailscale.com/kb/1193/tailscale-ssh) into your device

---

## Project Files

- `harden-vps.sh` - The main script (for existing servers)
- `cloud-init.yaml` - Cloud-init config (for new servers)
- `user-guide.md` - Configuration examples and scenarios
- `PRD.md` - Technical documentation (for developers)

---

>[!TIP]
> **Remember:** Security is not a one-time thing. Keep your server updated, monitor logs regularly, and review your SSH keys periodically!

>[!NOTE]
> This tool provides an opinionated security configuration based on my specific needs and use cases. Always review and adapt security settings based on your own requirements, threat model, and any applicable compliance needs.
