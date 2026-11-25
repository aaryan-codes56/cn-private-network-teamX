# Phase 2 Runbook: Harden, Recover, Troubleshoot

Step-by-step commands for every Phase 2 extension. Each step says **which Mac** runs it, **what you should see**, and **which screenshot** to save in `evidence/`.
Run every command from the repository folder (`cd cn-private-network-teamx`) on every Mac.

| Mac | Person | Phase 1 role | Added in Phase 2 |
|---|---|---|---|
| Mac 1 | Aaryan | Primary DNS (dnsmasq) + client + Wireshark | TTL 30 s on records |
| Mac 2 | Vivek | Primary edge: nginx, TLS, load balancer | Failover headers, `/edge-health` |
| Mac 3 | Pratik | Backend A :3001 | **pf firewall** (Ext C) |
| Mac 4 | Raghvendra | Backend B :3002 + client | **Backup DNS** (Ext A) + **standby edge nginx** (Ext E) + **pf firewall** (Ext C) |

> **As run on 25 Nov:** the backup DNS was planned on Mac 3, but Mac 3 is a managed Mac whose Application Firewall cannot be changed, so it was moved to **Mac 4** (`BACKUP_DNS_IP=$MAC4_IP` in `scripts/team.env`). Mac 4 runs the dnsmasq binary copied from Mac 1: `sudo ~/dnsmasq -C configs/phase2/dnsmasq-backup.conf --pid-file=/tmp/dnsmasq-team1.pid` (stop: `sudo pkill dnsmasq`). Where the steps below say "Mac 3" for DNS, use Mac 4; to change its record, edit `configs/phase2/dnsmasq-backup.conf` and restart it.

---

## 0. Pre-flight (all Macs, ~5 minutes)

1. Copy the latest repository to all 4 Macs (AirDrop the zip, or `git pull`).
2. Keep every laptop awake. Wi-Fi power saving caused timeouts in Phase 1:
   ```bash
   caffeinate -dimsu &
   ```
3. Check the IP address on every Mac. **DHCP can change it between sessions.** On 25 Nov, Mac 1 came back as `10.7.23.224` instead of `10.7.6.152`.
   ```bash
   scripts/preflight.sh
   ```
   If a Mac's IP changed, run this on every Mac (or on one Mac, then re-share the repo):
   ```bash
   scripts/retarget_ip.sh <old-ip> <new-ip>
   ```
   This updates `scripts/team.env` and all `configs/phase2/*.conf`. Then redeploy the configs that changed (section 1). If the edge IP changed, the certificate stays valid: it names `app.team1.test`, not an IP.
4. Start the Phase 1 stack:
   ```bash
   python3 backend/backend.py A 3001        # Mac 3
   python3 backend/backend.py B 3002        # Mac 4
   ```
5. Point the clients (Mac 1 and Mac 4; Mac 2 too if you like) at **both** DNS servers:
   ```bash
   scripts/set_client_dns.sh both           # -> 10.7.23.224 (Mac 1) then 10.7.13.204 (Mac 4)
   ```

## 1. Deploy the Phase 2 configs (once)

**Mac 1: primary DNS with TTL 30 s**
```bash
sudo cp configs/phase2/dnsmasq-primary.conf $(brew --prefix)/etc/dnsmasq.conf
sudo brew services restart dnsmasq
dig @127.0.0.1 app.team1.test +noall +answer      # app.team1.test. 30 IN A 10.7.11.1
```

**Backup DNS (Extension A), planned on Mac 3, run on Mac 4 (see note at the top)**
```bash
brew install dnsmasq
sudo cp configs/phase2/dnsmasq-backup.conf $(brew --prefix)/etc/dnsmasq.conf
sudo brew services start dnsmasq
dig @127.0.0.1 app.team1.test +noall +answer      # same answer as Mac 1
```
If the macOS Application Firewall is on, allow dnsmasq to receive connections:
`sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add $(realpath $(brew --prefix)/sbin/dnsmasq) --unblockapp $(realpath $(brew --prefix)/sbin/dnsmasq)`

**Mac 2: primary edge, Phase 2 config**
```bash
cp configs/phase2/team1.conf $(brew --prefix)/etc/nginx/servers/team1.conf
sudo nginx -t && sudo brew services restart nginx
```

