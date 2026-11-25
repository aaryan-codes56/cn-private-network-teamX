#!/bin/bash
# Extension F - systematic, layer-by-layer diagnosis from a CLIENT Mac.
#   scripts/diagnose.sh                                   # https://app.team1.test/api/status
#   scripts/diagnose.sh https://app.team1.test:8443/api/config
#   CA=~/Downloads/app.crt scripts/diagnose.sh            # if curl does not read the keychain
#
# Order (bottom-up through the request path, stops at the first broken layer):
#   0 client config -> 1 DNS -> 2 IP (ping) -> 3 TCP -> 4 TLS -> 5 HTTP via edge -> 6 backends
set -uo pipefail
source "$(dirname "$0")/team.env"
URL="${1:-https://$DOMAIN/api/status}"
HOST=$(printf '%s' "$URL" | sed -E 's#^[a-z]+://([^/:]+).*#\1#')
PORT=$(printf '%s' "$URL" | sed -nE 's#^[a-z]+://[^/:]+:([0-9]+).*#\1#p'); PORT=${PORT:-443}
CAARGS=(); [ -n "${CA:-}" ] && CAARGS=(--cacert "$CA")
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
pass() { echo "  ${G}PASS${N} $*"; }
fail() { echo "  ${R}FAIL${N} $*"; }
warn() { echo "  ${Y}WARN${N} $*"; }
info() { echo "       $*"; }
hdr()  { awk -F': ' -v k="$1" 'tolower($1)==k{sub(/\r$/,"",$2); print $2}' "$TMP/h"; }
verdict() {
    echo; echo "${B}==> FIRST FAILING LAYER: $1${N}"; shift
    for l in "$@"; do echo "    - $l"; done
    exit 1
}
is_ip() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

echo "${B}Diagnosing $URL   (host=$HOST port=$PORT)   $(date +%H:%M:%S)${N}"

# ---------------------------------------------------------------- 0. client config
echo; echo "${B}[0] Client configuration${N}"
MYIP=$(ipconfig getifaddr en0 2>/dev/null)
info "this Mac: ${MYIP:-no IPv4 on en0}   gateway: $(route -n get default 2>/dev/null | awk '/gateway/{print $2}')"
NS=$(scutil --dns | awk '/^resolver #1/{f=1} f&&/nameserver\[/{print $3} f&&/^$/{exit}' | tr '\n' ' ')
info "DNS servers in use: ${NS:-none}"
case " $NS " in
  *" $MAC1_IP "*|*" $BACKUP_DNS_IP "*) pass "client points at a team DNS server" ;;
  *) warn "client is NOT using team DNS ($MAC1_IP / $BACKUP_DNS_IP) -> fix: scripts/set_client_dns.sh both" ;;
esac

# ---------------------------------------------------------------- 1. DNS
echo; echo "${B}[1] DNS - Application layer, UDP 53${N}"
declare -a ANS=()
for ns in "$MAC1_IP" "$BACKUP_DNS_IP"; do
    a=$(dig +time=2 +tries=1 @"$ns" "$HOST" A +noall +answer 2>/dev/null | awk '$4=="A"{print $5" ttl="$2; exit}')
    if [ -n "$a" ]; then info "@$ns  -> $a"; ANS+=("${a%% *}")
    else warn "DNS server $ns gave no answer (dnsmasq stopped / host down / record missing)"; fi
done
if [ "${#ANS[@]}" -eq 2 ] && [ "${ANS[0]}" != "${ANS[1]}" ]; then
    warn "primary and backup DNS DISAGREE (${ANS[0]} vs ${ANS[1]}) - a record was changed on only one server"
