#!/bin/bash
echo "=== SSH SECURITY AUDIT ==="
echo ""

echo "--- 1. PASSWORD AUTHENTICATION ---"
result=$(sudo sshd -T | grep "^passwordauthentication")
echo "$result"
if echo "$result" | grep -q "passwordauthentication no"; then
    echo "✅ Password authentication is DISABLED"
else
    echo "❌ WARNING: Password authentication may be ENABLED"
fi
echo ""

echo "--- 2. ROOT LOGIN ---"
result=$(sudo sshd -T | grep "^permitrootlogin")
echo "$result"
if echo "$result" | grep -qE "permitrootlogin (no|prohibit-password)"; then
    echo "✅ Root login is properly restricted"
else
    echo "❌ WARNING: Root login may be allowed"
fi
echo ""

echo "--- 3. PUBLIC KEY AUTHENTICATION ---"
result=$(sudo sshd -T | grep "^pubkeyauthentication")
echo "$result"
if echo "$result" | grep -q "pubkeyauthentication yes"; then
    echo "✅ SSH key authentication is ENABLED"
else
    echo "❌ WARNING: SSH key authentication may be disabled"
fi
echo ""

echo "--- 4. FAIL2BAN STATUS ---"
if command -v fail2ban-client &> /dev/null; then
    echo "✅ Fail2ban is installed"
    if sudo systemctl is-active --quiet fail2ban; then
        echo "✅ Fail2ban is RUNNING"
        echo ""
        echo "Active jails:"
        sudo fail2ban-client status
        echo ""
        if sudo fail2ban-client status 2>/dev/null | grep -q "sshd"; then
            echo "✅ SSH jail is active"
            echo ""
            echo "SSH jail details:"
            sudo fail2ban-client status sshd
        else
            echo "⚠️  SSH jail may not be configured"
        fi
    else
        echo "❌ Fail2ban is installed but NOT RUNNING"
    fi
else
    echo "❌ Fail2ban is NOT INSTALLED"
fi
echo ""

echo "--- 5. RECENT SSH AUTHENTICATION ATTEMPTS ---"
echo "Last 5 successful logins:"
sudo grep "Accepted" /var/log/auth.log 2>/dev/null | tail -5
echo ""
echo "Recent failed login attempts:"
sudo grep "Failed password\|authentication failure" /var/log/auth.log 2>/dev/null | tail -5
echo ""

echo "--- 6. CURRENT SSH SESSIONS ---"
who
echo ""

echo "=== AUDIT COMPLETE ==="