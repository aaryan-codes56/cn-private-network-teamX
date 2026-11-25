#!/bin/bash
# Send repeated HTTPS requests BY NAME and show who answered (Tasks D, Ext D, Ext E).
#   scripts/lb_test.sh                 # 6 requests
#   scripts/lb_test.sh 20 1            # 20 requests, 1 s apart
#   scripts/lb_test.sh 0 1             # forever, 1 s apart (Ctrl+C to stop)
#   URL=https://app.team1.test/api/config scripts/lb_test.sh
# If curl does not trust the keychain on this Mac:  CA=~/Downloads/app.crt scripts/lb_test.sh
set -uo pipefail
source "$(dirname "$0")/team.env"
N="${1:-6}"; INT="${2:-0.3}"
URL="${URL:-https://$DOMAIN/api/status}"
CAARGS=(); [ -n "${CA:-}" ] && CAARGS=(--cacert "$CA")
HDR=$(mktemp); trap 'rm -f "$HDR"' EXIT

h() { awk -F': ' -v k="$1" 'tolower($1)==k{sub(/\r$/,"",$2); print $2}' "$HDR"; }

printf "%-4s %-9s %-5s %-13s %-8s %-13s %s\n" "#" "time" "code" "edge-ip" "backend" "edge" "upstream tried (status)"
i=0
while [ "$N" -eq 0 ] || [ "$i" -lt "$N" ]; do
    i=$((i+1)); : > "$HDR"
    out=$(curl -s ${CAARGS[@]+"${CAARGS[@]}"} -o /dev/null -D "$HDR" -w '%{http_code} %{remote_ip}' \
          --connect-timeout 5 --max-time 20 "$URL"); rc=$?
    code=${out%% *}; ip=${out#* }
    [ "$rc" -ne 0 ] && code="ERR$rc"
    printf "%-4s %-9s %-5s %-13s %-8s %-13s %s (%s)\n" "$i" "$(date +%H:%M:%S)" "$code" "${ip:--}" \
        "$(h x-backend)" "$(h x-edge)" "$(h x-upstream)" "$(h x-upstream-status)"
    sleep "$INT"
done
