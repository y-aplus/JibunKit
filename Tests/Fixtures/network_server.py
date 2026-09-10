"""Loopback-only HTTP evidence fixture; no external network or credentials."""
import http.server
import pathlib
import sys


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = (self.headers.get("Cookie", "") if self.path.startswith("/echo")
                else self.headers.get("X-Fixture-Owner", "missing")).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Content-Type", "text/plain")
        self.send_header("Cache-Control", "max-age=3600" if self.path.startswith("/cache") else "no-store")
        if self.path.startswith("/set"):
            self.send_header("Set-Cookie", "account=" + self.headers.get("X-Fixture-Owner", "missing") + "; Path=/")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    pathlib.Path(sys.argv[1]).write_text(str(server.server_port), encoding="ascii")
    server.serve_forever()
