"""Lokale Vorschau von build/web wie Firebase Hosting (unbekannte Pfade → index.html,
damit Links wie /k/CODE und /s/TOKEN funktionieren).

    python3 tool/dev/serve_web.py [port]   # Standard 18765
"""
import http.server
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build", "web")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18765


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def send_head(self):
        if not os.path.exists(self.translate_path(self.path)):
            self.path = "/index.html"
        return super().send_head()

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
