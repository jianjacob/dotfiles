#!/usr/bin/env bash
#
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        VPS Security Hardening Script                         ║
# ║                                                                              ║
# ║  Compatible: Ubuntu 20.04 / 22.04 / 24.04                                    ║
# ║  Providers:  Oracle OCI, DigitalOcean, Racknerd, Linode, Vultr, any VPS      ║
# ║                                                                              ║
# ║  Features:                                                                   ║
# ║    • System updates & optional unattended upgrades                           ║
# ║    • SSH hardening (disable root, disable password auth)                     ║
# ║    • UFW firewall configuration                                              ║
# ║    • Fail2ban brute-force protection                                         ║
# ║    • Optional Tailscale VPN installation                                     ║
# ║    • Dry-run mode for safe preview                                           ║
# ║    • Verbose mode for detailed auditing                                      ║
# ║                                                                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Usage:
#   ./harden-vps.sh [OPTIONS]
#
# Options:
#   --dry-run     Preview changes without applying them
#   --verbose     Show detailed audit information
#   --auto        Skip interactive prompts (use defaults)
#   --help        Show this help message
#
# Run as root or with sudo privileges.

set -euo pipefail
IFS=$'\n\t'

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION & CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════════

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SSH_HARDENING_FILE="/etc/ssh/sshd_config.d/99-security-hardening.conf"
readonly FAIL2BAN_JAIL_FILE="/etc/fail2ban/jail.d/sshd-custom.conf"
readonly AUTO_UPGRADES_FILE="/etc/apt/apt.conf.d/20auto-upgrades"

# Command-line flags (defaults)
DRY_RUN=0
VERBOSE=0
AUTO_MODE=0

# Track if SSH config was modified (for safe reload)
SSH_CONFIG_CHANGED=0

# ═══════════════════════════════════════════════════════════════════════════════
# COLOR DEFINITIONS & OUTPUT FORMATTING
# ═══════════════════════════════════════════════════════════════════════════════

# Check if terminal supports colors
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null) -ge 8 ]]; then
    readonly C_RESET='\033[0m'
    readonly C_BOLD='\033[1m'
    readonly C_DIM='\033[2m'
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[1;33m'
    readonly C_BLUE='\033[0;34m'
    readonly C_MAGENTA='\033[0;35m'
    readonly C_CYAN='\033[0;36m'
    readonly C_WHITE='\033[1;37m'
    readonly C_BG_GREEN='\033[42m'
    readonly C_BG_RED='\033[41m'
    readonly C_BG_BLUE='\033[44m'
else
    readonly C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW=''
    readonly C_BLUE='' C_MAGENTA='' C_CYAN='' C_WHITE=''
    readonly C_BG_GREEN='' C_BG_RED='' C_BG_BLUE=''
fi

# Icons
readonly ICON_SUCCESS="✓"
readonly ICON_ERROR="✗"
readonly ICON_WARNING="⚠"
readonly ICON_INFO="ℹ"
readonly ICON_ARROW="→"
readonly ICON_BULLET="•"
readonly ICON_LOCK="🔒"
readonly ICON_SHIELD="🛡"

# Output functions
print_success() { echo -e "${C_GREEN}${ICON_SUCCESS}${C_RESET} $1"; }
print_error()   { echo -e "${C_RED}${ICON_ERROR}${C_RESET} $1" >&2; }
print_warning() { echo -e "${C_YELLOW}${ICON_WARNING}${C_RESET} $1"; }
print_info()    { echo -e "${C_BLUE}${ICON_INFO}${C_RESET} $1"; }
print_dry()     { [[ $DRY_RUN -eq 1 ]] && echo -e "${C_MAGENTA}[DRY-RUN]${C_RESET} $1" || true; }
print_verbose() { [[ $VERBOSE -eq 1 ]] && echo -e "${C_DIM}  $1${C_RESET}" || true; }

print_step() {
    local step_num="$1"
    local step_title="$2"
    echo ""
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_BOLD}${C_WHITE}  Step ${step_num}: ${step_title}${C_RESET}"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
}

print_banner() {
    echo ""
    echo -e "${C_BOLD}${C_CYAN}"
    cat << 'BANNER'
  ╦  ╦╔═╗╔═╗  ╦ ╦╔═╗╦═╗╔╦╗╔═╗╔╗╔╦╔╗╔╔═╗
  ╚╗╔╝╠═╝╚═╗  ╠═╣╠═╣╠╦╝ ║║║╣ ║║║║║║║║ ╦
   ╚╝ ╩  ╚═╝  ╩ ╩╩ ╩╩╚══╩╝╚═╝╝╚╝╩╝╚╝╚═╝
BANNER
    echo -e "${C_RESET}"
    echo -e "  ${C_DIM}Version ${SCRIPT_VERSION} ${ICON_BULLET} Author: jianjacob + 🤖 ${ICON_BULLET} MIT License${C_RESET}"
    echo -e "  ${C_DIM}Ubuntu 20.04/22.04/24.04 ${ICON_BULLET} Provider Agnostic${C_RESET}"
    echo ""
    
    # Display mode indicators
    local modes=""
    [[ $DRY_RUN -eq 1 ]] && modes+="${C_MAGENTA}[DRY-RUN]${C_RESET} " || true
    [[ $VERBOSE -eq 1 ]] && modes+="${C_BLUE}[VERBOSE]${C_RESET} " || true
    [[ $AUTO_MODE -eq 1 ]] && modes+="${C_YELLOW}[AUTO]${C_RESET} " || true
    [[ -n "$modes" ]] && echo -e "  Modes: $modes" && echo "" || true
}

print_summary() {
    echo ""
    echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}  ${ICON_SHIELD} Security Hardening Complete ${ICON_LOCK}${C_RESET}"
    echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

