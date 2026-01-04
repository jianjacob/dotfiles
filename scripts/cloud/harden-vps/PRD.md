# **Product Requirement Document (PRD)**

## **Title:** VPS Security Hardening Script

**Target Users:** System administrators, DevOps engineers, VPS owners (Ubuntu 20.04 / 22.04 / 24.04)

**Purpose:** Improve baseline security for newly provisioned or existing VPS instances using Ubuntu.

---

## **1. Background / Problem Statement**

New VPS instances are often deployed with default settings that are **vulnerable to common attacks**:

* Root login enabled via SSH, which increases risk if passwords or keys are compromised.
* Password authentication enabled, allowing brute-force attacks.
* Firewall (`ufw`) may be inactive or misconfigured.
* Fail2ban may not be installed, leaving SSH exposed to repeated login attempts.
* Security updates may not be automatically applied.
* Optional VPN solutions like Tailscale may not be installed, limiting secure remote access options.

These issues expose VPS hosts to unauthorized access, ransomware, and other attacks.

**Goal:** Automate a **baseline security hardening process** so that VPS instances are safe to operate immediately, without manual configuration of each security component.

---

## **2. Scope**

**In Scope:**

1. **System updates** and optional unattended security upgrades.
2. Installation and configuration of **essential security packages**:

   * `ufw` (firewall)
   * `fail2ban` (SSH brute-force prevention)
   * `curl` (utility used for Tailscale installation and general scripts)
3. **SSH security hardening**:

   * Disable root login via SSH
   * Disable password-based authentication
   * Enable key-based authentication
   * Limit authentication attempts (`MaxAuthTries`)
4. **User management**:

   * Ensure at least one “safe user” exists with SSH key access
   * Create new user if none exists or “upgrade” existing user to passwordless sudo
5. **Optional Tailscale VPN installation** for secure remote access.
6. **Interactive verification** to prevent accidental lockout.
7. **Dry-run mode** to preview changes without applying them.
8. **Verbose mode** for detailed system audit before and after hardening.

**Out of Scope:**

* Configuring other network services (databases, web servers).
* Full Linux system compliance audits (CIS benchmarks, app-level hardening).
* Automating recovery from misconfigured firewall or SSH errors.

---

## **3. User Stories**

1. **As a VPS owner**, I want to automatically configure SSH, firewall, and security packages, so I don’t have to manually harden each server.
2. **As a DevOps engineer**, I want to ensure existing users are preserved and upgraded safely, so automation doesn’t lock out anyone.
3. **As a security-conscious admin**, I want dry-run and verbose modes, so I can validate changes before applying them.
4. **As a developer**, I want optional VPN setup with Tailscale, so I can securely connect to the VPS without exposing SSH to the internet.

---

## **4. Functional Requirements**

| Step | Function            | Description                                                              | Safety/Idempotency Features                                  |
| ---- | ------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------ |
| 1    | Security Audit      | Check current system, SSH config, firewall, fail2ban, installed packages | Verbose only; no changes made                                |
| 2    | System Update       | Upgrade all packages                                                     | Dry-run mode supported                                       |
| 2b   | Unattended Upgrades | Enable automatic security updates                                        | Optional, interactive                                        |
| 3    | Security Packages   | Install `ufw`, `fail2ban`, `curl`                                        | Checks if already installed; skips if present                |
| 4    | SSH User Handling   | Ensure at least one non-root user exists                                 | Preserves existing users; upgrades with sudo & key setup     |
| 5    | SSH Hardening       | Apply secure SSH config                                                  | Creates backup; validates config before restart              |
| 6    | Fail2ban            | Configure SSH jail                                                       | Idempotent (doesn’t overwrite existing config unnecessarily) |
| 7    | UFW                 | Configure firewall rules, allow SSH, enable service                      | Ensures firewall is running; idempotent reset                |
| 8    | Tailscale           | Optional VPN setup                                                       | Checks if Tailscale is already installed to skip re-install  |
| 9    | Apply Changes       | Restart SSH if verified by user                                          | Prevents accidental lockout                                  |
| 10   | Final Audit         | Report final configuration                                               | Verbose only; non-destructive                                |

---

## **5. Non-Functional Requirements**

* **Idempotency:** Can be run multiple times without breaking system state.
* **Safety:** Requires user confirmation before risky actions like restarting SSH.
* **Portability:** Works on Ubuntu 20.04, 22.04, 24.04 (VPS providers like DigitalOcean, Racknerd).
* **Automation Friendly:** Supports dry-run mode for automated testing.
* **User-Friendly:** Interactive prompts and informative messages prevent misconfiguration.

---

## **6. Assumptions**

* VPS uses Ubuntu with systemd.
* SSH key-based login is available (at least one user with authorized keys).
* User running the script has root privileges or can sudo without password prompts.

---

## **7. Risks & Mitigations**

| Risk                       | Mitigation                                                               |
| -------------------------- | ------------------------------------------------------------------------ |
| Locking out SSH access     | Interactive confirmation required before restarting SSH; backups created |
| Misconfigured firewall     | UFW reset performed; rules validated; service enabled and started        |
| Existing users overwritten | Script detects existing users and upgrades them safely                   |
| Package conflicts          | Checks if package already installed before installing                    |

---

## **8. Success Metrics**

* VPS is updated and all security packages installed.
* Root login via SSH is disabled.
* Password authentication is disabled; only key-based login works.
* At least one “safe user” exists with passwordless sudo.
* Fail2ban monitors SSH and firewall is active.
* Tailscale is installed optionally without breaking existing installation.
* Script can be rerun without failures or overwriting critical user data.

---

## **9. Notes**

* This script is intended for **initial hardening** and **quick setup**, not comprehensive compliance auditing.
* Intended to be **safe for multiple VPS providers**, not tied to DigitalOcean only.
* Interactive prompts prevent accidental lockouts but may be disabled in automation by removing `read` calls.

