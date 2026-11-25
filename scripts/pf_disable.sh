#!/bin/bash
# Extension C - ROLLBACK. Run on Mac 3 and Mac 4:   sudo scripts/pf_disable.sh
# Removes our anchor and releases our pf enable reference -> original state restored.
set -uo pipefail
ANCHOR="com.apple/team1"
STATE=/var/tmp/team1-pf

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo:  sudo $0"; exit 1; }

pfctl -a "$ANCHOR" -F all 2>/dev/null && echo "Flushed rules + tables in anchor $ANCHOR"

if [ -s "$STATE/token" ] && [ "$(cat "$STATE/token")" != "none" ]; then
    pfctl -X "$(cat "$STATE/token")" 2>&1 | sed 's/^/  /'
    rm -f "$STATE/token"
fi

echo
echo "== pf status now : $(pfctl -s info 2>/dev/null | head -1)"
echo "== pf status before Ext C: $(cat "$STATE/status-before.txt" 2>/dev/null)"
echo "== rules left in anchor $ANCHOR:"
pfctl -a "$ANCHOR" -sr 2>/dev/null | sed 's/^/  /'; echo "  (empty = removed)"
if [ -f "$STATE/pf.conf.backup" ]; then
    cmp -s /etc/pf.conf "$STATE/pf.conf.backup" && echo "== /etc/pf.conf identical to the backup (never modified)" \
        || echo "!! /etc/pf.conf differs from backup - restore with: sudo cp $STATE/pf.conf.backup /etc/pf.conf && sudo pfctl -f /etc/pf.conf"
fi
