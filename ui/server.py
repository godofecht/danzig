#!/usr/bin/env python3
"""
DanzigGain Web Server
Serves the UI and processes audio files using danzig-gain-standalone
"""

import http.server
import socketserver
import os
import subprocess
import json
import sys
from pathlib import Path
from urllib.parse import urlparse, parse_qs

PORT = 8000
DANZIG_BIN = "./zig-out/bin/danzig-gain-standalone"
UI_DIR = "./ui"

class DanzigGainHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        """Handle GET requests - serve UI files"""
        if self.path == '/' or self.path == '':
            self.path = '/index.html'
        
        # Serve files from ui directory
        if self.path.startswith('/'):
            file_path = Path(UI_DIR) / self.path.lstrip('/')
            
            if file_path.exists() and file_path.is_file():
                self.send_response(200)
                if str(file_path).endswith('.html'):
                    self.send_header('Content-type', 'text/html')
                elif str(file_path).endswith('.css'):
                    self.send_header('Content-type', 'text/css')
                elif str(file_path).endswith('.js'):
                    self.send_header('Content-type', 'application/javascript')
                else:
                    self.send_header('Content-type', 'application/octet-stream')
                self.end_headers()
                
                with open(file_path, 'rb') as f:
                    self.wfile.write(f.read())
                return
        
        self.send_response(404)
        self.end_headers()
    
    def do_POST(self):
        """Handle POST requests - process audio"""
        if self.path == '/api/process':
            try:
                # Parse request
                content_length = int(self.headers.get('Content-Length', 0))
                body = self.rfile.read(content_length)
                
                # For now, return success
                response = {
                    'status': 'ok',
                    'message': 'Audio processing endpoint ready'
                }
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(json.dumps(response).encode())
                return
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'error': str(e)}).encode())
                return
        
        self.send_response(404)
        self.end_headers()
    
    def do_OPTIONS(self):
        """Handle CORS preflight"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

if __name__ == '__main__':
    os.chdir(Path(__file__).parent)
    
    print("\n🎵 DanzigGain Web Server")
    print("=" * 40)
    print(f"\n✓ Open http://localhost:{PORT} in your browser")
    print(f"✓ Press Ctrl+C to stop\n")
    
    try:
        with socketserver.TCPServer(("", PORT), DanzigGainHandler) as httpd:
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n\nServer stopped.")
        sys.exit(0)
    except OSError as e:
        print(f"\n❌ Error: {e}")
        print(f"   Port {PORT} may already be in use.")
        sys.exit(1)
