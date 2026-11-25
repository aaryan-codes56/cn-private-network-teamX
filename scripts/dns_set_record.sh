#!/bin/bash
# Change a project DNS record on THIS DNS server (Extension B / E).
# Run on BOTH Mac 1 (primary) and Mac 3 (backup) so they keep giving the same answer.
#
#   scripts/dns_set_record.sh app.team1.test 10.7.2.250   # cut over to standby edge (Mac 4)
#   scripts/dns_set_record.sh app.team1.test 10.7.11.1    # back to primary edge (Mac 2)
set -euo pipefail
NAME="${1:?usage: $0 <name> <ip>}"
IP="${2:?usage: $0 <name> <ip>}"

if [ -d /opt/homebrew/etc ]; then PREFIX=/opt/homebrew; else PREFIX=/usr/local; fi
CONF="$PREFIX/etc/dnsmasq.conf"
[ -f "$CONF" ] || { echo "No $CONF - is dnsmasq installed on this Mac?"; exit 1; }
grep -q "^host-record=$NAME," "$CONF" || { echo "No host-record for $NAME in $CONF"; exit 1; }

ESC_NAME=$(printf '%s' "$NAME" | sed 's/\./\\./g')
echo "before: $(grep "^host-record=$NAME," "$CONF")"
sudo sed -i '' -E "s/^(host-record=$ESC_NAME,)[0-9.]+/\1$IP/" "$CONF"
echo "after : $(grep "^host-record=$NAME," "$CONF")"

sudo brew services restart dnsmasq >/dev/null
sleep 1
echo "$(date +%H:%M:%S)  dnsmasq restarted. Server now answers:"
dig @127.0.0.1 "$NAME" +noall +answer
