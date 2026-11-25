#!/bin/bash
# Run on EVERY Mac before the demo: checks this Mac's IP against team.env,
# pings the others and lists which team services are listening here.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/team.env"

MYIP=$(ipconfig getifaddr en0 2>/dev/null)
echo "This Mac : ${MYIP:-NO IPv4 ON en0}  mask $(ipconfig getoption en0 subnet_mask 2>/dev/null)  gw $(route -n get default 2>/dev/null | awk '/gateway/{print $2}')"
echo "MAC addr : $(ifconfig en0 2>/dev/null | awk '/ether/{print $2}')   interface: en0"
echo "DNS      : $(scutil --dns | awk '/^resolver #1/{f=1} f&&/nameserver\[/{print $3} f&&/^$/{exit}' | tr '\n' ' ')"

case "$MYIP" in
  "$MAC1_IP") echo "Role     : Mac 1 - primary DNS + client" ;;
  "$MAC2_IP") echo "Role     : Mac 2 - primary edge" ;;
  "$MAC3_IP") echo "Role     : Mac 3 - Backend A + backup DNS" ;;
  "$MAC4_IP") echo "Role     : Mac 4 - Backend B + standby edge" ;;
  *) echo "!! This IP is not in scripts/team.env. If DHCP changed it, run:"
     echo "   scripts/retarget_ip.sh <old-ip-of-this-mac> $MYIP" ;;
esac

echo; echo "Reachability:"
for t in "Mac1 $MAC1_IP" "Mac2 $MAC2_IP" "Mac3 $MAC3_IP" "Mac4 $MAC4_IP"; do
    set -- $t
    if ping -c 2 -t 3 "$2" >/dev/null 2>&1; then echo "  $1 $2  OK"; else echo "  $1 $2  NO REPLY"; fi
done

echo; echo "Team services listening on this Mac:"
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 && $9 ~ /:(443|8443|3001|3002)$/ {print "  tcp "$9"  "$1}' | sort -u
pgrep -x dnsmasq >/dev/null && echo "  udp :53  dnsmasq (running)"
pgrep -x nginx   >/dev/null || echo "  (nginx not running here)"
true
