"""
A live command channel into a running Blender.

WHY THIS EXISTS
---------------
Every animation iteration used to cost a cold `blender --background` run:
~20 seconds to rebuild the rig, re-key every clip and re-render, just to ask
one question. That made exploration expensive, so it did not happen - poses
got tuned by guessing rather than by looking.

This starts a small HTTP server INSIDE Blender, so a live session can be
driven and questioned in milliseconds: evaluate an expression, nudge a pose,
re-render from a new angle, measure a distance. The rig stays loaded between
calls, which is the whole point.

    POST /exec    body = python source        -> {ok, stdout, result}
    GET  /ping                                 -> {ok, blend, frame}
    GET  /shot?path=...&cam=x,y,z&at=x,y,z     -> renders, returns path

THREADING, WHICH IS THE ONLY SUBTLE PART
----------------------------------------
bpy is not thread-safe: touching it from the HTTP thread crashes Blender
outright. Requests are therefore queued and drained by a bpy.app.timers
callback on the MAIN thread; the HTTP thread blocks on an Event until the
result comes back. Everything Blender-side runs where Blender expects.

SCOPE
-----
Binds to 127.0.0.1 only and executes arbitrary Python, exactly like Blender's
own scripting console. It is a local development tool - do not expose the port.

    blender file.blend --python tools/blender_server.py
"""
import bpy
import io
import json
import queue
import threading
import traceback
import contextlib
import http.server

PORT = 8799

_requests: "queue.Queue" = queue.Queue()


class _Job:
    __slots__ = ("code", "kind", "args", "done", "out")

    def __init__(self, kind, code=None, args=None):
        self.kind = kind
        self.code = code
        self.args = args or {}
        self.done = threading.Event()
        self.out = None


def _run_exec(code):
    """Exec in a persistent namespace so state carries between calls."""
    ns = _run_exec.__dict__.setdefault("ns", {"bpy": bpy})
    buf = io.StringIO()
    result = None
    try:
        with contextlib.redirect_stdout(buf):
            try:
                # Expression first, so `/exec` can be used to ask questions.
                result = eval(compile(code, "<exec>", "eval"), ns)
            except SyntaxError:
                exec(compile(code, "<exec>", "exec"), ns)
        return {"ok": True, "stdout": buf.getvalue(), "result": repr(result) if result is not None else None}
    except Exception:
        return {"ok": False, "stdout": buf.getvalue(), "error": traceback.format_exc()}


def _run_shot(args):
    from mathutils import Matrix, Vector

    scene = bpy.context.scene
    path = args.get("path") or "//shot.png"

    cam = scene.camera
    if cam and args.get("cam"):
        loc = Vector([float(v) for v in args["cam"].split(",")])
        at = Vector([float(v) for v in (args.get("at") or "0,0,0").split(",")])
        up = Vector((0, 1, 0)) if args.get("yup") else Vector((0, 0, 1))
        f = (at - loc).normalized()
        r = f.cross(up).normalized()
        u = r.cross(f)
        cam.matrix_world = Matrix(((r.x, u.x, -f.x, loc.x),
                                   (r.y, u.y, -f.y, loc.y),
                                   (r.z, u.z, -f.z, loc.z),
                                   (0, 0, 0, 1)))
    if args.get("frame"):
        scene.frame_set(int(args["frame"]))

    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return {"ok": True, "path": bpy.path.abspath(path), "frame": scene.frame_current}


def _drain():
    """Main-thread pump. Registered with bpy.app.timers."""
    while True:
        try:
            job = _requests.get_nowait()
        except queue.Empty:
            break
        try:
            if job.kind == "exec":
                job.out = _run_exec(job.code)
            elif job.kind == "shot":
                job.out = _run_shot(job.args)
            else:
                job.out = {"ok": True, "blend": bpy.data.filepath,
                           "frame": bpy.context.scene.frame_current}
        except Exception:
            job.out = {"ok": False, "error": traceback.format_exc()}
        finally:
            job.done.set()
    return 0.05


def _submit(kind, code=None, args=None, timeout=120):
    job = _Job(kind, code, args)
    _requests.put(job)
    if not job.done.wait(timeout):
        return {"ok": False, "error": "timed out waiting for Blender's main thread"}
    return job.out


class Handler(http.server.BaseHTTPRequestHandler):
    def _reply(self, payload, code=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        code = self.rfile.read(n).decode("utf-8")
        self._reply(_submit("exec", code=code))

    def do_GET(self):
        path, _, qs = self.path.partition("?")
        args = {}
        for pair in qs.split("&"):
            if "=" in pair:
                k, _, v = pair.partition("=")
                args[k] = __import__("urllib.parse", fromlist=["unquote"]).unquote(v)
        if path.startswith("/shot"):
            self._reply(_submit("shot", args=args))
        else:
            self._reply(_submit("ping"))

    def log_message(self, *a):
        pass


def start():
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    bpy.app.timers.register(_drain, persistent=True)
    print("BLENDER COMMAND SERVER on 127.0.0.1:%d" % PORT)


start()
