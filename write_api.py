#!/usr/bin/env python3
"""
vault への書き込みを受け付ける最小限のHTTP API。
POST /write  { "path": "相対パス.md", "content": "本文", "mode": "overwrite"|"append" }
Header: X-Write-Secret: <WRITE_API_SECRET>
"""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VAULT_PATH = os.environ.get("VAULT_PATH", "/vault")
SECRET = os.environ["WRITE_API_SECRET"]
PORT = int(os.environ.get("WRITE_API_PORT", "8090"))


def safe_join(base, rel_path):
    # ディレクトリトラバーサル対策: vault の外に出られないようにする
    rel_path = rel_path.lstrip("/")
    full = os.path.normpath(os.path.join(base, rel_path))
    if not full.startswith(os.path.normpath(base) + os.sep) and full != os.path.normpath(base):
        raise ValueError("invalid path")
    return full


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.end_headers()
        self.wfile.write(json.dumps(body, ensure_ascii=False).encode("utf-8"))

    def do_POST(self):
        if self.path != "/write":
            return self._send(404, {"error": "not found"})

        if self.headers.get("X-Write-Secret") != SECRET:
            return self._send(401, {"error": "unauthorized"})

        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
            rel_path = payload["path"]
            content = payload["content"]
            mode = payload.get("mode", "overwrite")  # overwrite | append

            full_path = safe_join(VAULT_PATH, rel_path)
            os.makedirs(os.path.dirname(full_path), exist_ok=True)

            if mode == "append" and os.path.exists(full_path):
                with open(full_path, "a", encoding="utf-8") as f:
                    f.write("\n" + content)
            else:
                with open(full_path, "w", encoding="utf-8") as f:
                    f.write(content)

            return self._send(200, {"ok": True, "path": rel_path, "mode": mode})
        except Exception as e:
            return self._send(400, {"error": str(e)})

    def log_message(self, fmt, *args):
        print(f"[write_api] {self.address_string()} - {fmt % args}")


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[write_api] listening on :{PORT}, vault={VAULT_PATH}")
    server.serve_forever()