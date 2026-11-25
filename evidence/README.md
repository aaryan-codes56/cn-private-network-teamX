# Evidence – Phase 1 (TeamX)

| Task | File | Taken on | Shows |
|---|---|---|---|
| A | [A_mac1_network.png](A_mac1_network.png) | Mac 1 | IP 10.7.6.152, subnet, gateway, MAC (en0) |
| A | [A_mac2_network.png](A_mac2_network.png) | Mac 2 | IP 10.7.11.1, subnet, gateway, MAC (en0) |
| A | [A_mac3_network.png](A_mac3_network.png) | Mac 3 | IP 10.7.6.153, subnet, gateway, MAC (en0) |
| A | [A_mac4_network.png](A_mac4_network.png) | Mac 4 | IP 10.7.2.250, subnet, gateway, MAC (en0) |
| B | [B_dig_server.png](B_dig_server.png) | Mac 1 | `dig @10.7.6.152 app.team1.test` → 10.7.11.1 |
| B | [B_dns_client_mac3.png](B_dns_client_mac3.png) | Mac 3 | dig + nslookup resolved through Mac 1 |
| B | [B_dns_client_mac4.png](B_dns_client_mac4.png) | Mac 4 | dig + nslookup resolved through Mac 1 |
| C | [C_backendA_direct.png](C_backendA_direct.png) | Mac 1 | direct request to Backend A :3001 → `X-Backend: A` |
| C | [C_backendB_direct.png](C_backendB_direct.png) | Mac 1 | direct request to Backend B :3002 → `X-Backend: B` |
| D | [D_browser_backend_B.png](D_browser_backend_B.png) | Mac 1 | browser reload served by Backend B (round-robin) |
| E | [E_browser_padlock.png](E_browser_padlock.png) | Mac 1 | https://app.team1.test, connection secure, no warning |
| E | [E_cert_details.png](E_cert_details.png) | Mac 1 | certificate for app.team1.test |
| E | [E_http1_vs_http2.png](E_http1_vs_http2.png) | Mac 1 | ALPN http/1.1 vs h2 |
| F | [F_cache_headers.png](F_cache_headers.png) | Mac 1 | `cache-control: public, max-age=60` + ETag |
| F | [F_304.png](F_304.png) | Mac 1 | conditional request → `HTTP/2 304`, `content-length: 0` |
| G | [G_curl_headers.png](G_curl_headers.png) | Mac 1 | curl -v: DNS, TCP, TLS 1.3, cert verify ok, HTTP/2, headers |
| G | [G_wireshark_dns.png](G_wireshark_dns.png) | Mac 1 | DNS query/response, UDP 53 (loopback, Mac 1 is its own resolver) |
| G | [G_tcp_handshake.png](G_tcp_handshake.png) | Mac 1 | SYN, SYN-ACK, port 51677 → 443 |
| G | [G_tcp_seq_ack.png](G_tcp_seq_ack.png) | Mac 1 | full connection: seq/ack numbers, TLS handshake, application data, FIN |
| G | [G_tls_handshake.png](G_tls_handshake.png) | Mac 1 | Client Hello (SNI), Server Hello, Certificate, key exchange |
| G | [G_tls_encrypted.png](G_tls_encrypted.png) | Mac 1 | encrypted Application Data |
| Fail 1 | [FAIL1_wrong_dns_server.png](FAIL1_wrong_dns_server.png) | Mac 1 | NXDOMAIN from 8.8.8.8, ping still works |
| Fail 2 | [FAIL2_wrong_record.png](FAIL2_wrong_record.png) | Mac 1 | dig → 10.7.11.99, curl timeout |
| Fail 3 | [FAIL3_one_backend.png](FAIL3_one_backend.png) | Mac 1 | Backend A stopped → every response `X-Backend: B` |
| Fail 4 | [FAIL4_502.png](FAIL4_502.png) | Mac 1 | both backends stopped → `HTTP/2 502` from nginx |
| Fail 5 | [FAIL5_wrong_port.png](FAIL5_wrong_port.png) | Mac 1 | port 9999 connection refused, ping works |

