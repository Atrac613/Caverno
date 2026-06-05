"""Caverno embedded Python worker.

A long-lived loopback HTTP server that executes model-generated Python
snippets on demand. The Flutter host starts this once (via serious_python,
on a background thread) and drives it over 127.0.0.1 with ``POST /run``.

Design notes:
- Pure standard library only, so the same bundle runs on every platform the
  serious_python plugin supports (iOS/Android/macOS/Windows/Linux) without any
  native wheels.
- The host picks the port and a shared secret, passed via the ``CAVERNO_PORT``
  and ``CAVERNO_TOKEN`` environment variables. Every request must present the
  secret in the ``X-Caverno-Token`` header; this keeps other local processes
  from driving the interpreter even though it binds loopback.
- Jobs are serialized (single-threaded server). Each job runs in a fresh
  namespace with stdout/stderr captured and an injected ``caverno`` helper that
  exposes the attachments the user sent with the message.
"""

import io
import json
import os
import sys
import threading
import traceback
import types
from http.server import BaseHTTPRequestHandler, HTTPServer

# Upper bound on characters returned per stream. The host truncates further
# before forwarding to the model; this only guards against unbounded buffers.
_MAX_STREAM_CHARS = 200_000


class _StreamRouter:
    """Thread-aware stdout/stderr replacement.

    Installed once as ``sys.stdout`` / ``sys.stderr``. When a job registers a
    capture buffer for its thread, that thread's writes go to the buffer; every
    other thread (including a timed-out job whose thread keeps running) writes
    to the real stream. This captures a job's output without ever mutating
    global state mid-flight, so a hung job can neither swallow the worker's own
    output nor a later job's capture.
    """

    def __init__(self, real):
        self._real = real
        self._local = threading.local()

    def set_target(self, buffer):
        self._local.buffer = buffer

    def clear_target(self):
        self._local.buffer = None

    def _target(self):
        return getattr(self._local, "buffer", None)

    def write(self, data):
        target = self._target()
        if target is not None:
            return target.write(data)
        return self._real.write(data)

    def flush(self):
        target = self._target()
        if target is not None:
            return target.flush()
        return self._real.flush()

    def isatty(self):
        return False

    def fileno(self):
        return self._real.fileno()

    @property
    def encoding(self):
        return getattr(self._real, "encoding", "utf-8")


_stdout_router = _StreamRouter(sys.stdout)
_stderr_router = _StreamRouter(sys.stderr)
sys.stdout = _stdout_router
sys.stderr = _stderr_router


def _truncate(text):
    if len(text) <= _MAX_STREAM_CHARS:
        return text
    return text[:_MAX_STREAM_CHARS]


def _coerce_output(value):
    """Return a JSON-serializable view of an explicit ``caverno.set_output``."""
    if value is None:
        return None
    try:
        json.dumps(value)
        return value
    except (TypeError, ValueError):
        return repr(value)


def _build_caverno_module(inputs, job_cwd):
    """Create a per-job ``caverno`` helper exposing staged attachments.

    Generated code can read the files the user attached without hard-coding
    paths, e.g. ``caverno.inputs[0].read_bytes()``, and may hand a structured
    result back to the host via ``caverno.set_output(value)``.
    """
    module = types.ModuleType("caverno")

    class _Input:
        def __init__(self, name, path, mime):
            self.name = name
            self.path = path
            self.mime = mime

        def read_bytes(self):
            with open(self.path, "rb") as handle:
                return handle.read()

        def read_text(self, encoding="utf-8"):
            with open(self.path, "r", encoding=encoding) as handle:
                return handle.read()

        def __repr__(self):
            return "<caverno.Input name={!r} path={!r}>".format(
                self.name, self.path
            )

    module.inputs = [
        _Input(item.get("name", ""), item.get("path", ""), item.get("mime"))
        for item in inputs
    ]
    module.cwd = job_cwd
    module._output = None
    module._output_set = False

    def set_output(value):
        module._output = value
        module._output_set = True

    module.set_output = set_output
    return module


