#!/usr/bin/env python3
"""NotiEcho 프리뷰 서버: 정적 파일 + 구글 TTS 프록시 (/tts?q=word)"""
import http.server
import socketserver
import urllib.request
import urllib.parse
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 5060


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('X-Frame-Options', 'ALLOWALL')
        self.send_header('Content-Security-Policy', 'frame-ancestors *')
        super().end_headers()

    def do_GET(self):
        if self.path.startswith('/tts'):
            self.handle_tts()
        else:
            super().do_GET()

    def handle_tts(self):
        try:
            qs = urllib.parse.urlparse(self.path).query
            params = urllib.parse.parse_qs(qs)
            text = (params.get('q') or [''])[0].strip()
            slow = (params.get('slow') or ['0'])[0] == '1'
            if not text or len(text) > 200:
                self.send_error(400, 'bad query')
                return
            g_params = {
                'ie': 'UTF-8',
                'tl': 'en',
                'client': 'tw-ob',
                'q': text,
            }
            if slow:
                g_params['ttsspeed'] = '0.3'
            url = 'https://translate.google.com/translate_tts?' + \
                urllib.parse.urlencode(g_params)
            req = urllib.request.Request(url, headers={
                'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)'
            })
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = resp.read()
            self.send_response(200)
            self.send_header('Content-Type', 'audio/mpeg')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'public, max-age=86400')
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            try:
                self.send_error(502, f'tts proxy error: {e}')
            except Exception:
                pass

    def log_message(self, *args):
        pass


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('0.0.0.0', PORT), Handler) as httpd:
    print(f'Serving on port {PORT}')
    httpd.serve_forever()