## Shown live instead of as screenshots

These were demonstrated live during the review; their results are recorded in the main README and the Phase 2 report.

- Ping between all machines – `scripts/preflight.sh` on each Mac (0% loss)
- Load balancing loop – A, B, A, B, A, B (terminal output in the main README; also `EXTD_1_both_healthy.png`)
- Browser cache – DevTools Network tab (304 also shown with curl in `F_304.png`)
- Wireshark capture – opened live; key packets in the `G_*.png` screenshots

# Evidence – Phase 2

Commands for each screenshot are in [docs/PHASE2_RUNBOOK.md](../docs/PHASE2_RUNBOOK.md). Phase 2 IPs: Mac 1 10.7.23.224 · Mac 2 10.7.11.1 · Mac 3 10.7.4.180 · Mac 4 10.7.13.204.

| Ext | File | Taken on | Shows |
|---|---|---|---|
| A | [EXTA_1_client_two_dns.png](EXTA_1_client_two_dns.png) | Mac 1 | client lists two DNS servers: 10.7.23.224 (Mac 1), 10.7.13.204 (Mac 4) |
| A | [EXTA_2_backup_records.png](EXTA_2_backup_records.png) | Mac 4 | backup DNS answers `app.team1.test → 10.7.11.1`, TTL 30 |
| A | [EXTA_3_primary_answers.png](EXTA_3_primary_answers.png) | Mac 1 | normally the primary answers (SERVER 10.7.23.224) |
| A | [EXTA_4_failover_dig.png](EXTA_4_failover_dig.png) | Mac 1 | primary stopped → `connection refused`, answer from SERVER 10.7.13.204 |
| A | [EXTA_5_service_still_works.png](EXTA_5_service_still_works.png) | Mac 1 | site still 200 by name with the primary DNS down |
| B | [EXTB_1_ttl30.png](EXTB_1_ttl30.png) | Mac 1 | record TTL 30 |
| B / E | [EXTB_2_cached_old_answer.png](EXTB_2_cached_old_answer.png) | Mac 1 | record changed to the standby edge at 21:05:45 |
| B / E | [EXTB_3_ttl_expired_switch.png](EXTB_3_ttl_expired_switch.png) | Mac 1 | cached client on `mac2-primary` until 21:05:56, `mac4-standby` from 21:05:58 (13 s) |
| B | [EXTB_4_flush_immediate.png](EXTB_4_flush_immediate.png) | Mac 1 | after switching back + cache flush: `mac2-primary` immediately |
| C | [EXTC_1_before_open.png](EXTC_1_before_open.png) | Mac 1 | before pf: port 3001 reachable directly |
| C | [EXTC_2_rules_mac3.png](EXTC_2_rules_mac3.png), [EXTC_2_rules_mac4.png](EXTC_2_rules_mac4.png) | Mac 3 / 4 | pf rules loaded, only the edge 10.7.11.1 allowed |
| C | [EXTC_3_client_blocked.png](EXTC_3_client_blocked.png) | Mac 1 | 3001 / 3002 `Operation timed out`, ping 0% loss |
| C | [EXTC_6_service_still_works.png](EXTC_6_service_still_works.png) | Mac 1 | service still A/B through the edge with pf on |
| C | [EXTC_8_rollback_mac3.png](EXTC_8_rollback_mac3.png), [EXTC_8_rollback_mac4.png](EXTC_8_rollback_mac4.png) | Mac 3 / 4 | rollback: pf disabled, anchor empty, `/etc/pf.conf` unchanged |
| D | [EXTD_1_both_healthy.png](EXTD_1_both_healthy.png) | Mac 1 | both backends healthy, A/B alternating |
| D | [EXTD_2_A_down_all_B.png](EXTD_2_A_down_all_B.png) | Mac 1 | Backend A stopped: all 200 from B, `(502, 200)` = same-request failover |
| D | [EXTD_4_A_back.png](EXTD_4_A_back.png) | Mac 3 | Backend A restarted, receiving requests from nginx again |
| F | live | – | faculty-injected fault, diagnosed during the evaluation with `scripts/diagnose.sh` |
