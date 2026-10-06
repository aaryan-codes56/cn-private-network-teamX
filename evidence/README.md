# Evidence – Phase 1 (TeamX)

Put every screenshot in this folder with exactly these names.

| Task | File | Taken on | Shows |
|---|---|---|---|
| A | A_mac1_network.png … A_mac4_network.png | each Mac | IP, subnet, gateway, MAC address (en0) |
| A | A_ping_mac1.png … A_ping_mac4.png | each Mac | ping to the other Macs, 0% loss |
| B | B_dns_server_mac1.png | Mac 1 | `dig @10.7.6.152 app.team1.test` → 10.7.11.1 |
| B | B_dns_client_mac3.png | Mac 3 | dig + nslookup via Mac 1 |
| B | B_dns_client_mac4.png | Mac 4 | dig + nslookup via Mac 1 |
| C | C_backends_direct.png | Mac 1 | direct curl to 3001 (X-Backend: A) and 3002 (X-Backend: B) |
| D | D_load_balancing.png | Mac 1 | A, B, A, B, A, B |
| E | E_browser_padlock.png | Mac 1 | https://app.team1.test, "Connection is secure" |
| E | E_cert_details.png | Mac 1 | certificate for app.team1.test |
| E | E_http1_vs_http2.png | Mac 1 | ALPN http/1.1 vs h2 |
| F | F_cache_headers.png | Mac 1 | cache-control: public, max-age=60 + ETag |
| F | F_304.png | Mac 1 | HTTP/2 304, content-length 0 |
| F | F_browser_cache.png | Mac 1 | DevTools Network: 304 / disk cache |
| G | G_curl_headers.png | Mac 1 | curl -v: DNS, TCP, TLS 1.3, cert verify ok, HTTP/2, headers |
| G | G_wireshark_dns.png | Mac 1 | DNS query/response, UDP 53 |
| G | G_tcp_handshake.png | Mac 1 | SYN, SYN-ACK to port 443 |
| G | G_tcp_seq_ack.png | Mac 1 | sequence / acknowledgment numbers |
| G | G_tls_handshake.png | Mac 1 | ClientHello, ServerHello, Certificate |
| G | G_tls_encrypted.png | Mac 1 | encrypted Application Data |
| G | phase1_capture.pcapng | Mac 1 | full Wireshark capture |
| Fail 1 | FAIL1_wrong_dns_server.png | Mac 1 | NXDOMAIN from 8.8.8.8, ping still works |
| Fail 2 | FAIL2_wrong_record.png | Mac 1 | dig → 10.7.11.99, curl timeout |
| Fail 3 | FAIL3_one_backend.png | Mac 1 | all X-Backend: B |
| Fail 4 | FAIL4_502.png | Mac 1 | HTTP/2 502 from nginx |
| Fail 5 | FAIL5_wrong_port.png | Mac 1 | port 9999 connection refused, ping works |
