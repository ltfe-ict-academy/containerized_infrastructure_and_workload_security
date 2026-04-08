import json
import os
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, payload, status=200):
        data = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path not in ("/", "/health", "/info"):
            self._send_json({"error": "not found"}, status=404)
            return

        uid = os.getuid() if hasattr(os, "getuid") else "n/a"
        payload = {
            "service": "course-backend-demo",
            "status": "ok",
            "hostname": socket.gethostname(),
            "uid": uid,
            "cwd": os.getcwd(),
            "app_env": os.getenv("APP_ENV", "unset"),
        }
        self._send_json(payload)

    def log_message(self, format, *args):
        return


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8080), Handler)
    server.serve_forever()