fi
IP=$(dscacheutil -q host -a name "$HOST" 2>/dev/null | awk '/ip_address/{print $2; exit}')
if ! is_ip "${IP:-}"; then
    fail "the OS resolver cannot resolve $HOST"
    verdict "DNS" "client DNS settings: networksetup -getdnsservers Wi-Fi (expect $MAC1_IP $BACKUP_DNS_IP)" \
        "is dnsmasq running? on the DNS Macs: sudo brew services list | grep dnsmasq ; dig @127.0.0.1 $HOST" \
        "record present? grep host-record \$(brew --prefix)/etc/dnsmasq.conf" \
        "typo in the name? (.test, not .local)" \
        "IP connectivity can still be fine - try: ping $MAC2_IP"
fi
pass "$HOST -> $IP   (OS resolver = what curl/browser use)"
case "$IP" in
  "$MAC2_IP") info "= Mac 2, primary edge" ;;
  "$STANDBY_EDGE_IP") info "= standby edge (DNS cutover active?)" ;;
  *) warn "$IP is NOT a known edge (primary $MAC2_IP / standby $STANDBY_EDGE_IP) -> wrong A record? stale cache? (scripts/flush_dns.sh)" ;;
esac

# ---------------------------------------------------------------- 2. IP
echo; echo "${B}[2] IP - Network layer (ICMP)${N}"
if ping -c 2 -t 3 "$IP" >/dev/null 2>&1; then pass "$IP answers ping"
else warn "$IP does not answer ping (host off / left the Wi-Fi / wrong IP / ICMP blocked) - continuing"; fi

# ---------------------------------------------------------------- 3. TCP
echo; echo "${B}[3] TCP - Transport layer, port $PORT${N}"
nc -vz -G 4 -w 4 "$IP" "$PORT" > "$TMP/nc" 2>&1; rc=$?
if [ $rc -eq 0 ]; then pass "TCP handshake to $IP:$PORT completed (SYN, SYN-ACK, ACK)"
elif grep -qi refused "$TMP/nc"; then
    fail "connection REFUSED - host is up and sent a RST: nothing is listening on $PORT"
    verdict "TCP (port / service)" "is nginx running on the edge? sudo brew services list | grep nginx ; sudo nginx -t" \
        "right port? edge listens on 443 (or 8443 if that is your setup): sudo lsof -nP -iTCP:$PORT -sTCP:LISTEN" \
        "nginx config error after an edit? tail \$(brew --prefix)/var/log/nginx/error.log"
else
    fail "connection TIMED OUT - no reply at all to our SYN"
    verdict "TCP / IP path" "wrong IP in the DNS record? (step 1)" "edge Mac asleep or off the Wi-Fi? ping $IP" \
        "firewall dropping port $PORT on the edge? sudo pfctl -sr ; sudo pfctl -a com.apple/team1 -sr"
fi

# ---------------------------------------------------------------- 4. TLS
echo; echo "${B}[4] TLS - handshake + certificate${N}"
openssl s_client -connect "$IP:$PORT" -servername "$HOST" </dev/null > "$TMP/tls" 2>&1
if ! grep -q "BEGIN CERTIFICATE" "$TMP/tls"; then
    fail "TLS handshake failed - no certificate received"
    info "$(grep -iE 'error|alert|wrong version' "$TMP/tls" | head -2)"
    verdict "TLS" "is the edge speaking TLS on $PORT? (listen 443 ssl;)" \
        "ssl_certificate / ssl_certificate_key paths in team1.conf ; sudo nginx -t"
