# Troubleshooting Playbook (Extension F)

**Method:** go up the request path one layer at a time and stop at the **first** layer that fails. Everything above it is a symptom, not the cause.

```
0 client config ─► 1 DNS ─► 2 IP ─► 3 TCP ─► 4 TLS ─► 5 HTTP via edge ─► 6 backend
   (which DNS?)    (name→IP)  (ping)  (port)  (cert)   (nginx status)      (app)
```

Fast path: `scripts/diagnose.sh` (on a client) runs all of these checks and prints `FIRST FAILING LAYER`.

## Manual checks per layer

| Layer | Command (from a client unless noted) | Healthy result |
|---|---|---|
| 0 Client config | `networksetup -getdnsservers Wi-Fi` · `scutil --dns \| head -12` | `10.7.23.224`, `10.7.4.180` |
| 1 DNS | `dig app.team1.test` · `dig @10.7.23.224 app.team1.test` · `dig @10.7.4.180 app.team1.test` · `dscacheutil -q host -a name app.team1.test` | `10.7.11.1`, TTL 30, both servers agree |
| 2 IP | `ping -c 3 10.7.11.1` | replies, 0% loss |
| 3 TCP | `nc -vz -G 5 10.7.11.1 443` | `succeeded` |
| 4 TLS | `openssl s_client -connect 10.7.11.1:443 -servername app.team1.test </dev/null \| openssl x509 -noout -subject -enddate -text \| grep -A1 "Alternative Name"` · `curl -v https://app.team1.test/edge-health` | CN/SAN `app.team1.test`, not expired, `SSL certificate verify ok` |
| 5 HTTP (edge) | `curl -sI https://app.team1.test/edge-health` · `curl -sI https://app.team1.test/api/status` | `200` and `200`. If the first is 200 and the second is 502/504, the problem is **behind** nginx |
| 6 Backend (run on **Mac 2**) | `nc -vz 10.7.4.180 3001` · `nc -vz 10.7.13.204 3002` · `curl -s http://10.7.4.180:3001/api/status` · `tail -20 $(brew --prefix)/var/log/nginx/error.log` | `succeeded`, JSON with `"backend"` |

**Reading TCP results:** `Connection refused` = the host answered with RST, so nothing is listening on that port (service down or wrong port). `Operation timed out` = no answer at all (wrong IP, Mac asleep or off the Wi-Fi, or a firewall dropping the SYN).
**Reading HTTP results:** `502 Bad Gateway` = nginx could not connect to any backend (refused). `504 Gateway Time-out` = nginx connected or waited but no backend answered in time.

## Likely injected faults

