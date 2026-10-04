#!/usr/bin/env bash
set -euo pipefail
quiet=false
if [[ "${1:-}" == --quiet-output ]]; then quiet=true; shift; fi
if [[ "$#" != 0 || "$(uname -s)" != Darwin ]]; then
  echo 'Usage (macOS): tool/run_farm_foreground_host_canary.sh [--quiet-output]' >&2
  exit 64
fi
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "${ROOT_DIR}/build/integration_test_reports"
RUN_DIR="$(mktemp -d "${ROOT_DIR}/build/integration_test_reports/farm_foreground_host.XXXXXX")"
printf 'Farm foreground host canary: artifacts=%s\n' "${RUN_DIR}"
cd "${ROOT_DIR}"
set +e
fvm flutter test --no-pub -d macos \
  integration_test/farm_foreground_host_canary_test.dart -r expanded \
  --dart-define="CAVERNO_FARM_HOST_REPORT_PATH=${RUN_DIR}/evidence.json" \
  >"${RUN_DIR}/flutter_test.log" 2>&1
TEST_STATUS=$?
python3 - "${RUN_DIR}" "${TEST_STATUS}" <<'PYGATE'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
gaps = []
try:
    e = json.loads((root / 'evidence.json').read_text())
    checks = {
        'test passed': sys.argv[2] == '0' and e.get('schemaVersion') == 1 and e.get('passed') is True,
        'native background and resume': e.get('nativeBackgroundTransitions') == [True, False],
        'before next timer': e.get('timerIntervalMs') == 5000 and 0 <= e.get('resumeToDrainMs', 5000) < 4000,
        'zero dispatch': e.get('enqueueCalls') == 0 and e.get('startCalls') == 0,
        'cancelled report': len(e.get('reports', [])) == 1 and 'cancelled before further dispatch' in e['reports'][0]['body'],
    }
    gaps = [name for name, passed in checks.items() if not passed]
except (OSError, ValueError, TypeError, KeyError) as error:
    gaps = [f'Missing or malformed evidence: {type(error).__name__}']
summary = {'result': 'failed' if gaps else 'passed', 'gaps': gaps,
           'scope': 'Native macOS lifecycle and timer; fixed pending proposal, AC and report sink; no LLM calls or real project dispatch'}
(root / 'canary_summary.json').write_text(json.dumps(summary, indent=2) + '\n')
sys.exit(1 if gaps else 0)
PYGATE
GATE_STATUS=$?
set -e
if ! "${quiet}"; then cat "${RUN_DIR}/flutter_test.log"; fi
printf 'Farm foreground host canary: tests=%s gate=%s artifact=%s/canary_summary.json\n' "${TEST_STATUS}" "${GATE_STATUS}" "${RUN_DIR}"
if [[ "${TEST_STATUS}" != 0 ]]; then exit "${TEST_STATUS}"; fi
exit "${GATE_STATUS}"
