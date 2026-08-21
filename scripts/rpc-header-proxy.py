#!/usr/bin/env python3
"""Local HTTP proxy that injects one static header onto every request before
forwarding it to an upstream JSON-RPC endpoint.

Foundry's forking and broadcast code paths (`vm.createSelectFork`, `forge
script --rpc-url`) build their RPC provider straight from a URL string with
no way to attach custom headers — see the RPC_HEADER_SECRET comments in
scripts/deploy-v3-multichain.sh and scripts/with-rpc-header-proxy.sh. This
proxy exists so those code paths can still reach an RPC endpoint that
requires a header (e.g. x-internal-service-secret) by pointing FOUNDRY_RPC_URL
at 127.0.0.1 instead of the upstream endpoint directly.

Usage: rpc-header-proxy.py <upstream_url> <header_name> <header_value> <port>
Prints "READY <port>" once listening, then serves until killed.
"""
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM_URL, HEADER_NAME, HEADER_VALUE, PORT = sys.argv[1:5]


class ProxyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        req = urllib.request.Request(UPSTREAM_URL, data=body, method="POST")
        req.add_header("Content-Type", self.headers.get("Content-Type", "application/json"))
        req.add_header(HEADER_NAME, HEADER_VALUE)
        try:
            with urllib.request.urlopen(req) as resp:
                self._respond(resp.status, resp.headers.get("Content-Type"), resp.read())
        except urllib.error.HTTPError as e:
            self._respond(e.code, "application/json", e.read())

    def _respond(self, status, content_type, payload):
        self.send_response(status)
        self.send_header("Content-Type", content_type or "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format, *args):  # keep CI logs quiet
        pass


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", int(PORT)), ProxyHandler)
    print(f"READY {PORT}", flush=True)
    server.serve_forever()