show_help() {
    echo ""
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_BOLD}${C_WHITE}  ${ICON_SHIELD} VPS Security Hardening Script ${ICON_LOCK}${C_RESET}"
    echo -e "${C_DIM}  Version ${SCRIPT_VERSION} • Author: jianjacob + 🤖 • MIT License${C_RESET}"
    echo -e "${C_DIM}  Ubuntu 20.04/22.04/24.04 • Provider Agnostic${C_RESET}"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo ""
    echo -e "${C_BOLD}${C_YELLOW}USAGE${C_RESET}"
    echo -e "  ${C_GREEN}${SCRIPT_NAME}${C_RESET} [OPTIONS]"
    echo ""
    echo -e "${C_BOLD}${C_YELLOW}OPTIONS${C_RESET}"
    echo -e "  ${C_CYAN}--dry-run${C_RESET}     Preview changes without applying them"
    echo -e "  ${C_CYAN}--verbose${C_RESET}     Show detailed audit information before and after"
    echo -e "  ${C_CYAN}--auto${C_RESET}        Skip interactive prompts (use safe defaults)"
    echo -e "  ${C_CYAN}--help${C_RESET}        Show this help message"
    echo ""
    echo -e "${C_BOLD}${C_YELLOW}EXAMPLES${C_RESET}"
    echo -e "  ${C_DIM}# Interactive mode (recommended for first run)${C_RESET}"
    echo -e "  ${C_GREEN}${SCRIPT_NAME}${C_RESET}"
    echo ""
    echo -e "  ${C_DIM}# Preview all changes without applying${C_RESET}"
    echo -e "  ${C_GREEN}${SCRIPT_NAME}${C_RESET} ${C_CYAN}--dry-run --verbose${C_RESET}"
    echo ""
    echo -e "  ${C_DIM}# Automated hardening (for scripts/CI)${C_RESET}"
    echo -e "  ${C_GREEN}${SCRIPT_NAME}${C_RESET} ${C_CYAN}--auto${C_RESET}"
    echo ""
    echo -e "${C_BOLD}${C_YELLOW}WHAT THIS SCRIPT DOES${C_RESET}"
    echo -e "  ${C_GREEN}1.${C_RESET} Audits current security configuration"
    echo -e "  ${C_GREEN}2.${C_RESET} Updates system packages"
    echo -e "  ${C_GREEN}3.${C_RESET} Installs security tools (ufw, fail2ban, curl)"
    echo -e "  ${C_GREEN}4.${C_RESET} Ensures a safe SSH user exists with sudo"
    echo -e "  ${C_GREEN}5.${C_RESET} Hardens SSH (disables password auth & root login)"
    echo -e "  ${C_GREEN}6.${C_RESET} Configures fail2ban for brute-force protection"
    echo -e "  ${C_GREEN}7.${C_RESET} Sets up UFW firewall rules"
    echo -e "  ${C_GREEN}8.${C_RESET} Optional: Installs Tailscale VPN (with exit node support)"
    echo -e "  ${C_GREEN}9.${C_RESET} Reloads SSH to apply changes"
    echo ""
    echo -e "${C_BOLD}${C_YELLOW}TAILSCALE SETUP${C_RESET}"
    echo -e "  In interactive mode, the script will:"
    echo -e "  ${ICON_BULLET} Ask if you want to configure as an exit node"
    echo -e "  ${ICON_BULLET} Enable IP forwarding if needed"
    echo -e "  ${ICON_BULLET} Prompt for an auth key (get one from Tailscale admin)"
    echo -e "  ${ICON_BULLET} Auto-configure with: ${C_DIM}--advertise-exit-node --accept-routes --ssh${C_RESET}"
    echo ""
    echo -e "${C_BOLD}${C_YELLOW}REQUIREMENTS${C_RESET}"
    echo -e "  ${ICON_BULLET} Ubuntu 20.04, 22.04, or 24.04"
    echo -e "  ${ICON_BULLET} Root privileges or passwordless sudo"
    echo -e "  ${ICON_BULLET} SSH key already configured for at least one user"
    echo -e "  ${ICON_BULLET} ${C_DIM}(Optional) Tailscale auth key for automated setup${C_RESET}"
    echo ""
    exit 0
}

# Parse command-line arguments
parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run)  DRY_RUN=1 ;;
            --verbose)  VERBOSE=1 ;;
            --auto)     AUTO_MODE=1 ;;
            --help|-h)  show_help ;;
            *)
                print_error "Unknown argument: $arg"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
}

# Check if running in interactive mode
check_interactive() {
    # If auto mode is explicitly set, skip interactive check
    if [[ $AUTO_MODE -eq 1 ]]; then
        return 0
    fi
    
    # Check if stdin is connected to a terminal
    if [[ ! -t 0 ]]; then
        print_warning "Stdin is not connected to a terminal (non-interactive environment)"
        print_warning "Interactive prompts will not work. Automatically enabling --auto mode with safe defaults."
        print_info "To suppress this warning, use --auto flag explicitly when running the script"
        echo ""
        AUTO_MODE=1
        return 0
    fi
    
    # Interactive mode is available
    return 0
}

# Determine sudo prefix
setup_sudo() {
    if [[ "$EUID" -eq 0 ]]; then
        SUDO=""
    elif sudo -n true 2>/dev/null; then
        SUDO="sudo"
    else
        print_error "This script requires root privileges or passwordless sudo."
        print_info "Run as root or configure passwordless sudo for your user."
        exit 1
    fi
}

# Execute command or print in dry-run mode
run_cmd() {
    if [[ $DRY_RUN -eq 1 ]]; then
        # Join all arguments with spaces for readable output
        local cmd_str="${*}"
        print_dry "Would execute: ${cmd_str}"
        return 0
    else
        "$@"
    fi
}

# Prompt user for yes/no with default
prompt_yn() {
    local prompt="$1"
    local default="${2:-no}"
    
    if [[ $AUTO_MODE -eq 1 ]]; then
        [[ "$default" == "yes" ]] && return 0 || return 1
    fi
    
    local response
    if [[ "$default" == "yes" ]]; then
        read -r -p "$prompt [Y/n]: " response || response=""
        # Match empty, "y", "yes" (case insensitive)
        [[ -z "$response" || "$response" =~ ^[Yy]([Ee][Ss])?$ ]]
    else
        read -r -p "$prompt [y/N]: " response || response=""
        # Match "y" or "yes" (case insensitive)
        [[ "$response" =~ ^[Yy]([Ee][Ss])?$ ]]
    fi
}

# Prompt for text input with default
prompt_text() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    
    if [[ $AUTO_MODE -eq 1 ]]; then
        eval "$varname='$default'"
        return
    fi
    
    local response
    read -r -p "$prompt [$default]: " response || response=""
    eval "$varname='${response:-$default}'"
}