**Mac 4: standby edge (Extension E)**
```bash
brew install nginx
# copy app.crt AND app.key from Mac 2 (AirDrop) into the nginx folder:
cp ~/Downloads/app.crt ~/Downloads/app.key $(brew --prefix)/etc/nginx/
rm ~/Downloads/app.key                                  # do not leave the private key lying around
cp configs/phase2/team1-standby.conf $(brew --prefix)/etc/nginx/servers/team1.conf
sudo nginx -t && sudo brew services start nginx
```
Pre-check from Mac 1. `--resolve` skips DNS, so use it only for this pre-check:
```bash
curl --resolve app.team1.test:443:10.7.13.204 https://app.team1.test/edge-health   # {"edge":"mac4-standby",...}
```

**Sanity check from a client**
```bash
scripts/lb_test.sh            # 200, A/B alternating, edge mac2-primary
```

---

## Extension A: Backup DNS resolver

| # | Mac | Command | Expected | Screenshot |
|---|---|---|---|---|
| 1 | Mac 4 | `scripts/set_client_dns.sh both` | two servers: 10.7.23.224, 10.7.4.180 | `EXTA_1_client_two_dns.png` |
| 2 | Mac 3 | `dig @127.0.0.1 app.team1.test` | `10.7.11.1`, TTL 30, same records as Mac 1 | `EXTA_2_backup_records.png` |
| 3 | Mac 4 | `dig app.team1.test` | `SERVER: 10.7.23.224#53` (primary answers) | `EXTA_3_primary_answers.png` |
| 4 | Mac 1 | `sudo brew services stop dnsmasq` | primary DNS down | |
| 5 | Mac 3 | `log stream --info --predicate 'process == "dnsmasq"'` | leave running: shows queries reaching the backup | |
| 6 | Mac 4 | `dig app.team1.test` | `communications error to 10.7.23.224#53: connection refused`, then the answer from `SERVER: 10.7.4.180#53` | `EXTA_4_failover_dig.png` |
| 7 | Mac 4 | `scripts/flush_dns.sh; scripts/lb_test.sh 4` | still HTTP 200 **by name**: the OS resolver fell back to the backup | `EXTA_5_service_still_works.png` |
| 8 | Mac 3 | (terminal from step 5) | `query[A] app.team1.test from 10.7.13.204` | `EXTA_6_backup_log.png` |
| 9 | Mac 1 | `sudo brew services start dnsmasq` | restore | |

**DNS failure vs application failure**: show both, side by side.
- Both DNS servers stopped: `dig` times out and curl says `Could not resolve host`. **The name cannot be turned into an IP.** `ping 10.7.11.1` still works.
- DNS up, both backends stopped: `dig` answers `10.7.11.1`, TLS works, nginx returns **502**. **Resolution works, but the service is down.** (Phase 1 `FAIL4_502.png`.)

---

## Extension D: High-availability failover (Step 8 of the demo)

nginx uses **passive health checks**. A backend that refuses or times out is retried on the other backend (`proxy_next_upstream`). After `max_fails=3` failures in `fail_timeout=10s`, it is taken out of rotation for 10 s, then tried again.

| # | Mac | Command | Expected | Screenshot |
|---|---|---|---|---|
| 1 | Mac 1 | `scripts/lb_test.sh 0 1` (leave running) | A, B, A, B … `upstream tried` shows one backend | `EXTD_1_both_healthy.png` |
| 2 | Mac 2 | `tail -f $(brew --prefix)/var/log/nginx/error.log` | leave running | |
| 3 | Mac 3 | **Ctrl+C** on Backend A | | |
| 4 | Mac 1 | (watch) | **every** reply is 200 from **B**. Some lines show `10.7.4.180:3001, 10.7.13.204:3002 (502, 200)`: nginx tried A, it failed, and nginx retried on B within the same request. Other lines show only `10.7.13.204:3002`: A is marked down | `EXTD_2_A_down_all_B.png` |
| 5 | Mac 2 | (error.log) | `connect() failed (61: Connection refused) while connecting to upstream ... 10.7.4.180:3001` | `EXTD_3_nginx_error_log.png` |
| 6 | Mac 3 | `python3 backend/backend.py A 3001` | | |
| 7 | Mac 1 | (watch) | within ~10 s, A and B alternate again | `EXTD_4_A_back.png` |

