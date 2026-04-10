#!/bin/bash
# File: dns_debug.sh
# Stand: 2025-10-26

echo "🔍 DNS & Network Debug for formulae.brew.sh"
echo "Timestamp: $(date)"

# Direct IP resolution
echo "=== 1. DNS Resolution ==="
nslookup formulae.brew.sh 8.8.8.8 2>/dev/null | grep "Address:"
dig @8.8.8.8 formulae.brew.sh +short

echo -e "\n=== 2. System DNS Test ==="
host formulae.brew.sh

echo -e "\n=== 3. Direct IP Connection ==="
# Get IP and test direct connection
IP=$(dig @8.8.8.8 +short formulae.brew.sh | head -n1)
if [ -n "$IP" ]; then
    echo "Target IP: $IP"
    nc -zv $IP 443 2>&1 | grep -E "(succeeded|open)"
    curl -I --connect-timeout 5 --resolve formulae.brew.sh:443:$IP https://formulae.brew.sh 2>/dev/null | head -3 || echo "Direct IP curl failed"
else
    echo "❌ Cannot resolve IP"
fi

echo -e "\n=== 4. Network Diagnostics ==="
ping -c 2 8.8.8.8 >/dev/null 2>&1 && echo "✅ Internet connectivity OK" || echo "❌ No internet"
traceroute formulae.brew.sh 2>/dev/null | head -3 || echo "Traceroute failed"

echo -e "\n=== 5. Homebrew Status ==="
ls -la ~/Library/Caches/Homebrew/api/ 2>/dev/null || echo "API cache missing"
brew doctor --quiet 2>/dev/null && echo "✅ brew doctor passes" || echo "⚠️ brew doctor issues"