# Check Ubuntu version compatibility
check_ubuntu_version() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS. This script requires Ubuntu."
        exit 1
    fi
    
    source /etc/os-release
    
    if [[ "${ID:-}" != "ubuntu" ]]; then
        print_error "This script only supports Ubuntu. Detected: ${ID:-unknown}"
        exit 1
    fi
    
    local version="${VERSION_ID:-0}"
    case "$version" in
        20.04|22.04|24.04)
            print_verbose "Ubuntu $version detected - compatible"
            ;;
        *)
            print_warning "Ubuntu $version detected - may not be fully tested"
            if [[ $AUTO_MODE -eq 1 ]]; then
                print_warning "Auto mode: continuing with untested Ubuntu version"
            elif ! prompt_yn "Continue anyway?" "no"; then
                exit 1
            fi
            ;;
    esac
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    # Remove any temp files
    rm -f /tmp/ssh-hardening-*.tmp 2>/dev/null || true
    rm -f /tmp/fail2ban-*.tmp 2>/dev/null || true
    exit $exit_code
}
trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: SECURITY AUDIT
# ═══════════════════════════════════════════════════════════════════════════════

do_security_audit() {
    print_step "1" "Security Audit"
    
    # System info
    echo ""
    echo -e "  ${C_BOLD}System Information:${C_RESET}"
    echo -e "    ${ICON_BULLET} Hostname:    $(hostname)"
    echo -e "    ${ICON_BULLET} OS:          $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')"
    echo -e "    ${ICON_BULLET} Kernel:      $(uname -r)"
    echo -e "    ${ICON_BULLET} User:        $(whoami)"
    echo -e "    ${ICON_BULLET} Date:        $(date '+%Y-%m-%d %H:%M:%S %Z')"
    
    # SSH Configuration
    echo ""
    echo -e "  ${C_BOLD}SSH Configuration:${C_RESET}"
    
    local sshd_config
    sshd_config=$($SUDO sshd -T 2>/dev/null || echo "")
    
    if [[ -n "$sshd_config" ]]; then
        local pass_auth root_login pubkey_auth max_tries
        pass_auth=$(echo "$sshd_config" | grep "^passwordauthentication" | awk '{print $2}')
        root_login=$(echo "$sshd_config" | grep "^permitrootlogin" | awk '{print $2}')
        pubkey_auth=$(echo "$sshd_config" | grep "^pubkeyauthentication" | awk '{print $2}')
        max_tries=$(echo "$sshd_config" | grep "^maxauthtries" | awk '{print $2}')
        
        # Password Authentication
        if [[ "$pass_auth" == "no" ]]; then
            echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} Password auth:     disabled"
        else
            echo -e "    ${C_RED}${ICON_ERROR}${C_RESET} Password auth:     ${C_RED}enabled${C_RESET} (insecure)"
        fi
        
        # Root Login
        if [[ "$root_login" == "no" || "$root_login" == "prohibit-password" ]]; then
            echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} Root login:        disabled/restricted"
        else
            echo -e "    ${C_RED}${ICON_ERROR}${C_RESET} Root login:        ${C_RED}enabled${C_RESET} (insecure)"
        fi
        
        # Pubkey Authentication
        if [[ "$pubkey_auth" == "yes" ]]; then
            echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} Pubkey auth:       enabled"
        else
            echo -e "    ${C_RED}${ICON_ERROR}${C_RESET} Pubkey auth:       ${C_RED}disabled${C_RESET}"
        fi
        
        # Max Auth Tries
        if [[ -n "$max_tries" ]] && [[ "$max_tries" -le 4 ]]; then
            echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} Max auth tries:    $max_tries"
        else
            echo -e "    ${C_YELLOW}${ICON_WARNING}${C_RESET} Max auth tries:    ${max_tries:-6} (could be lower)"
        fi
    else
        echo -e "    ${C_YELLOW}${ICON_WARNING}${C_RESET} Unable to query SSH configuration"
    fi
    
    # Fail2ban Status
    echo ""
    echo -e "  ${C_BOLD}Fail2ban Status:${C_RESET}"
    if command -v fail2ban-client &>/dev/null; then
        if systemctl is-active --quiet fail2ban 2>/dev/null; then
            echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} Service:           running"
            local jail_status
            jail_status=$($SUDO fail2ban-client status sshd 2>/dev/null || echo "")
            if [[ -n "$jail_status" ]]; then
                local banned
                banned=$(echo "$jail_status" | grep "Currently banned" | awk -F: '{print $2}' | tr -d ' ')
                echo -e "    ${ICON_BULLET} SSH jail:          active (${banned:-0} banned IPs)"
            else
                echo -e "    ${C_YELLOW}${ICON_WARNING}${C_RESET} SSH jail:          not configured"
            fi
        else
            echo -e "    ${C_YELLOW}${ICON_WARNING}${C_RESET} Service:           installed but not running"
        fi
    else
        echo -e "    ${C_RED}${ICON_ERROR}${C_RESET} Status:            not installed"
    fi
    
    # UFW Firewall Status
    echo ""
    echo -e "  ${C_BOLD}UFW Firewall Status:${C_RESET}"
    if command -v ufw &>/dev/null; then
        local ufw_status
        ufw_status=$($SUDO ufw status 2>/dev/null | head -1)
        if echo "$ufw_status" | grep -q "active"; then
            echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} Status:            active"
            # Count rules
            local rule_count
            rule_count=$($SUDO ufw status | grep -c "ALLOW\|DENY" || echo "0")
            echo -e "    ${ICON_BULLET} Rules configured:  $rule_count"
        elif echo "$ufw_status" | grep -q "inactive"; then
            echo -e "    ${C_YELLOW}${ICON_WARNING}${C_RESET} Status:            inactive"
        else
            echo -e "    ${C_YELLOW}${ICON_WARNING}${C_RESET} Status:            unknown"
        fi
    else
        echo -e "    ${C_RED}${ICON_ERROR}${C_RESET} Status:            not installed"
    fi
    
    # Tailscale Status (if installed)
    if command -v tailscale &>/dev/null; then
        echo ""
        echo -e "  ${C_BOLD}Tailscale Status:${C_RESET}"
        local ts_status
        ts_status=$($SUDO tailscale status --self 2>/dev/null | head -1 || echo "")
        if [[ -n "$ts_status" ]]; then
            echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} Connected:         $ts_status"
        else
            echo -e "    ${C_YELLOW}${ICON_WARNING}${C_RESET} Installed but not connected"
        fi
    fi
    
    # SSH Users with keys
    echo ""
    echo -e "  ${C_BOLD}SSH-Ready Users:${C_RESET}"
    local found_users=0
    while IFS= read -r username; do
        if [[ -n "$username" ]]; then
            local auth_keys="/home/$username/.ssh/authorized_keys"
            if [[ -f "$auth_keys" ]] && [[ -s "$auth_keys" ]]; then
                # Count keys - handle keys with options prefix (e.g., "no-port-forwarding,... ssh-rsa")
                # Match lines containing ssh-rsa, ssh-ed25519, ecdsa-sha2, etc.
                local key_count
                key_count=$(grep -cE "(^|[[:space:]])(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2)" "$auth_keys" 2>/dev/null) || key_count=0
                
                # Check if any keys are usable (not blocked by command="")
                local usable_keys=0
                while IFS= read -r line; do
                    # Skip keys that have a forced command blocking login
                    if [[ -n "$line" ]] && ! echo "$line" | grep -qE 'command="[^"]*exit'; then
                        ((usable_keys++)) || true
                    fi
                done < <(grep -E "(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2)" "$auth_keys" 2>/dev/null)
                
                local has_sudo=""
                if groups "$username" 2>/dev/null | grep -qw "sudo"; then
                    has_sudo=" ${C_GREEN}[sudo]${C_RESET}"
                fi
                
                if [[ $usable_keys -gt 0 ]]; then
                    echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} $username: ${usable_keys} usable key(s)$has_sudo"
                    ((found_users++)) || true
                else
                    echo -e "    ${C_YELLOW}${ICON_WARNING}${C_RESET} $username: ${key_count} key(s) but login may be blocked$has_sudo"
                fi
            fi
        fi
    done < <(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd 2>/dev/null)
    
    # Check root keys
    if [[ -f /root/.ssh/authorized_keys ]] && [[ -s /root/.ssh/authorized_keys ]]; then
        local root_keys
        root_keys=$(grep -cE "(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2)" /root/.ssh/authorized_keys 2>/dev/null) || root_keys=0
        if [[ $root_keys -gt 0 ]]; then
            echo -e "    ${C_YELLOW}${ICON_WARNING}${C_RESET} root: ${root_keys} key(s) (will be copied to new user)"
        fi
    fi
    
    if [[ $found_users -eq 0 ]]; then
        echo -e "    ${C_YELLOW}${ICON_WARNING}${C_RESET} No non-root users with SSH keys found"
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: SYSTEM UPDATE
# ═══════════════════════════════════════════════════════════════════════════════

