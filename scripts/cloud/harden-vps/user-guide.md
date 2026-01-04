# Configuration Examples: Script vs Cloud-Init

Quick reference guide showing equivalent configurations between the interactive script and cloud-init YAML.

---

## Scenario 1: Basic Hardening (No Tailscale)

### Using Script (Interactive):
```bash
./harden-vps.sh

# When prompted:
Would you like to install Tailscale VPN? [y/N]: n
```

### Using Cloud-Init:
```yaml
bootcmd:
  - echo "INSTALL_TAILSCALE=false" >> /etc/environment
```

**Result:** Secure VPS without VPN functionality

---

## Scenario 2: Hardening + Tailscale (No Exit Node)

### Using Script (Interactive):
```bash
./harden-vps.sh

# When prompted:
Would you like to install Tailscale VPN? [y/N]: y
Configure this server as a Tailscale exit node? [Y/n]: n
Enter Tailscale auth key: tskey-auth-xxxxx
```

### Using Cloud-Init:
```yaml
bootcmd:
  - echo "INSTALL_TAILSCALE=true" >> /etc/environment
  - echo "SETUP_EXIT_NODE=false" >> /etc/environment
  - echo "TAILSCALE_AUTH_KEY=tskey-auth-xxxxx" >> /etc/environment
  - echo "TAILSCALE_HOSTNAME=my-vps" >> /etc/environment
```

**Result:** Secure VPS + Tailscale private network (no exit node)

---

## Scenario 3: Hardening + Tailscale Exit Node (Indian VPS)

### Using Script (Interactive):
```bash
./harden-vps.sh

# When prompted:
Would you like to install Tailscale VPN? [y/N]: y
Configure this server as a Tailscale exit node? [Y/n]: y
Enter Tailscale auth key: tskey-auth-k9xK123...
```

**Script automatically:**
- Enables IP forwarding
- Adds `--advertise-exit-node` flag
- Configures firewall for Tailscale

### Using Cloud-Init:
```yaml
hostname: india-exit
timezone: Asia/Kolkata

bootcmd:
  - echo "INSTALL_TAILSCALE=true" >> /etc/environment
  - echo "SETUP_EXIT_NODE=true" >> /etc/environment
  - echo "TAILSCALE_AUTH_KEY=tskey-auth-k9xK123..." >> /etc/environment
  - echo "TAILSCALE_HOSTNAME=india-exit" >> /etc/environment

users:
  - name: ubuntu
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3... your-key
```

**Result:** VPN exit node for accessing Indian websites from abroad

**After setup:**
1. Go to https://login.tailscale.com/admin/machines
2. Find "india-exit" node
3. Enable "Use as exit node"
4. On your laptop: Connect to exit node
5. Browse with Indian IP!

---

## Scenario 4: US Exit Node (For Accessing US Content)

### Using Script:
```bash
./harden-vps.sh

# Same as above, just running on US-based VPS
```

### Using Cloud-Init:
```yaml
hostname: us-exit
timezone: America/New_York

bootcmd:
  - echo "INSTALL_TAILSCALE=true" >> /etc/environment
  - echo "SETUP_EXIT_NODE=true" >> /etc/environment
  - echo "TAILSCALE_AUTH_KEY=tskey-auth-p7yH456..." >> /etc/environment
  - echo "TAILSCALE_HOSTNAME=us-exit" >> /etc/environment

users:
  - name: ubuntu
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3... your-key
```

**Result:** VPN exit node for accessing US content from abroad

---

## Scenario 5: Dry-Run Preview (Script Only)

```bash
# See what would happen without making changes
./harden-vps.sh --dry-run --verbose

# Output shows:
[DRY-RUN] Would execute: apt-get update -qq
[DRY-RUN] Would create /etc/ssh/sshd_config.d/99-security-hardening.conf
[DRY-RUN] Would enable IP forwarding
...
```

**Great for:** Testing before applying to production servers

---

## Scenario 6: Automated Deployment (CI/CD)

### Script with Auto Mode:
```bash
# Non-interactive, uses safe defaults
./harden-vps.sh --auto

# Skips all prompts:
# - Enables automatic updates (default: yes)
# - Skips Tailscale (default: no)
# - Creates 'ubuntu' user if needed
```

### Cloud-Init (Always Automated):
```yaml
# Already fully automated
# Just paste into User Data field when creating VPS
# Note: Automatic security updates are always enabled in cloud-init
```

**Great for:** Infrastructure-as-Code, Terraform, Ansible

**Difference:** Cloud-init always enables automatic security updates, while the script prompts you (default: yes).

---

## Scenario 7: Multiple Exit Nodes in Different Regions

Create 3 VPS instances with these cloud-init configs:

### India (Oracle Cloud, Hyderabad):
```yaml
hostname: india-vpn
timezone: Asia/Kolkata
bootcmd:
  - echo "INSTALL_TAILSCALE=true" >> /etc/environment
  - echo "SETUP_EXIT_NODE=true" >> /etc/environment
  - echo "TAILSCALE_AUTH_KEY=tskey-auth-india123" >> /etc/environment
  - echo "TAILSCALE_HOSTNAME=india-vpn" >> /etc/environment
```

