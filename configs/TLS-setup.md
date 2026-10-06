# TLS certificate setup

## 1. Create the certificate (Mac 2)
```bash
cd $(brew --prefix)/etc/nginx
openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout app.key -out app.crt \
  -subj "/CN=app.team1.test" \
  -addext "subjectAltName=DNS:app.team1.test,DNS:api.team1.test" \
  -addext "extendedKeyUsage=serverAuth"
```
- `app.crt` = public certificate (shared with clients)
- `app.key` = private key (kept secret on Mac 2, NOT in this repo)

## 2. Trust it on every client Mac (Mac 1, Mac 4)
Download the public certificate straight from the edge (or AirDrop app.crt), then trust it:
```bash
openssl s_client -connect 10.7.11.1:443 -servername app.team1.test </dev/null 2>/dev/null | openssl x509 -out ~/Downloads/app.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/app.crt
```

## 3. Verify (no -k flag)
```bash
curl -v https://app.team1.test/api/status
# if macOS curl does not read the keychain:
curl -v --cacert ~/Downloads/app.crt https://app.team1.test/api/status
```

## TLS handshake (what Wireshark shows)
ClientHello -> ServerHello -> Certificate -> Key Exchange -> Finished -> encrypted Application Data.
TLS is terminated at nginx (Mac 2); nginx talks plain HTTP to the backends on the private LAN.