do_system_update() {
    print_step "2" "System Update"
    
    print_info "Updating package lists..."
    run_cmd $SUDO apt-get update -qq
    
    print_info "Upgrading installed packages..."
    if [[ $DRY_RUN -eq 1 ]]; then
        print_dry "Would run: apt-get upgrade -y"
        # Show what would be upgraded
        $SUDO apt-get upgrade --dry-run 2>/dev/null | grep "^Inst" | head -10 || true
    else
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get upgrade -y -qq || {
            print_warning "Some packages may have failed to upgrade"
        }
    fi
    
    print_success "System packages updated"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2b: UNATTENDED UPGRADES (Optional)
# ═══════════════════════════════════════════════════════════════════════════════

do_unattended_upgrades() {
    print_step "2b" "Automatic Security Updates (Optional)"
    
    # Check current state
    local already_configured=0
    if [[ -f "$AUTO_UPGRADES_FILE" ]]; then
        if $SUDO grep -qE 'Unattended-Upgrade\s+"1"' "$AUTO_UPGRADES_FILE" 2>/dev/null; then
            already_configured=1
            print_success "Unattended upgrades already configured"
            return 0
        fi
    fi
    
    if prompt_yn "Enable automatic security updates?" "yes"; then
        # Install package if needed
        if ! dpkg -s unattended-upgrades &>/dev/null; then
            print_info "Installing unattended-upgrades package..."
            run_cmd $SUDO apt-get install -y -qq unattended-upgrades
        else
            print_verbose "Package unattended-upgrades already installed"
        fi
        
        # Configure
        if [[ $DRY_RUN -eq 1 ]]; then
            print_dry "Would create $AUTO_UPGRADES_FILE with auto-upgrade settings"
        else
            $SUDO tee "$AUTO_UPGRADES_FILE" > /dev/null << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
            print_success "Automatic security updates enabled"
        fi
    else
        print_info "Skipping automatic updates configuration"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: INSTALL SECURITY PACKAGES
# ═══════════════════════════════════════════════════════════════════════════════

do_install_packages() {
    print_step "3" "Security Packages Installation"
    
    local packages=("ufw" "fail2ban" "curl")
    local to_install=()
    
    for pkg in "${packages[@]}"; do
        if dpkg -s "$pkg" &>/dev/null; then
            print_verbose "$pkg is already installed"
        else
            to_install+=("$pkg")
        fi
    done
    
    if [[ ${#to_install[@]} -eq 0 ]]; then
        print_success "All required packages already installed"
    else
        print_info "Installing: ${to_install[*]}"
        run_cmd $SUDO apt-get install -y -qq "${to_install[@]}"
        print_success "Security packages installed"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: SSH USER HANDLING
# ═══════════════════════════════════════════════════════════════════════════════

do_user_handling() {
    print_step "4" "SSH User Verification"
    
    # Find existing users with usable SSH keys (not blocked by forced command)
    local safe_users=()
    while IFS= read -r username; do
        if [[ -n "$username" ]]; then
            local auth_keys="/home/$username/.ssh/authorized_keys"
            if [[ -f "$auth_keys" ]] && [[ -s "$auth_keys" ]]; then
                # Check if user has at least one usable key (not blocked by exit command)
                local has_usable_key=0
                while IFS= read -r line; do
                    if [[ -n "$line" ]] && ! echo "$line" | grep -qE 'command="[^"]*exit'; then
                        has_usable_key=1
                        break
                    fi
                done < <(grep -E "(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2)" "$auth_keys" 2>/dev/null)
                
                if [[ $has_usable_key -eq 1 ]]; then
                    safe_users+=("$username")
                fi
            fi
        fi
    done < <(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd 2>/dev/null)
    
    if [[ ${#safe_users[@]} -gt 0 ]]; then
        local user_list
        user_list=$(IFS=', '; echo "${safe_users[*]}")
        print_success "Found ${#safe_users[@]} user(s) with SSH keys: ${user_list}"
        
        # Ensure they have sudo access
        for user in "${safe_users[@]}"; do
            if ! groups "$user" 2>/dev/null | grep -qw "sudo"; then
                print_info "Adding $user to sudo group..."
                run_cmd $SUDO usermod -aG sudo "$user"
                
                # Setup passwordless sudo
                local sudoers_file="/etc/sudoers.d/$user"
                if [[ ! -f "$sudoers_file" ]]; then
                    if [[ $DRY_RUN -eq 1 ]]; then
                        print_dry "Would create $sudoers_file for passwordless sudo"
                    else
                        echo "$user ALL=(ALL) NOPASSWD:ALL" | $SUDO tee "$sudoers_file" > /dev/null
                        $SUDO chmod 440 "$sudoers_file"
                    fi
                fi
                print_success "$user now has passwordless sudo"
            else
                print_verbose "$user already has sudo privileges"
            fi
        done
        return 0
    fi
    
    # No safe users found - need to create one
    print_warning "No non-root user with SSH keys found!"
    print_warning "You MUST have at least one safe user to avoid being locked out."
    echo ""
    
    local new_user
    prompt_text "Enter username to create" "ubuntu" new_user
    
    # Validate username
    if [[ ! "$new_user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        print_error "Invalid username format. Use lowercase letters, numbers, underscore, hyphen."
        exit 1
    fi
    
    if id "$new_user" &>/dev/null; then
        print_info "User $new_user already exists. Setting up SSH access..."
    else
        print_info "Creating user $new_user..."
        run_cmd $SUDO adduser --disabled-password --gecos "VPS Admin User" "$new_user"
    fi
    
    # Add to sudo group
    run_cmd $SUDO usermod -aG sudo "$new_user"
    
    # Setup passwordless sudo
    if [[ $DRY_RUN -eq 1 ]]; then
        print_dry "Would configure passwordless sudo for $new_user"
    else
        echo "$new_user ALL=(ALL) NOPASSWD:ALL" | $SUDO tee "/etc/sudoers.d/$new_user" > /dev/null
        $SUDO chmod 440 "/etc/sudoers.d/$new_user"
    fi
    
    # Setup SSH directory
    local ssh_dir="/home/$new_user/.ssh"
    local auth_file="$ssh_dir/authorized_keys"
    
    run_cmd $SUDO mkdir -p "$ssh_dir"
    run_cmd $SUDO chmod 700 "$ssh_dir"
    
    # Try to copy keys from root
    if [[ -f /root/.ssh/authorized_keys ]] && [[ -s /root/.ssh/authorized_keys ]]; then
        print_info "Copying SSH keys from root..."
        run_cmd $SUDO cp /root/.ssh/authorized_keys "$auth_file"
        run_cmd $SUDO chmod 600 "$auth_file"
        run_cmd $SUDO chown -R "$new_user:$new_user" "$ssh_dir"
        print_success "SSH keys copied from root to $new_user"
    else
        # Need user to paste key
        if [[ $AUTO_MODE -eq 1 ]]; then
            print_error "No SSH keys found to copy in auto mode. Cannot continue."
            exit 1
        fi
        
        echo ""
        print_warning "No SSH keys found in /root/.ssh/authorized_keys"
        print_info "Please paste your SSH public key (starts with ssh-rsa or ssh-ed25519):"
        echo ""
        
        local ssh_key
        read -r ssh_key || ssh_key=""
        
        # Validate SSH key format
        if [[ -z "$ssh_key" ]]; then
            print_error "No SSH key provided. Cannot continue safely."
            exit 1
        fi
        
        # Validate SSH key format - allow keys with options prefix (e.g., "no-port-forwarding ssh-rsa...")
        # or just the key type and data
        if ! echo "$ssh_key" | grep -qE "(^|[[:space:]])(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp|ssh-dss)\s+[A-Za-z0-9+/=]+"; then
            print_error "Invalid SSH key format."
            print_info "Expected format: ssh-ed25519 AAAA... or ssh-rsa AAAA..."
            print_info "Keys with options are also supported (e.g., no-port-forwarding ssh-rsa...)"
            exit 1
        fi
        
        if [[ $DRY_RUN -eq 1 ]]; then
            print_dry "Would write SSH key to $auth_file"
        else
            echo "$ssh_key" | $SUDO tee "$auth_file" > /dev/null
            $SUDO chmod 600 "$auth_file"
            $SUDO chown -R "$new_user:$new_user" "$ssh_dir"
        fi
        print_success "SSH key installed for $new_user"
    fi
    
    echo ""
    print_success "User $new_user is ready for SSH access"
    echo -e "    ${ICON_ARROW} Login with: ${C_CYAN}ssh $new_user@$(hostname -I | awk '{print $1}')${C_RESET}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: SSH HARDENING
# ═══════════════════════════════════════════════════════════════════════════════

do_ssh_hardening() {
    print_step "5" "SSH Security Hardening"
    
    # Ensure config directory exists
    run_cmd $SUDO mkdir -p /etc/ssh/sshd_config.d
    
    # Define hardened configuration
    local hardened_config
    read -r -d '' hardened_config << 'EOF' || true
# Security hardening configuration
# Generated by harden-vps.sh
# Do not edit manually

# Disable password authentication - keys only
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no

# Disable root login
PermitRootLogin no

# Enable public key authentication
PubkeyAuthentication yes

# Limit authentication attempts
MaxAuthTries 3
MaxSessions 4

# Disable X11 forwarding (security risk if not needed)
X11Forwarding no

# Stricter settings
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    
    # Check if config already exists and matches
    if [[ -f "$SSH_HARDENING_FILE" ]]; then
        local current_config
        current_config=$($SUDO cat "$SSH_HARDENING_FILE" 2>/dev/null)
        
        # Compare key settings (ignoring comments/whitespace)
        local current_pass current_root
        current_pass=$(echo "$current_config" | grep "^PasswordAuthentication" | awk '{print $2}')
        current_root=$(echo "$current_config" | grep "^PermitRootLogin" | awk '{print $2}')
        
        if [[ "$current_pass" == "no" ]] && [[ "$current_root" == "no" ]]; then
            print_verbose "SSH hardening configuration already applied"
            print_success "SSH is already hardened"
            return 0
        fi
    fi
    
    # Backup current config
    local backup_file="/etc/ssh/sshd_config.backup.$(date +%Y%m%d-%H%M%S)"
    print_info "Backing up SSH config to $backup_file"
    run_cmd $SUDO cp /etc/ssh/sshd_config "$backup_file"
    
    # Write new hardening config
    if [[ $DRY_RUN -eq 1 ]]; then
        print_dry "Would write hardening config to $SSH_HARDENING_FILE"
        echo ""
        echo -e "${C_DIM}Configuration that would be written:${C_RESET}"
        echo "$hardened_config" | head -10
        echo -e "${C_DIM}...${C_RESET}"
    else
        echo "$hardened_config" | $SUDO tee "$SSH_HARDENING_FILE" > /dev/null
        $SUDO chmod 644 "$SSH_HARDENING_FILE"
        SSH_CONFIG_CHANGED=1
    fi
    
    # Validate configuration
    print_info "Validating SSH configuration..."
    if $SUDO sshd -t 2>/dev/null; then
        print_success "SSH configuration is valid"
    else
        print_error "SSH configuration validation failed!"
        print_warning "Restoring backup..."
        $SUDO rm -f "$SSH_HARDENING_FILE"
        exit 1
    fi
    
    print_success "SSH hardening configuration applied"
    echo -e "    ${ICON_BULLET} Password authentication: ${C_RED}disabled${C_RESET}"
    echo -e "    ${ICON_BULLET} Root login: ${C_RED}disabled${C_RESET}"
    echo -e "    ${ICON_BULLET} Key authentication: ${C_GREEN}enabled${C_RESET}"
    echo -e "    ${ICON_BULLET} Max auth tries: ${C_CYAN}3${C_RESET}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: FAIL2BAN CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

do_fail2ban_config() {
    print_step "6" "Fail2ban Configuration"
    
    # Check if already configured
    if [[ -f "$FAIL2BAN_JAIL_FILE" ]]; then
        if $SUDO grep -q "enabled = true" "$FAIL2BAN_JAIL_FILE" 2>/dev/null; then
            print_verbose "Fail2ban SSH jail already configured"
            
            # Ensure service is running
            if ! systemctl is-active --quiet fail2ban; then
                run_cmd $SUDO systemctl enable --now fail2ban
            fi
            print_success "Fail2ban already configured and running"
            return 0
        fi
    fi
    
    # Create jail configuration
    local jail_config
    read -r -d '' jail_config << 'EOF' || true
# SSH protection jail
# Generated by harden-vps.sh

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
backend = systemd

# Ban settings
maxretry = 5
findtime = 600
bantime = 3600

# Aggressive mode for repeated offenders
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 86400
EOF
    
    # Write configuration
    if [[ $DRY_RUN -eq 1 ]]; then
        print_dry "Would write fail2ban jail config to $FAIL2BAN_JAIL_FILE"
    else
        $SUDO mkdir -p /etc/fail2ban/jail.d
        echo "$jail_config" | $SUDO tee "$FAIL2BAN_JAIL_FILE" > /dev/null
        $SUDO chmod 644 "$FAIL2BAN_JAIL_FILE"
    fi
    
    # Enable and start service
    run_cmd $SUDO systemctl enable fail2ban
    run_cmd $SUDO systemctl restart fail2ban
    
    print_success "Fail2ban configured"
    echo -e "    ${ICON_BULLET} Max retries: ${C_CYAN}5${C_RESET}"
    echo -e "    ${ICON_BULLET} Find time: ${C_CYAN}10 minutes${C_RESET}"
    echo -e "    ${ICON_BULLET} Ban time: ${C_CYAN}1 hour${C_RESET} (increases for repeat offenders)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: UFW FIREWALL CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

do_ufw_config() {
    print_step "7" "UFW Firewall Configuration"
    
    # Check current UFW status
    local ufw_status
    ufw_status=$($SUDO ufw status 2>/dev/null || echo "")
    
    local needs_config=1
    
    if echo "$ufw_status" | grep -q "Status: active"; then
        if echo "$ufw_status" | grep -q "22/tcp\|22 "; then
            print_verbose "UFW is active with SSH rule"
            needs_config=0
        fi
    fi
    
    if [[ $needs_config -eq 1 ]]; then
        print_info "Configuring firewall rules..."
        
        # Reset to defaults (non-interactive)
        if [[ $DRY_RUN -eq 1 ]]; then
            print_dry "Would reset UFW and configure rules"
        else
            # Disable first to avoid issues
            $SUDO ufw --force disable 2>/dev/null || true
            
            # Reset rules
            $SUDO ufw --force reset >/dev/null 2>&1
            
            # Set default policies
            $SUDO ufw default deny incoming >/dev/null
            $SUDO ufw default allow outgoing >/dev/null
            
            # Allow SSH (critical!)
            $SUDO ufw allow 22/tcp comment 'SSH' >/dev/null
            
            # Enable firewall
            $SUDO ufw --force enable >/dev/null
        fi
        
        print_success "Firewall configured"
    else
        # Ensure firewall is enabled
        if ! echo "$ufw_status" | grep -q "Status: active"; then
            run_cmd $SUDO ufw --force enable
        fi
        print_success "Firewall already configured"
    fi
    
    # Add Tailscale port if installed
    if command -v tailscale &>/dev/null; then
        if ! echo "$ufw_status" | grep -q "41641/udp"; then
            print_info "Adding Tailscale port..."
            run_cmd $SUDO ufw allow 41641/udp comment 'Tailscale'
        fi
    fi
    
    echo -e "    ${ICON_BULLET} Default incoming: ${C_RED}deny${C_RESET}"
    echo -e "    ${ICON_BULLET} Default outgoing: ${C_GREEN}allow${C_RESET}"
    echo -e "    ${ICON_BULLET} SSH (22/tcp): ${C_GREEN}allow${C_RESET}"
    
    # Enable service
    run_cmd $SUDO systemctl enable ufw 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: TAILSCALE VPN (Optional)
# ═══════════════════════════════════════════════════════════════════════════════

enable_ip_forwarding() {
    # Enable IP forwarding for Tailscale exit node functionality
    local sysctl_conf="/etc/sysctl.conf"
    
    # Check if already enabled
    if sysctl net.ipv4.ip_forward 2>/dev/null | grep -q "= 1"; then
        print_verbose "IP forwarding already enabled"
        return 0
    fi
    
    print_info "Enabling IP forwarding for exit node..."
    
    if [[ $DRY_RUN -eq 1 ]]; then
        print_dry "Would enable net.ipv4.ip_forward = 1"
        return 0
    fi
    
    # Add to sysctl.conf if not present
    if ! $SUDO grep -q "^net.ipv4.ip_forward" "$sysctl_conf" 2>/dev/null; then
        echo 'net.ipv4.ip_forward = 1' | $SUDO tee -a "$sysctl_conf" > /dev/null
    else
        $SUDO sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' "$sysctl_conf"
    fi
    
    # Also enable IPv6 forwarding
    if ! $SUDO grep -q "^net.ipv6.conf.all.forwarding" "$sysctl_conf" 2>/dev/null; then
        echo 'net.ipv6.conf.all.forwarding = 1' | $SUDO tee -a "$sysctl_conf" > /dev/null
    fi
    
    # Apply immediately
    $SUDO sysctl -p > /dev/null 2>&1 || true
    print_success "IP forwarding enabled"
}

do_tailscale_setup() {
    print_step "8" "Tailscale VPN (Optional)"
    
    local tailscale_installed=0
    local tailscale_connected=0
    
    if command -v tailscale &>/dev/null; then
        tailscale_installed=1
        
        local ts_status
        ts_status=$($SUDO tailscale status --self 2>&1 || echo "")
        
        # Check if connected (has an IP address in output)
        if echo "$ts_status" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"; then
            tailscale_connected=1
            print_success "Tailscale is already installed and connected"
            
            if echo "$ts_status" | grep -q "offers exit node"; then
                print_verbose "Configured as exit node"
            fi
            return 0
        else
            print_success "Tailscale is installed but not connected"
        fi
    fi
    
    # If not installed, ask to install
    if [[ $tailscale_installed -eq 0 ]]; then
        local should_install=0
        if [[ $AUTO_MODE -eq 1 ]]; then
            # In auto mode, install if TAILSCALE_AUTH_KEY is provided
            if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
                should_install=1
                print_info "Auto mode: Installing Tailscale (TAILSCALE_AUTH_KEY provided)"
            else
                print_info "Auto mode: Skipping Tailscale installation (set TAILSCALE_AUTH_KEY to enable)"
                return 0
            fi
        elif prompt_yn "Would you like to install Tailscale VPN?" "no"; then
            should_install=1
        fi
        
        if [[ $should_install -eq 0 ]]; then
            print_info "Skipping Tailscale installation"
            return 0
        fi
        
        print_info "Installing Tailscale..."
        
        if [[ $DRY_RUN -eq 1 ]]; then
            print_dry "Would download and run Tailscale installer"
            print_dry "Would prompt for auth key and configure as exit node"
            return 0
        fi
        
        # Download and install
        if ! curl -fsSL https://tailscale.com/install.sh | $SUDO sh; then
            print_error "Tailscale installation failed"
            return 1
        fi
        
        print_success "Tailscale installed"
        
        # Add firewall rule
        $SUDO ufw allow 41641/udp comment 'Tailscale' 2>/dev/null || true
    fi
    
    # At this point, Tailscale is installed but not connected
    # Offer to configure it
    if [[ $DRY_RUN -eq 1 ]]; then
        print_dry "Would prompt for Tailscale configuration"
        return 0
    fi
    
    local should_configure=0
    if [[ $AUTO_MODE -eq 1 ]]; then
        # In auto mode, configure if TAILSCALE_AUTH_KEY is provided
        if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
            should_configure=1
        else
            print_info "Auto mode: Skipping Tailscale configuration (set TAILSCALE_AUTH_KEY to enable)"
            return 0
        fi
    elif prompt_yn "Would you like to configure Tailscale now?" "yes"; then
        should_configure=1
    fi
    
    if [[ $should_configure -eq 0 ]]; then
        echo ""
        echo -e "  ${C_BOLD}Manual setup:${C_RESET}"
        echo -e "    ${C_CYAN}sudo tailscale up --advertise-exit-node --accept-routes --accept-dns=false --ssh${C_RESET}"
        return 0
    fi
    
    # Ask about exit node setup
    local setup_exit_node=0
    if prompt_yn "Configure this server as a Tailscale exit node?" "yes"; then
        setup_exit_node=1
        enable_ip_forwarding
    fi
    
    # Prompt for auth key in interactive mode
    echo ""
    echo -e "  ${C_BOLD}Tailscale Authentication:${C_RESET}"
    echo -e "  ${C_DIM}Get an auth key from: https://login.tailscale.com/admin/settings/keys${C_RESET}"
    echo ""
    
    local auth_key=""
    if [[ $AUTO_MODE -eq 1 ]]; then
        # In auto mode, check for auth key from environment variable
        if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
            auth_key="${TAILSCALE_AUTH_KEY}"
            print_info "Using Tailscale auth key from TAILSCALE_AUTH_KEY environment variable"
        else
            print_info "Auto mode: Skipping Tailscale configuration (set TAILSCALE_AUTH_KEY env var to enable)"
        fi
    else
        read -r -p "  Enter Tailscale auth key (or press Enter to skip): " auth_key || auth_key=""
    fi
    
    if [[ -n "$auth_key" ]]; then
        # Validate auth key format (starts with tskey-)
        if [[ ! "$auth_key" =~ ^tskey- ]]; then
            print_warning "Auth key should start with 'tskey-'. Proceeding anyway..."
        fi
        
        print_info "Connecting to Tailscale..."
        print_info "(You may need to approve the device in your browser)"
        
        # Build command array to safely pass auth key
        local ts_args=("tailscale" "up" "--authkey" "$auth_key" "--accept-routes" "--ssh")
        if [[ $setup_exit_node -eq 1 ]]; then
            ts_args+=("--advertise-exit-node")
        fi
        
        # Execute with array to avoid shell injection
        if $SUDO "${ts_args[@]}"; then
            print_success "Tailscale connected successfully"
            
            # Show connection info
            local ts_ip
            ts_ip=$($SUDO tailscale ip -4 2>/dev/null || echo "")
            if [[ -n "$ts_ip" ]]; then
                echo -e "    ${ICON_BULLET} Tailscale IP: ${C_CYAN}${ts_ip}${C_RESET}"
            fi
            
            if [[ $setup_exit_node -eq 1 ]]; then
                echo -e "    ${ICON_BULLET} Exit node: ${C_GREEN}advertised${C_RESET}"
                echo -e "    ${C_DIM}  (Enable in Tailscale admin console to use)${C_RESET}"
            fi
        else
            print_error "Failed to connect to Tailscale"
            print_info "Try manually: sudo tailscale up --accept-dns=false [..other options..]"
        fi
    else
        echo ""
        echo -e "  ${C_BOLD}Manual setup required:${C_RESET}"
        if [[ $setup_exit_node -eq 1 ]]; then
            echo -e "    ${C_CYAN}sudo tailscale up --advertise-exit-node --accept-routes --accept-dns=false --ssh${C_RESET}"
        else
            echo -e "    ${C_CYAN}sudo tailscale up --accept-routes --accept-dns=false --ssh${C_RESET}"
        fi
        echo -e "  ${C_DIM}Then authenticate in your browser${C_RESET}"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 9: APPLY CHANGES (SSH RESTART)
# ═══════════════════════════════════════════════════════════════════════════════

do_apply_changes() {
    print_step "9" "Apply Changes"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        print_dry "Would reload/restart SSH service to apply changes"
        return 0
    fi
    
    # If SSH config was changed, we need to reload SSH to apply changes
    # Using reload (SIGHUP) is safer than restart - it doesn't drop existing connections
    if [[ $SSH_CONFIG_CHANGED -eq 1 ]]; then
        print_info "SSH configuration was modified. Reloading SSH service..."
        
        # Try reload first (safer, doesn't drop connections)
        local ssh_reloaded=0
        if $SUDO systemctl reload ssh 2>/dev/null; then
            ssh_reloaded=1
        elif $SUDO systemctl reload sshd 2>/dev/null; then
            ssh_reloaded=1
        elif $SUDO kill -HUP "$(pgrep -o sshd)" 2>/dev/null; then
            # Fallback: send SIGHUP directly to sshd
            ssh_reloaded=1
        fi
        
        if [[ $ssh_reloaded -eq 1 ]]; then
            print_success "SSH service reloaded - new config is now active"
        else
            # Reload failed, try restart as fallback
            print_warning "Reload failed, attempting restart..."
            if $SUDO systemctl restart ssh 2>/dev/null || $SUDO systemctl restart sshd 2>/dev/null; then
                print_success "SSH service restarted successfully"
            else
                print_error "Failed to reload/restart SSH service"
                print_warning "Try manually: sudo systemctl restart ssh"
            fi
        fi
    else
        print_success "No SSH configuration changes - no reload needed"
    fi
    
    # Show connection info
    echo ""
    local suggested_user=""
    while IFS= read -r username; do
        if [[ -n "$username" ]]; then
            local auth_keys="/home/$username/.ssh/authorized_keys"
            if [[ -f "$auth_keys" ]] && [[ -s "$auth_keys" ]]; then
                suggested_user="$username"
                break
            fi
        fi
    done < <(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd 2>/dev/null)
    
    local host_ip
    host_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_SERVER_IP")
    
    echo -e "  ${C_BOLD}Connection Info:${C_RESET}"
    if [[ -n "$suggested_user" ]]; then
        echo -e "    ${ICON_ARROW} SSH: ${C_CYAN}ssh ${suggested_user}@${host_ip}${C_RESET}"
    fi
    
    # Show Tailscale info if available
    if command -v tailscale &>/dev/null; then
        local ts_ip
        ts_ip=$($SUDO tailscale ip -4 2>/dev/null || echo "")
        if [[ -n "$ts_ip" ]]; then
            echo -e "    ${ICON_ARROW} Tailscale: ${C_CYAN}ssh ${suggested_user:-USER}@${ts_ip}${C_RESET}"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 10: FINAL SECURITY AUDIT
# ═══════════════════════════════════════════════════════════════════════════════

do_final_audit() {
    if [[ $VERBOSE -eq 0 ]]; then
        return 0
    fi
    
    print_step "10" "Final Security Audit"
    do_security_audit
    
    # Print summary recommendations
    echo ""
    echo -e "  ${C_BOLD}Security Improvements Applied:${C_RESET}"
    echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} System packages updated"
    echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} Non-root user with SSH key configured"
    echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} Password authentication disabled"
    echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} Root SSH login disabled"
    echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} Fail2ban protecting SSH"
    echo -e "    ${C_GREEN}${ICON_SUCCESS}${C_RESET} UFW firewall active"
    
    echo ""
    echo -e "  ${C_BOLD}Post-Hardening Notes:${C_RESET}"
    echo -e "    ${ICON_BULLET} Log in as your non-root user, then use ${C_CYAN}sudo${C_RESET}"
    echo -e "    ${ICON_BULLET} Root login is now ${C_RED}blocked${C_RESET}"
    echo -e "    ${ICON_BULLET} Password login is ${C_RED}disabled${C_RESET} - keys only"
    echo -e "    ${ICON_BULLET} If locked out, use your cloud provider's console"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    parse_args "$@"
    check_interactive
    setup_sudo
    
    print_banner
    check_ubuntu_version
    
    # Execute all steps
    do_security_audit
    do_system_update
    do_unattended_upgrades
    do_install_packages
    do_user_handling
    do_ssh_hardening
    do_fail2ban_config
    do_ufw_config
    do_tailscale_setup
    do_apply_changes
    do_final_audit
    
    # Final summary
    print_summary
    
    if [[ $DRY_RUN -eq 1 ]]; then
        echo ""
        echo -e "  ${C_MAGENTA}This was a dry-run. No changes were made.${C_RESET}"
        echo -e "  Run without ${C_CYAN}--dry-run${C_RESET} to apply changes."
    fi
    
    echo ""
}

main "$@"
