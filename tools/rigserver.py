"""Receives rig dumps POSTed from Roblox Studio (the same localhost trick Rojo uses)."""
import http.server, json, os, sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rig_dump.json')


class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n)
        with open(OUT, 'wb') as f:
            f.write(body)
        print('RECEIVED %d bytes -> %s' % (len(body), OUT), flush=True)
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'ok')

    def do_GET(self):
        # /poses hands the baked Blender swing back to Studio, so the animation
        # never has to be pasted through a command bar as a giant literal.
        if self.path.startswith('/poses'):
            p = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'swing_poses.json')
            body = open(p, 'rb').read()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            print('SERVED poses %d bytes' % len(body), flush=True)
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'rigserver up')

    def log_message(self, *a):
        pass


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    print('listening on %d' % port, flush=True)
    http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()
