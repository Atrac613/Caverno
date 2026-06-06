#!/usr/bin/env python3
"""Regression tests for the embedded Python worker (run with system python3):

    python3 test/python/worker_test.py

Flutter is not required. Exercises job execution, the injected ``caverno``
attachment helper, structured ``set_output``, error/timeout reporting, the
loopback HTTP server + token auth, and the vendored piexif EXIF round-trip.

Note: the system python3 may differ from the bundled 3.12.9, but this covers
the worker's pure-Python/stdlib logic. The on-device embedded interpreter is
verified separately by integration_test/python_runtime_test.dart.
"""
import base64
import json
import os
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

WORKER_DIR = os.path.abspath(
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "..",
        "..",
        "lib",
        "core",
        "services",
        "script_runtime",
        "worker",
    )
)
sys.path.insert(0, WORKER_DIR)
import main  # noqa: E402 - triggers the __pypackages__ bootstrap

_failures = []


def check(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    if not cond:
        _failures.append(name)


# A minimal valid 1x1 JPEG (no EXIF); piexif inserts EXIF into it below.
_TINY_JPEG_B64 = (
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAAA//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AfwD/2Q=="
)


def main_tests():
    # 1. stdout capture
    r = main._execute("print('hi')", [], "", 10)
    check("stdout capture", r["stdout"] == "hi\n" and r["error"] is None)

    # 2. structured set_output
    r = main._execute("caverno.set_output({'a': 1, 'b': [2, 3]})", [], "", 10)
    check("set_output json", r["result"] == {"a": 1, "b": [2, 3]})

    # 3. staged input via caverno.inputs
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "note.txt")
        with open(path, "w") as fh:
            fh.write("metadata-here")
        code = (
            "print(caverno.inputs[0].read_text()); "
            "print(caverno.inputs[0].name)"
        )
        r = main._execute(code, [{"name": "note.txt", "path": path}], d, 10)
        check("inputs read_text", r["stdout"] == "metadata-here\nnote.txt\n")

    # 4. `import caverno` form
    r = main._execute("from caverno import inputs; print(len(inputs))", [], "", 10)
    check("import caverno", r["stdout"] == "0\n")

    # 5. error + traceback
    r = main._execute("raise ValueError('boom')", [], "", 10)
    check(
        "error reported",
        r["error"] == "ValueError: boom" and "Traceback" in (r["traceback"] or ""),
    )

    # 6. timeout (sleep-bound hang releases the GIL, like real I/O waits)
    r = main._execute("import time\ntime.sleep(5)", [], "", 1)
    check("timeout flagged", r["timed_out"] is True)

    # 7. vendored piexif EXIF round-trip on a staged image
    with tempfile.TemporaryDirectory() as d:
        img = os.path.join(d, "img.jpg")
        with open(img, "wb") as fh:
            fh.write(base64.b64decode(_TINY_JPEG_B64))
        code = (
            "import piexif, caverno\n"
            "src = caverno.inputs[0].path\n"
            "piexif.insert(piexif.dump("
            "{'0th': {piexif.ImageIFD.Make: b'TestCam'}}), src)\n"
            "print(piexif.load(src)['0th'][piexif.ImageIFD.Make].decode())\n"
        )
        r = main._execute(code, [{"name": "img.jpg", "path": img}], d, 20)
        check(
            "piexif round-trip",
            r["error"] is None and r["stdout"].strip() == "TestCam",
        )


def http_tests():
    port = 8771
    os.environ["CAVERNO_PORT"] = str(port)
    os.environ["CAVERNO_TOKEN"] = "secret123"
    server = main.HTTPServer(("127.0.0.1", port), main._Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    time.sleep(0.3)

    def http(method, path, body=None, token="secret123"):
        req = urllib.request.Request(
            "http://127.0.0.1:%d%s" % (port, path), method=method
        )
        if token is not None:
            req.add_header("X-Caverno-Token", token)
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, data=data) as resp:
            return resp.status, json.loads(resp.read().decode())

    status, payload = http("GET", "/health")
    check("health ok", status == 200 and payload["status"] == "ok")

    status, payload = http("POST", "/run", {"code": "print(6*7)"})
    check("http run", payload["stdout"] == "42\n")

    try:
        status, _ = http("GET", "/health", token="wrong")
        forbidden = status == 403
    except urllib.error.HTTPError as exc:
        forbidden = exc.code == 403
    check("token rejected", forbidden)

    server.shutdown()


def main_entry():
    main_tests()
    http_tests()
    print()
    print("FAILURES:", _failures if _failures else "none")
    return 1 if _failures else 0


if __name__ == "__main__":
    sys.exit(main_entry())
