#!/bin/bash
# A Mac got a new IP from DHCP? Replace it in team.env and every Phase 2 config.
#   scripts/retarget_ip.sh 10.7.6.152 10.7.23.224
# Afterwards re-deploy the changed config on the Mac that uses it (dnsmasq / nginx / pf),
# and re-run scripts/set_client_dns.sh both on the clients if a DNS server IP changed.
set -euo pipefail
OLD="${1:?usage: $0 <old-ip> <new-ip>}"; NEW="${2:?usage: $0 <old-ip> <new-ip>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ESC=$(printf '%s' "$OLD" | sed 's/\./\\./g')

for f in "$ROOT"/scripts/team.env "$ROOT"/configs/phase2/*.conf; do
    if grep -Eq "(^|[^0-9.])$ESC([^0-9.]|$)" "$f"; then
        sed -i '' -E "s/(^|[^0-9.])$ESC([^0-9.]|$)/\1$NEW\2/g" "$f"
        echo "updated  ${f#$ROOT/}"
    fi
done
echo "Now redeploy the configs that changed (see docs/PHASE2_RUNBOOK.md, section 0)."
