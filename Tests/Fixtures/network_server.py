"""Loopback-only HTTP evidence fixture; no external network or credentials."""
import http.server
import pathlib
import sys
import os
import subprocess
import threading


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/redirect"):
            self.send_response(302)
            self.send_header("Location", "/echo")
            self.send_header("Content-Length", "0")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            return
        if self.path.startswith("/auth"):
            authorization = self.headers.get("Authorization")
            if not authorization:
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="same"')
                self.send_header("Content-Length", "0")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                return
            body = authorization.encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return
        body = (self.headers.get("Cookie", "") if self.path.startswith("/echo")
                else self.headers.get("X-Fixture-Owner", "missing")).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Content-Type", "text/plain")
        self.send_header("Cache-Control", "max-age=3600" if self.path.startswith("/cache") else "no-store")
        if self.path.startswith("/set"):
            self.send_header("Set-Cookie", "account=" + self.headers.get("X-Fixture-Owner", "missing") + "; Path=/")
        if self.path.startswith("/logout"):
            self.send_header("Set-Cookie", "account=; Max-Age=0; Path=/")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    if sys.argv[1] == "--run-tests":
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        environment = dict(os.environ, JIBUNKIT_NETWORK_TEST_PORT=str(server.server_port))
        print("Loopback HTTP fixture ready; starting swift test", flush=True)
        try:
            result = subprocess.run(["swift", "test"], env=environment)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        sys.exit(result.returncode)
    else:
        pathlib.Path(sys.argv[1]).write_text(str(server.server_port), encoding="ascii")
        server.serve_forever()
