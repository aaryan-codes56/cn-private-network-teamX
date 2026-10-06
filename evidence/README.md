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

## To be added before the final evaluation
- `A_ping_mac1.png` … `A_ping_mac4.png` – ping between all machines
- `D_load_balancing.png` – terminal loop showing A, B, A, B, A, B (output recorded in the main README)
- `F_browser_cache.png` – DevTools Network tab showing 304 / disk cache
- `phase1_capture.pcapng` – saved Wireshark capture
