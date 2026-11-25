#!/bin/bash
# Extension C - Service isolation. Run on Mac 3 and Mac 4:   sudo scripts/pf_enable.sh
# Loads configs/phase2/pf-backends.conf into pf anchor com.apple/team1.
# /etc/pf.conf is NOT modified. Rollback: sudo scripts/pf_disable.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES="$ROOT/configs/phase2/pf-backends.conf"
ANCHOR="com.apple/team1"
STATE=/var/tmp/team1-pf

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo:  sudo $0"; exit 1; }
mkdir -p "$STATE"

# --- rollback copies (taken BEFORE any change) ---
cp /etc/pf.conf "$STATE/pf.conf.backup"
pfctl -sr > "$STATE/rules-before.txt" 2>/dev/null || true
pfctl -s info 2>/dev/null | head -1 > "$STATE/status-before.txt" || true
echo "Rollback copies saved in $STATE"

# The stock macOS ruleset contains:  anchor "com.apple/*"  - make sure it is loaded
if ! pfctl -sr 2>/dev/null | grep -q 'anchor "com.apple/\*"'; then
    echo "Main ruleset not loaded - loading the unmodified /etc/pf.conf"
    pfctl -f /etc/pf.conf 2>/dev/null
fi

pfctl -n -a "$ANCHOR" -f "$RULES"                # syntax check first
pfctl -a "$ANCHOR" -f "$RULES"
TOKEN=$(pfctl -E 2>&1 | awk '/Token/{print $NF}')
echo "${TOKEN:-none}" > "$STATE/token"

echo
echo "== pf status:  $(pfctl -s info 2>/dev/null | head -1)"
echo "== rules in anchor $ANCHOR:"
pfctl -a "$ANCHOR" -sr 2>/dev/null
echo "== allowed edges:"
pfctl -a "$ANCHOR" -t edges -T show 2>/dev/null
echo
echo "Test from Mac 1 (should TIME OUT):   nc -vz -G 5 <this-mac-ip> <3001|3002>"
echo "Test from Mac 2 (should SUCCEED):    nc -vz -G 5 <this-mac-ip> <3001|3002>"
echo "Ext E - allow the standby edge too:  sudo pfctl -a $ANCHOR -t edges -T add <mac4-ip>"
