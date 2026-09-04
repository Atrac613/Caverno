#!/usr/bin/env python3
"""Emit bounded heartbeats while a repository-owned command is running."""

from __future__ import annotations

import os
import signal
import sys
import time


def _stop(_signal: int, _frame: object) -> None:
    raise SystemExit(0)


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print("heartbeat requires PID, interval, label, and log path", file=sys.stderr)
        return 64
    pid = int(argv[0])
    interval = float(argv[1])
    label = argv[2]
    log_path = argv[3]
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    while True:
        time.sleep(interval)
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return 0
        print(f"Still running {label}", flush=True)
        print(f"  Full log: {log_path}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
