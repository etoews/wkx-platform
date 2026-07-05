"""hello: the M3 smoke-test app and ancestor of the reference project (M8).

Responds 200 to every GET with MESSAGE from the environment, so M5 can
change the page by setting /wkx/hello/<env>/MESSAGE and redeploying.
"""
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MESSAGE = os.environ.get("MESSAGE", "hello, wing kong exchange")
PORT = 8000


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"<!doctype html>\n<title>hello</title>\n<h1>{MESSAGE}</h1>\n".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # BaseHTTPRequestHandler logs to stderr; keep that, docker captures it.
        super().log_message(fmt, *args)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