def _execute(code, inputs, job_cwd, timeout):
    """Run ``code`` in an isolated namespace and capture its effects.

    The script runs on a daemon thread so the request can return after
    ``timeout`` seconds even if the script hangs. A timed-out script keeps
    running in the background until it finishes; because jobs are serialized
    this is acceptable for a chat tool and is reported via ``timed_out``.
    """
    stdout_buffer = io.StringIO()
    stderr_buffer = io.StringIO()
    caverno_module = _build_caverno_module(inputs, job_cwd)
    box = {"error": None, "traceback": None, "output": None}

    def target():
        previous_cwd = None
        try:
            if job_cwd and os.path.isdir(job_cwd):
                previous_cwd = os.getcwd()
                os.chdir(job_cwd)
            # Expose `caverno` as both a global and an importable module so the
            # model can use either `caverno.inputs` or `from caverno import inputs`.
            sys.modules["caverno"] = caverno_module
            script_globals = {
                "__name__": "__caverno__",
                "__builtins__": __builtins__,
                "caverno": caverno_module,
            }
            _stdout_router.set_target(stdout_buffer)
            _stderr_router.set_target(stderr_buffer)
            exec(compile(code, "<caverno-script>", "exec"), script_globals)
            if caverno_module._output_set:
                box["output"] = _coerce_output(caverno_module._output)
        except BaseException as exc:  # report any failure back to the host
            box["error"] = "{}: {}".format(type(exc).__name__, exc)
            box["traceback"] = traceback.format_exc()
        finally:
            _stdout_router.clear_target()
            _stderr_router.clear_target()
            if previous_cwd is not None:
                try:
                    os.chdir(previous_cwd)
                except OSError:
                    pass

    worker = threading.Thread(target=target, daemon=True)
    worker.start()
    worker.join(timeout)
    timed_out = worker.is_alive()

    return {
        "stdout": _truncate(stdout_buffer.getvalue()),
        "stderr": _truncate(stderr_buffer.getvalue()),
        "result": box["output"],
        "error": box["error"],
        "traceback": box["traceback"],
        "timed_out": timed_out,
    }


class _Handler(BaseHTTPRequestHandler):
    # Silence the default stderr request logging.
    def log_message(self, *args):  # noqa: N802 - stdlib signature
        return

    def _token(self):
        return os.environ.get("CAVERNO_TOKEN", "")

    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        expected = self._token()
        if not expected:
            return True
        return self.headers.get("X-Caverno-Token", "") == expected

    def do_GET(self):  # noqa: N802 - stdlib signature
        if not self._authorized():
            self._send_json(403, {"error": "forbidden"})
            return
        if self.path == "/health":
            self._send_json(200, {"status": "ok", "python": sys.version})
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802 - stdlib signature
        if not self._authorized():
            self._send_json(403, {"error": "forbidden"})
            return
        if self.path != "/run":
            self._send_json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length) if length > 0 else b""
            request = json.loads(raw.decode("utf-8")) if raw else {}
            code = request.get("code", "")
            inputs = request.get("inputs", []) or []
            job_cwd = request.get("cwd", "") or ""
            timeout = request.get("timeout", 60)
            try:
                timeout = float(timeout)
            except (TypeError, ValueError):
                timeout = 60.0
            result = _execute(code, inputs, job_cwd, timeout)
            self._send_json(200, result)
        except Exception as exc:  # never let the worker die on a bad request
            self._send_json(
                200,
                {
                    "stdout": "",
                    "stderr": "",
                    "result": None,
                    "error": "worker_request_error: {}".format(exc),
                    "traceback": traceback.format_exc(),
                    "timed_out": False,
                },
            )


def main():
    port = int(os.environ.get("CAVERNO_PORT", "0"))
    server = HTTPServer(("127.0.0.1", port), _Handler)
    # Block forever; serious_python runs this on its own background thread.
    server.serve_forever()


if __name__ == "__main__":
    main()
