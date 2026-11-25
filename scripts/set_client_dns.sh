#!/bin/bash
# Point this Mac's Wi-Fi DNS at the team servers (Extension A).
#   scripts/set_client_dns.sh both      -> Mac 1 (primary) + backup DNS (Mac 3)   [Phase 2 default]
#   scripts/set_client_dns.sh primary   -> Mac 1 only (Phase 1 setting)
#   scripts/set_client_dns.sh google    -> 8.8.8.8 (Failure 1: wrong DNS server)
#   scripts/set_client_dns.sh reset     -> back to DHCP-provided DNS
set -euo pipefail
source "$(dirname "$0")/team.env"
SVC="${WIFI_SERVICE:-Wi-Fi}"

case "${1:-both}" in
  both)    sudo networksetup -setdnsservers "$SVC" "$MAC1_IP" "$BACKUP_DNS_IP" ;;
  primary) sudo networksetup -setdnsservers "$SVC" "$MAC1_IP" ;;
  google)  sudo networksetup -setdnsservers "$SVC" 8.8.8.8 ;;
  reset)   sudo networksetup -setdnsservers "$SVC" Empty ;;
  *) echo "usage: $0 both|primary|google|reset"; exit 1 ;;
esac

sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
echo "DNS servers on $SVC:"; networksetup -getdnsservers "$SVC" | sed 's/^/  /'
echo "Resolver order used by macOS:"; scutil --dns | awk '/^resolver #1/{f=1} f&&/nameserver/{print "  "$0} f&&/^$/{exit}'
