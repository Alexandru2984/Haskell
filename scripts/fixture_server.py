#!/usr/bin/env python3
"""Synthetic API for isolated integration/browser checks; loopback only."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import time

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/slow": time.sleep(1.2)
        self.send_response(500 if self.path == '/fail' else 200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({'status':'error' if self.path == '/fail' else 'ok', 'version':'1.4.0'}).encode())
    def log_message(self, *_args):
        pass

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', int(os.environ.get('FIXTURE_PORT', '19061'))), Handler).serve_forever()