### US (RackNerd, Los Angeles):
```yaml
hostname: us-vpn
timezone: America/Los_Angeles
bootcmd:
  - echo "INSTALL_TAILSCALE=true" >> /etc/environment
  - echo "SETUP_EXIT_NODE=true" >> /etc/environment
  - echo "TAILSCALE_AUTH_KEY=tskey-auth-us456" >> /etc/environment
  - echo "TAILSCALE_HOSTNAME=us-vpn" >> /etc/environment
```

### Europe (DigitalOcean, Frankfurt):
```yaml
hostname: eu-vpn
timezone: Europe/Berlin
bootcmd:
  - echo "INSTALL_TAILSCALE=true" >> /etc/environment
  - echo "SETUP_EXIT_NODE=true" >> /etc/environment
  - echo "TAILSCALE_AUTH_KEY=tskey-auth-eu789" >> /etc/environment
  - echo "TAILSCALE_HOSTNAME=eu-vpn" >> /etc/environment
```

**Result:** 3 exit nodes you can switch between!

On your laptop:
```bash
# Use India
tailscale up --exit-node=india-vpn

# Switch to US
tailscale up --exit-node=us-vpn

# Switch to Europe
tailscale up --exit-node=eu-vpn

# Disable
tailscale up --exit-node=
```

---

## Quick Reference Table

| Feature | Script Command | Cloud-Init Setting |
|---------|---------------|-------------------|
| Tailscale Install | `y` at prompt | `INSTALL_TAILSCALE=true` |
| Exit Node | `y` at exit node prompt | `SETUP_EXIT_NODE=true` |
| Skip Tailscale | `n` at prompt | `INSTALL_TAILSCALE=false` |
| Auth Key | Enter when prompted | `TAILSCALE_AUTH_KEY=...` |
| Hostname | Auto-suggested | `TAILSCALE_HOSTNAME=...` |
| IP Forwarding | Automatic if exit node | Automatic if `SETUP_EXIT_NODE=true` |
| Auto Updates | Prompted (default: yes) | Always enabled |
| Dry-Run | `--dry-run` flag | N/A (cloud-init only) |
| Verbose Audit | `--verbose` flag | Check logs after |
| Auto Mode | `--auto` flag | Always automatic |

---

## Common Patterns

### Pattern 1: Test First, Then Apply
```bash
# 1. Preview on test server
./harden-vps.sh --dry-run --verbose

# 2. Apply to test server
./harden-vps.sh

# 3. If good, use cloud-init for production fleet
# (paste tested config into production instances)
```

### Pattern 2: Hybrid Approach
```bash
# 1. Use cloud-init for base hardening (fast)
# 2. SSH in and run script for Tailscale setup (flexible)

# On VPS after cloud-init completes:
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --advertise-exit-node --accept-routes --ssh
```

### Pattern 3: Git-Based Configuration Management
```
vps-configs/
├── base-hardening.yaml          # No Tailscale
├── india-exit-node.yaml         # India + Tailscale exit
├── us-exit-node.yaml            # US + Tailscale exit
├── dev-server.yaml              # No Tailscale, dev packages
└── prod-web-server.yaml         # No Tailscale, web stack
```

Version control your configs, deploy as needed!

---

## Verification Commands (After Setup)

### Check Security Status:
```bash
# SSH config
sudo sshd -T | grep -E "passwordauth|rootlogin"

# Firewall
sudo ufw status verbose

# Fail2ban
sudo fail2ban-client status sshd
```

### Check Tailscale Status:
```bash
# Connection status
sudo tailscale status

# Check if you have an IP (means connected)
sudo tailscale status --self
# Should show something like: 100.x.x.x hostname

# IP address
sudo tailscale ip -4

# Exit node status
sudo tailscale status --self | grep "exit node"

# Check if IP forwarding enabled
sysctl net.ipv4.ip_forward
# Should show: net.ipv4.ip_forward = 1 (if exit node)
```

### Check Logs:
```bash
# Script execution (if using cloud-init)
cat /var/log/vps-hardening.log

# Tailscale setup
cat /var/log/tailscale-setup.log

# Cloud-init full output
cat /var/log/cloud-init-output.log
```

---

## Troubleshooting Decision Tree

```
Exit node not working?
│
├─ Check: Is Tailscale connected?
│  └─ sudo tailscale status
│     ├─ Not connected → Run: sudo tailscale up
│     └─ Connected → Continue
│
├─ Check: Is IP forwarding enabled?
│  └─ sysctl net.ipv4.ip_forward
│     ├─ Shows 0 → Enable: echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
│     └─ Shows 1 → Continue
│
├─ Check: Is exit node advertised?
│  └─ sudo tailscale status --self
│     ├─ Shows "offers exit node" → Continue
│     └─ Doesn't show → Run: sudo tailscale up --advertise-exit-node --accept-routes
│
└─ Check: Is exit node enabled in admin console?
   └─ Go to https://login.tailscale.com/admin/machines
      └─ Find your node → Edit route settings → Enable "Use as exit node"
```

---

## Next Steps

After successful hardening:

1. **Document your setup** - Save auth keys, hostnames, IPs
2. **Test from different locations** - Verify exit nodes work
3. **Set up monitoring** (optional) - Uptime checks, alerts
4. **Schedule updates** - Already configured with unattended-upgrades!
5. **Backup SSH keys** - Store securely offline

**You're now running secure, properly configured VPS instances!** 🎉