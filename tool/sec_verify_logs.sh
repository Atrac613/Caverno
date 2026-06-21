#!/usr/bin/env bash
# SEC1/SEC2 verification log helper.
#
# Surfaces the newest Caverno LLM session log(s) and today's approval-audit
# entries with their security-perimeter fields, so you do not have to hunt for
# files after a verification run.
#
# Usage:
#   tool/sec_verify_logs.sh [N] [AUDIT_DATE]
#     N           how many newest session logs to inspect (default 1)
#     AUDIT_DATE  approval-audit day file to read, YYYY-MM-DD (default today)
#
# Honors the same locations as the app: CAVERNO_SESSION_LOG_DIR and
# CAVERNO_APPROVAL_AUDIT_DIR overrides, else CAVERNO_HOME (default ~/.caverno).
#
# Portable: pure bash + python3, no Flutter/Dart/Caverno runtime — any coding
# agent (Codex, Claude Code, etc.) with shell access can run it.
set -euo pipefail

N="${1:-1}"
AUDIT_DATE="${2:-$(date +%F)}"
HOME_DIR="${CAVERNO_HOME:-$HOME/.caverno}"
SESSION_DIR="${CAVERNO_SESSION_LOG_DIR:-$HOME_DIR/session_logs}"
AUDIT_DIR="${CAVERNO_APPROVAL_AUDIT_DIR:-$HOME_DIR/approval_audit}"

python3 - "$SESSION_DIR" "$AUDIT_DIR" "$N" "$AUDIT_DATE" <<'PY'
import json, glob, os, sys, datetime

session_dir, audit_dir, n, audit_date = (
    sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
)

logs = sorted(
    glob.glob(f"{session_dir}/*/*.jsonl") + glob.glob(f"{session_dir}/*.jsonl"),
    key=os.path.getmtime,
    reverse=True,
)[:n]

print("== Newest session logs ==")
for f in logs:
    ts = datetime.datetime.fromtimestamp(os.path.getmtime(f)).strftime("%m-%d %H:%M")
    print(f"  {ts}  {f}")
if not logs:
    print("  (none found)")

print("\n== Auto-review packets (SEC1/SEC2 fields) ==")
found = False
for f in logs:
    for line in open(f):
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        for m in obj.get("request", {}).get("messages", []):
            c = m.get("content")
            if isinstance(c, str) and "auto_review_request" in c:
                try:
                    pkt = json.loads(c)
                except Exception:
                    continue
                act = pkt.get("action", {})
                cap = act.get("capability", {})
                resp = (obj.get("response") or {}).get("content", "") or ""
                print(
                    f"  [{os.path.basename(f)[:8]}] {act.get('toolName')}: "
                    f"cap={cap.get('class')}/{cap.get('risk')} "
                    f"untrustedInfluence={act.get('untrustedInfluence')} "
                    f"verdict~{resp[:60]!r}"
                )
                found = True
if not found:
    print("  (no auto-review packets — old build, or approval mode != auto-review)")

print("\n== Approval audit (SEC fields) ==")
af = f"{audit_dir}/{audit_date}.jsonl"
if os.path.exists(af):
    print(f"  file: {af}")
    for line in open(af):
        line = line.strip()
        if not line:
            continue
        e = json.loads(line)
        print(
            f"    {e.get('tool')}: "
            f"cap={e.get('capabilityClass')}/{e.get('capabilityRisk')} "
            f"untrusted={e.get('untrustedInfluence')} "
            f"outcome={e.get('outcome')} mode={e.get('mode')}"
        )
else:
    print(f"  (no audit file: {af})")
PY