The test harness showed exactly this (nginx 1.31 + this repo's `backend.py`, 25 Nov):
```
both up   : A B A B A B                                   upstream (200)
A stopped : B (502, 200)  B (200)  B (502, 200)  B (200) ...   -> client never sees an error
A back    : B A B A B A
both down : 502  upstream 3002, 3001 (502, 502)
```

**Single point of failure, and how to remove it.** The edge (nginx on Mac 2) is still a single point of failure: if Mac 2 dies, every request fails even though both backends are healthy. The Wi-Fi router and the single LAN are SPOFs too. Fixes:
1. Two active edges sharing a **virtual IP** with VRRP (keepalived). The standby takes over the IP within about a second, so no DNS change is needed.
2. **DNS failover with health checks** (like Route 53 health checks): automatically point the name at the standby edge. Clients still wait out the TTL. Extension E does this manually.
3. In the cloud, the load balancer itself is a managed, multi-AZ service (AWS ALB, GCP LB), so the provider removes this SPOF.

---

## Extensions B + E: TTL and DNS-based cutover to the standby edge (Step 9 of the demo)

This one procedure proves both extensions. The A record for `app.team1.test` moves from Mac 2 (`10.7.11.1`) to the standby edge Mac 4 (`10.7.13.204`), and you watch the 30 s TTL hold clients on the old edge.

> Using a **browser**? Chrome has its own DNS cache (about 1 min). Use `curl`/the scripts for this demo, or clear Chrome's cache at `chrome://net-internals/#dns`.
> If Ext C pf rules are ON, allow the standby edge to reach Backend A first. On Mac 3: `sudo pfctl -a com.apple/team1 -t edges -T add 10.7.13.204`

**Setup: two terminals on Mac 4 and one on Mac 1**
```bash
# Mac 4, terminal 1: what the DNS servers say vs. what the OS cache returns
scripts/dns_watch.sh app.team1.test 2
# Mac 4, terminal 2: which edge actually serves the traffic
scripts/lb_test.sh 0 2
# Mac 1:
dig app.team1.test       # TTL column = 30 (Phase 1 was 0 = "never cache")   -> EXTB_1_ttl30.png
```

| # | Mac | Command | Expected | Screenshot |
|---|---|---|---|---|
| 1 | Mac 4 | (both terminals running) | OS-cache `10.7.11.1`, edge `mac2-primary` | |
| 2 | **Mac 1 and Mac 4** (straight after each other) | `scripts/dns_set_record.sh app.team1.test 10.7.13.204` | `app.team1.test. 30 IN A 10.7.13.204`. **Write down the time** (T0) | `EXTE_1_record_changed.png` |
| 3 | Mac 4 | (watch) | `@primary`/`@backup` columns show `10.7.13.204` **immediately**, but the **OS-cache column still shows 10.7.11.1** and the edge is still `mac2-primary` | `EXTB_2_cached_old_answer.png` |
| 4 | Mac 4 | (watch) | **≤ 30 s after T0**, OS-cache flips to `10.7.13.204` and the edge becomes `mac4-standby`. Note the time | `EXTB_3_ttl_expired_switch.png` |
| 5 | Mac 1 + Mac 4 | `scripts/dns_set_record.sh app.team1.test 10.7.11.1` | cut back to the primary | |
| 6 | Mac 1 | `scripts/flush_dns.sh; scripts/lb_test.sh 2` | **immediately** `mac2-primary`: the flushed client did a new lookup | `EXTB_4_flush_immediate.png` |
| 7 | Mac 4 | (watch, not flushed) | still `mac4-standby` for up to 30 s. **Cached clients briefly still hit the old edge while new lookups go to the new one** | `EXTE_2_cached_vs_new.png` |

Both edges show the **same certificate**, so no client sees a TLS warning during the cutover.

**Why `dig` and `curl` disagree:** `dig` asks the DNS server directly and bypasses the macOS cache. `curl`, the browser and `dscacheutil` go through mDNSResponder, which keeps the answer for the TTL. That gap *is* the TTL effect.

**In production:** lower the TTL (e.g. 3600 → 60 s) a day **before** a migration so old answers expire quickly. Change the record, then keep the old edge running until the old TTL has passed (connection draining), and only then switch it off. TTL trades how fast you can cut over against DNS query load.

---

## Extension C: Service isolation with the pf firewall

The rules live in `configs/phase2/pf-backends.conf` and load into the pf **anchor** `com.apple/team1`. The stock `/etc/pf.conf` already evaluates `com.apple/*`, so **`/etc/pf.conf` is never edited**. Rollback copies go to `/var/tmp/team1-pf/` before anything changes.

| # | Mac | Command | Expected | Screenshot |
|---|---|---|---|---|
| 1 | Mac 1 | `nc -vz -G 5 10.7.4.180 3001` (before) | `succeeded`: anyone can reach the backend directly | `EXTC_1_before_open.png` |
| 2 | Mac 3 **and** Mac 4 | `sudo scripts/pf_enable.sh` | rules + allowed edge `10.7.11.1` printed | `EXTC_2_rules_mac3.png` |
| 3 | Mac 1 | `nc -vz -G 5 10.7.4.180 3001` and `nc -vz -G 5 10.7.13.204 3002` | **`Operation timed out`**: SYN dropped | `EXTC_3_client_blocked.png` |
| 4 | Mac 1 | `ping -c 3 10.7.4.180` and `nc -vz -G 5 10.7.4.180 3999` | ping works (host reachable). Port 3999 gives `Connection refused` (closed port = RST), compared with 3001 timing out (filtered = dropped) | `EXTC_4_ping_vs_port.png` |
| 5 | Mac 2 | `nc -vz 10.7.4.180 3001` and `curl -s http://10.7.4.180:3001/api/status` | **succeeded**: the edge is allowed | `EXTC_5_edge_allowed.png` |
| 6 | Mac 1 | `scripts/lb_test.sh` | still 200, A/B alternate **through the edge** | `EXTC_6_service_still_works.png` |
| 7 | Mac 1 (optional) | Wireshark, filter `tcp.port==3001`, repeat step 3 | SYN, then `[TCP Retransmission]` SYNs, never a SYN-ACK | `EXTC_7_wireshark_syn_dropped.png` |
| 8 | Mac 3 **and** Mac 4 | `sudo scripts/pf_disable.sh` | anchor empty, `/etc/pf.conf identical to the backup` | `EXTC_8_rollback.png` |
| 9 | Mac 1 | `nc -vz -G 5 10.7.4.180 3001` | `succeeded` again: original configuration restored | |

---

## Extension F: Faculty-injected fault (Step 10 of the demo)

Say each step **out loud**. Marks are given for the method even if the fix is incomplete. Run on a client:

```bash
scripts/diagnose.sh                      # walks DNS -> IP -> TCP -> TLS -> HTTP -> backends, stops at the first broken layer
```
Then confirm by hand with the command for that layer, find the cause, fix it, and re-run `scripts/diagnose.sh` until it says **ALL LAYERS OK**.
The full fault table is in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Final demonstration sequence (Section 8 of the brief)

| # | Step | Who / where | Command or artefact |
|---|---|---|---|
| 1 | Topology + IP/service inventory | anyone | `README.md`, `docs/topology.png`, `docs/topology-phase2.png` |
| 2 | All machines on the LAN | every Mac | `scripts/preflight.sh` (IP, MAC, gateway, pings) |
| 3 | Resolve the private domain | Mac 4 | `dig app.team1.test` → `10.7.11.1`, `SERVER: 10.7.23.224#53` |
| 4 | HTTPS by name, no warnings | Mac 1 | browser `https://app.team1.test` (padlock) + `curl -v https://app.team1.test/api/status` (no `-k`) |
| 5 | Load balancing | Mac 1 | `scripts/lb_test.sh` → A, B, A, B |
| 6 | Wireshark DNS/TCP/TLS | Mac 1 | open the Phase 1 capture; point at the DNS query/response, SYN/SYN-ACK/ACK, ClientHello/ServerHello/Certificate |
| 7 | Headers + caching | Mac 1 | `curl -I https://app.team1.test/api/config`, then the same with `-H 'If-None-Match: "<etag>"'` → 304 |
| 8 | Fail one backend | Mac 3 + Mac 1 | Extension D above |
| 9 | Phase 2 DNS resilience | all | Extension A (backup DNS), then B+E (TTL + cutover) |
| 10 | Faculty fault | client | Extension F: `scripts/diagnose.sh` + TROUBLESHOOTING.md |
| 11 | Viva | each member | individual questions |

## After the demo: restore everything
```bash
sudo scripts/pf_disable.sh                                   # Mac 3, Mac 4
scripts/dns_set_record.sh app.team1.test 10.7.11.1           # Mac 1 (+ Mac 4's backup config, if still cut over)
sudo brew services stop nginx                                # Mac 4 (standby)
scripts/set_client_dns.sh reset                              # clients: back to normal Wi-Fi DNS
```