| Fault the faculty may inject | What you see | First failing layer | Confirm with | Fix |
|---|---|---|---|---|
| Client DNS set to 8.8.8.8 / removed | `Could not resolve host`; `ping 10.7.11.1` works | 0/1 DNS (client) | `networksetup -getdnsservers Wi-Fi` | `scripts/set_client_dns.sh both` |
| dnsmasq stopped on Mac 1 **and** Mac 4 | `dig` times out / `connection refused` on 53 | 1 DNS (server) | `dig @10.7.23.224 …`, `sudo brew services list` on the DNS Macs | `sudo brew services start dnsmasq` |
| dnsmasq stopped on Mac 1 only | still works (slower first lookup) | none: Ext A doing its job | `dig` shows `SERVER: 10.7.4.180` | start it again |
| Record deleted / typo in name (`app.tem1.test`) | `NXDOMAIN` | 1 DNS (data) | `grep host-record $(brew --prefix)/etc/dnsmasq.conf` | fix the line, `sudo brew services restart dnsmasq` |
| Record points to wrong IP (e.g. `10.7.11.99`) | `dig` answers, curl **times out** | 1 DNS (data) → shows up at 3 TCP | `dig` answer ≠ Mac 2's IP | `scripts/dns_set_record.sh app.team1.test 10.7.11.1` on **both** DNS Macs, then `scripts/flush_dns.sh` |
| Record changed on only one DNS server | answers differ between clients / over time | 1 DNS (inconsistency) | `dig @10.7.23.224` vs `dig @10.7.4.180` | make both identical |
| Stale cache after a fix | dig shows the right IP, curl still goes to the old one | 1 DNS (client cache) | `dscacheutil -q host -a name app.team1.test` | `scripts/flush_dns.sh` (or wait for the 30 s TTL) |
| nginx stopped on Mac 2 | `Connection refused` on 443; ping OK | 3 TCP | `nc -vz 10.7.11.1 443`; on Mac 2 `sudo brew services list` | `sudo nginx -t && sudo brew services start nginx` |
| nginx `listen` port changed (e.g. 8443) | 443 refused, 8443 open | 3 TCP | on Mac 2 `sudo lsof -nP -iTCP -sTCP:LISTEN \| grep nginx` | restore `listen 443 ssl;` and reload, or use the right port in the URL |
| Client uses the wrong port (`:9999`) | `Connection refused` | 3 TCP | the URL | use 443 |
| pf/firewall blocking 443 on Mac 2 | `Operation timed out` on 443, ping OK | 3 TCP | on Mac 2 `sudo pfctl -sr`, `sudo pfctl -a com.apple/team1 -sr` | remove the rule (`sudo pfctl -a <anchor> -F all`) |
| Edge Mac asleep / changed IP | ping and TCP time out | 2 IP | `scripts/preflight.sh` on Mac 2 | wake it; `scripts/retarget_ip.sh old new`, update the DNS record |
| Certificate not trusted on the client | curl `(60) SSL certificate problem`, browser warning | 4 TLS (trust) | `security find-certificate -c app.team1.test /Library/Keychains/System.keychain` | re-add `app.crt` as trusted (configs/TLS-setup.md). **Never use `-k`** |
| Wrong cert/key in nginx (other CN, expired, mismatched key) | `nginx -t` fails, or curl `SSL: no alternative certificate subject name matches` | 4 TLS | `openssl s_client … \| openssl x509 -noout -subject -enddate` | point `ssl_certificate` at the right `app.crt` / `app.key`; `sudo nginx -t` |
| `ssl_protocols` limited to something the client won't do | `handshake failure` / `alert protocol version` | 4 TLS | `curl -v` shows where the handshake stops | `ssl_protocols TLSv1.2 TLSv1.3;` |
| One backend stopped | all `X-Backend: B` (or A), still 200 | none: Ext D doing its job | `X-Upstream` header shows the failed attempt | start the backend |
| Both backends stopped | `502 Bad Gateway`, `/edge-health` still 200 | 6 backend | on Mac 2 `nc -vz` to 3001/3002 → refused | start the backends |
| Wrong upstream IP/port in nginx | 502 or 504 even though backends run | 5/6 edge config | `error.log`: `connect() failed … upstream: "http://10.7.4.180:3010"` | fix `upstream backends {}`, `sudo nginx -t && sudo nginx -s reload` |
| Backend bound to 127.0.0.1 only | works on that Mac, 502 from nginx | 6 backend | on the backend Mac `lsof -nP -iTCP:3001 -sTCP:LISTEN` shows `127.0.0.1:3001` | bind to `0.0.0.0` |
| pf on a backend not allowing the edge | 504 after ~10 s (SYN dropped) | 6 backend (network policy) | on the backend `sudo pfctl -a com.apple/team1 -t edges -T show` | `sudo pfctl -a com.apple/team1 -t edges -T add 10.7.11.1` |

## What to say out loud (template)

1. "First I check **name resolution**: `dig app.team1.test` returns … from server … so DNS is fine / broken."
2. "Next, **IP reachability**: `ping` the address DNS gave us …"
3. "Then **TCP**: `nc -vz` to port 443 is refused/timed out/succeeded, which means …"
4. "Then **TLS**: the certificate is for app.team1.test, valid until …, and curl verifies it …"
5. "Then **HTTP**: nginx's own `/edge-health` is 200, but `/api/status` is 502, so the edge works and the fault is **behind** it …"
6. "On Mac 2 I test the backends directly and read nginx's `error.log` …"
7. "Root cause: … Fix: … Re-test: `scripts/diagnose.sh` now says ALL LAYERS OK."
