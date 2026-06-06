#!/usr/bin/env python3
"""Package the embedded Python worker into the Flutter asset zip.

serious_python's ``SeriousPython.run()`` unpacks the asset and runs ``main.py``
at its root; pure-Python dependencies vendored under ``__pypackages__/`` are put
on ``sys.path`` by ``main.py``. Run this after editing the worker or its
vendored dependencies:

    python3 tool/pack_python_worker.py

The archive is deterministic (sorted entries, fixed timestamps) so re-packaging
an unchanged worker yields an identical zip.
"""

import os
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKER = os.path.join(
    ROOT, "lib", "core", "services", "script_runtime", "worker"
)
OUTPUT = os.path.join(ROOT, "assets", "python", "app.zip")

_EXCLUDE_DIRS = {"__pycache__"}
_EXCLUDE_SUFFIXES = (".pyc", ".pyo")


def _collect(worker_dir):
    entries = []
    for dirpath, dirnames, filenames in os.walk(worker_dir):
        dirnames[:] = sorted(d for d in dirnames if d not in _EXCLUDE_DIRS)
        for name in sorted(filenames):
            if name.endswith(_EXCLUDE_SUFFIXES):
                continue
            full = os.path.join(dirpath, name)
            arc = os.path.relpath(full, worker_dir)
            entries.append((full, arc))
    return entries


def main():
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    entries = _collect(WORKER)
    with zipfile.ZipFile(OUTPUT, "w", zipfile.ZIP_DEFLATED) as archive:
        for full, arc in entries:
            info = zipfile.ZipInfo(arc, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(full, "rb") as handle:
                archive.writestr(info, handle.read())
    print("Wrote {} ({} files)".format(OUTPUT, len(entries)))
    for _, arc in entries:
        print("  ", arc)


if __name__ == "__main__":
    main()
