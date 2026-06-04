#!/usr/bin/env python3
"""WO log+file server.

One server on :8080 that BOTH:
  - GET  -> serves files from the Downloads dir (so the Deck's `curl ... spike_marionette.ws`
            and the .asi pulls keep working exactly as before), and
  - POST/PUT /<name> -> writes the request body to Downloads/<name>, so the Deck can push its
            scriptslog here and Claude can read it on the PC (no more squinting at the in-game HUD).

Deck pushes with, e.g.:
  curl -s --data-binary @- http://192.168.0.49:8080/deck_scriptslog.txt
The latest upload is always at  C:\\Users\\kirco\\Downloads\\deck_scriptslog.txt
"""
import http.server
import socketserver
import os
import datetime

DOWNLOADS = r"C:\Users\kirco\Downloads"
PORT = 8080


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DOWNLOADS, **kwargs)

    def _write_upload(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length) if length else b""
        # last path segment, sanitized to a bare filename (no traversal)
        name = os.path.basename(self.path.strip("/")) or "upload.txt"
        if not name.endswith((".txt", ".log")):
            name = name + ".txt"
        path = os.path.join(DOWNLOADS, name)
        try:
            with open(path, "wb") as f:
                f.write(body)
            stamp = datetime.datetime.now().strftime("%H:%M:%S")
            print(f"[{stamp}] upload {name}  ({len(body)} bytes)")
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"OK")
        except Exception as e:  # noqa
            msg = str(e).encode()
            self.send_response(500)
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)

    def do_POST(self):
        self._write_upload()

    def do_PUT(self):
        self._write_upload()

    def log_message(self, fmt, *args):
        # keep GET noise quiet; uploads are printed in _write_upload
        pass


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    os.makedirs(DOWNLOADS, exist_ok=True)
    with Server(("0.0.0.0", PORT), Handler) as httpd:
        print(f"WO log+file server on 0.0.0.0:{PORT}  serving {DOWNLOADS}")
        print("  GET  -> file pull (Deck curl)   POST/PUT /<name> -> save upload")
        httpd.serve_forever()
