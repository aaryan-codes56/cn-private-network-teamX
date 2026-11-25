#!/bin/bash
# Watch DNS answers over time on a CLIENT Mac (Extension A, B, E).
#   scripts/dns_watch.sh [name] [interval-seconds]
#
# Columns:
#   OS-cache   = what macOS (mDNSResponder) returns -> what curl and the browser really use.
#                Cached for the record's TTL, so it lags behind a record change.
#   @primary/@backup = asked directly with dig (bypasses the OS cache) -> what each server says NOW,
#                with the TTL it hands out. "down" = that DNS server is not answering.
set -uo pipefail
source "$(dirname "$0")/team.env"
NAME="${1:-$DOMAIN}"
INT="${2:-2}"

ask() {   # ask <server>
    local out
    out=$(dig +time=1 +tries=1 @"$1" "$NAME" A +noall +answer 2>/dev/null | awk '$4=="A"{print $5" (ttl "$2")"; exit}')
    echo "${out:-down}"
}

printf "%-9s %-17s %-26s %-26s\n" "time" "OS-cache" "@primary $MAC1_IP" "@backup $BACKUP_DNS_IP"
while true; do
    os=$(dscacheutil -q host -a name "$NAME" 2>/dev/null | awk '/ip_address/{print $2; exit}')
    printf "%-9s %-17s %-26s %-26s\n" "$(date +%H:%M:%S)" "${os:-NO ANSWER}" "$(ask "$MAC1_IP")" "$(ask "$BACKUP_DNS_IP")"
    sleep "$INT"
done
