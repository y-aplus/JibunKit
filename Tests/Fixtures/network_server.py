"""Loopback-only HTTP evidence fixture; no external network or credentials."""
import http.server
import pathlib
import sys
import os
import subprocess
import threading

gates = {}
gates_lock = threading.Lock()


def gate(token):
    with gates_lock:
        return gates.setdefault(token, (threading.Event(), threading.Event()))


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Event-driven lifetime tests: the response is held until another request
        # releases it. A deadline prevents a failed test from hanging the fixture.
        if self.path.startswith(("/hold/", "/await-start/", "/release/")):
            operation, token = self.path.strip("/").split("/", 1)
            started, released = gate(token)
            if operation == "hold":
                started.set()
                ready = released.wait(timeout=20)
            elif operation == "await-start":
                ready = started.wait(timeout=20)
            else:
                released.set()
                ready = True
            self.send_response(200 if ready else 504)
            self.send_header("Content-Length", "0")
            self.send_header("Cache-Control", "no-store")
            if operation == "hold" and ready:
                self.send_header("Set-Cookie", "account=late-response; Path=/; Max-Age=3600")
            try:
                self.end_headers()
            except (BrokenPipeError, ConnectionResetError):
                # The cancellation test intentionally disconnects before release.
                pass
            return
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
            lifetime = "; Max-Age=3600" if self.path.startswith("/set-persistent") else ""
            self.send_header("Set-Cookie", "account=" + self.headers.get("X-Fixture-Owner", "missing") + "; Path=/" + lifetime)
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
