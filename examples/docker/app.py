import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self._respond(200, {"status": "ok"})
        elif self.path == "/":
            self._respond(200, {
                "message": os.getenv("MESSAGE", "Hello from myapp!"),
                "version": os.getenv("APP_VERSION", "1.0.0"),
                "hostname": os.uname().nodename,
            })
        else:
            self._respond(404, {"error": "not found"})

    def _respond(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}", flush=True)


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8080))
    server = HTTPServer(("", port), Handler)
    print(f"Listening on :{port}", flush=True)
    server.serve_forever()
