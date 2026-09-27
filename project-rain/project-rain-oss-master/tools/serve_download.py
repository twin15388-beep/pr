#!/usr/bin/env python3
"""serves the built single-file script for download"""

import http.server
import pathlib
import socketserver

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = {
    "/project-rain.lua": ROOT / "project-rain.lua",
    "/project-rain.luau": ROOT / "project-rain.luau",
}
PORT = 8090

_main = FILES["/project-rain.lua"]
INDEX = f"""<!doctype html>
<html>
<head><meta charset="utf-8"><title>project rain (oss) - download</title></head>
<body style="background:#101014;color:#e8e8f0;font-family:monospace;padding:40px">
  <h2>project rain (oss) - single-file build</h2>
  <p>{_main.stat().st_size / 1024 / 1024:.2f} MiB &mdash; 273 modules, 16 assets &mdash; verified Luau-clean</p>
  <p><a style="color:#6699cc" href="/project-rain.lua" download>download project-rain.lua</a></p>
  <p><a style="color:#6699cc" href="/project-rain.luau" download>download project-rain.luau</a> (same bytes, .luau extension)</p>
</body>
</html>"""


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self.respond(200, INDEX.encode(), "text/html; charset=utf-8")
        else:
            path = self.path.split("?")[0]
            if path in FILES and FILES[path].exists():
                data = FILES[path].read_bytes()
                self.respond(200, data, "application/octet-stream", {
                    "Content-Disposition": f'attachment; filename="{FILES[path].name}"',
                })
            else:
                self.respond(404, b"nope", "text/plain")

    def respond(self, code, body, content_type, extra=None):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)


with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as server:
    print(f"serving at http://0.0.0.0:{PORT}/project-rain.lua (.luau twin available)")
    server.serve_forever()
