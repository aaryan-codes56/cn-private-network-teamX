#!/usr/bin/env python3
"""
CN Phase 1 - Simple REST backend.
Run on Mac 3:  python3 backend.py A 3001
Run on Mac 4:  python3 backend.py B 3002

Uses only the Python standard library (no pip install needed).
Binds to 0.0.0.0 so other machines on the LAN can reach it.
"""
import hashlib
import json
import socket
import sys
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

if len(sys.argv) != 3:
    print("Usage: python3 backend.py <A|B> <port>")
    sys.exit(1)

NAME = sys.argv[1].upper()
PORT = int(sys.argv[2])
HOST = socket.gethostname()

# Same on both backends so the ETag matches whichever backend answers
CONFIG = {"service": "private-network-service", "version": "1.0", "phase": 1}
CONFIG_BODY = json.dumps(CONFIG).encode()
CONFIG_ETAG = '"' + hashlib.md5(CONFIG_BODY).hexdigest() + '"'


class Handler(BaseHTTPRequestHandler):
    server_version = "TeamBackend/1.0"

    def send(self, code, obj=None, extra_headers=None, include_body=True):
        data = b"" if code == 304 else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("X-Backend", NAME)
        for k, v in (extra_headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if include_body and data:
            self.wfile.write(data)

    def handle_path(self, include_body):
        path = self.path.split("?")[0]

        if path == "/":
            self.send(200, {
                "message": f"Backend {NAME} is running",
                "backend": NAME,
                "host": HOST,
                "port": PORT,
                "endpoints": ["/", "/api/status", "/api/config"],
            }, include_body=include_body)

        elif path == "/api/status":
            self.send(200, {
                "backend": NAME,
                "status": "ok",
                "time": datetime.now().isoformat(timespec="seconds"),
            }, {"Cache-Control": "no-store"}, include_body)

        elif path == "/api/config":
            # Caching demo endpoint: Cache-Control + ETag + 304 support
            headers = {"Cache-Control": "public, max-age=60", "ETag": CONFIG_ETAG}
            if self.headers.get("If-None-Match") == CONFIG_ETAG:
                self.send(304, None, headers, False)
            else:
                self.send(200, CONFIG, headers, include_body)

        else:
            self.send(404, {"error": "not found", "backend": NAME}, include_body=include_body)

    def do_GET(self):
        self.handle_path(True)

    def do_HEAD(self):  # curl -I sends HEAD
        self.handle_path(False)

    def log_message(self, fmt, *args):
        print(f"[Backend {NAME}] {self.client_address[0]}:{self.client_address[1]} - {fmt % args}")


if __name__ == "__main__":
    print(f"Backend {NAME} listening on 0.0.0.0:{PORT}  (Ctrl+C to stop)")
    try:
        ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        print(f"\nBackend {NAME} stopped")