fi
openssl x509 -in "$TMP/tls" -noout -subject -enddate > "$TMP/cert" 2>/dev/null
info "$(sed -n 1p "$TMP/cert")"; info "$(sed -n 2p "$TMP/cert")"
info "protocol: $(grep -E '^ *Protocol *:|New, TLS' "$TMP/tls" | head -1 | sed 's/^ *//')"
SAN=$(openssl x509 -in "$TMP/tls" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/^ *//')
info "SAN: ${SAN:-none}"
openssl x509 -in "$TMP/tls" -noout -checkend 0 >/dev/null 2>&1 || fail "certificate is EXPIRED"
case "$SAN" in *"DNS:$HOST"*) pass "certificate covers $HOST" ;; *) fail "certificate does NOT list $HOST" ;; esac
curl -sS ${CAARGS[@]+"${CAARGS[@]}"} -o /dev/null --connect-timeout 5 --max-time 10 "https://$HOST:$PORT/edge-health" 2> "$TMP/curltls"; rc=$?
if [ $rc -eq 60 ] || [ $rc -eq 51 ] || [ $rc -eq 35 ]; then
    fail "curl rejects the certificate (curl exit $rc): $(head -1 "$TMP/curltls")"
    verdict "TLS (trust / name)" "is app.crt trusted on this client? security find-certificate -c app.team1.test /Library/Keychains/System.keychain" \
        "did the edge get a NEW certificate? re-trust it (configs/TLS-setup.md step 2)" \
        "try: CA=~/Downloads/app.crt scripts/diagnose.sh   (curl not reading the keychain)" \
        "never 'fix' this with curl -k in the demo"
fi
pass "certificate trusted by this client, TLS handshake OK"

# ---------------------------------------------------------------- 5. HTTP
echo; echo "${B}[5] HTTP - Application layer through the edge${N}"
code=$(curl -s ${CAARGS[@]+"${CAARGS[@]}"} -o "$TMP/b" -D "$TMP/h" -w '%{http_code}' --connect-timeout 5 --max-time 25 "$URL")
info "HTTP $code   X-Edge=$(hdr x-edge)  X-Backend=$(hdr x-backend)  X-Upstream=$(hdr x-upstream) ($(hdr x-upstream-status))"
EH=$(curl -s ${CAARGS[@]+"${CAARGS[@]}"} -o /dev/null -w '%{http_code}' --max-time 5 "https://$HOST:$PORT/edge-health")
[ "$EH" = "200" ] && pass "nginx itself is healthy (/edge-health = 200)"
case "$code" in
  2??|304) pass "request served by Backend $(hdr x-backend)"; BACKCHECK=0 ;;
  404) warn "404 - wrong path? backends serve /, /api/status, /api/config"; BACKCHECK=0 ;;
  502|503|504) fail "HTTP $code from nginx - the edge works but NO backend answered"; BACKCHECK=1 ;;
  *) fail "unexpected HTTP $code"; BACKCHECK=1 ;;
esac

# ---------------------------------------------------------------- 6. backends
if [ "$BACKCHECK" -eq 1 ] || [ "${BACKENDS:-0}" = 1 ]; then
    echo; echo "${B}[6] Backends (behind the edge)${N}"
    [ "$MYIP" != "$MAC2_IP" ] && info "note: run this on Mac 2 - with Ext C firewall on, a TIMEOUT from a client is expected"
    for t in "A $MAC3_IP $PORT_A" "B $MAC4_IP $PORT_B"; do
        set -- $t
        nc -vz -G 3 -w 3 "$2" "$3" > "$TMP/nc" 2>&1 && pass "Backend $1 $2:$3 TCP open" \
            || { grep -qi refused "$TMP/nc" && fail "Backend $1 $2:$3 REFUSED (backend process not running)" \
                 || fail "Backend $1 $2:$3 TIMEOUT (Mac off/asleep, or pf blocking this Mac)"; }
    done
    [ "$BACKCHECK" -eq 1 ] && verdict "APPLICATION / BACKEND (behind the edge)" \
        "start the backends: python3 backend/backend.py A 3001 (Mac 3), B 3002 (Mac 4)" \
        "upstream IPs/ports in team1.conf match the backends? (Mac changed IP?)" \
        "nginx error log names the failing upstream: tail \$(brew --prefix)/var/log/nginx/error.log" \
        "pf on the backend allows the edge? sudo pfctl -a com.apple/team1 -t edges -T show"
fi

echo; echo "${B}==> ALL LAYERS OK${N}: DNS -> IP -> TCP -> TLS -> HTTP -> backend"
