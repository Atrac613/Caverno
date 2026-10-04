#!/usr/bin/env bash
set -euo pipefail

quiet=false
if [[ "${1:-}" == "--quiet-output" ]]; then quiet=true; shift; fi
if [[ "$#" != 0 ]]; then
  echo 'Usage: tool/run_farm_unattended_live_canary.sh [--quiet-output]' >&2
  exit 64
fi
: "${CAVERNO_LLM_BASE_URL:?Set the LLM API base URL}"
: "${CAVERNO_LLM_API_KEY:?Set the LLM API key}"
: "${CAVERNO_LLM_MODEL:?Set the exact loaded model ID}"
if [[ "${CAVERNO_LIVE_LLM_DATA_EXPORT_ACK:-}" != 1 ]]; then
  echo 'Set CAVERNO_LIVE_LLM_DATA_EXPORT_ACK=1 to authorize synthetic fixture export.' >&2
  exit 64
fi
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This canary requires the macOS native command containment route.' >&2
  exit 64
fi
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
mkdir -p "${REPORT_ROOT}"
RUN_DIR="$(mktemp -d "${REPORT_ROOT}/farm_unattended_live_canary.XXXXXX")"
LOG_PATH="${RUN_DIR}/flutter_test.jsonl"
mkdir -p "${RUN_DIR}/session_logs"
BUILD_COMMIT="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
BUILD_DIRTY=false
if ! git -C "${ROOT_DIR}" diff --quiet ||
  ! git -C "${ROOT_DIR}" diff --cached --quiet ||
  [[ -n "$(git -C "${ROOT_DIR}" ls-files --others --exclude-standard)" ]]; then
  BUILD_DIRTY=true
fi
printf 'Farm unattended canary: model=%s reports=%s\n' "${CAVERNO_LLM_MODEL}" "${RUN_DIR}"
cd "${ROOT_DIR}"
set +e
CAVERNO_FARM_UNATTENDED_LIVE_CANARY=1 \
CAVERNO_FARM_UNATTENDED_REPORT_DIR="${RUN_DIR}/fixtures" \
CAVERNO_SESSION_LOG_DIR="${RUN_DIR}/session_logs" \
fvm flutter test --no-pub --concurrency=1 \
  --dart-define="CAVERNO_BUILD_COMMIT=${BUILD_COMMIT}" \
  --dart-define="CAVERNO_BUILD_DIRTY=${BUILD_DIRTY}" \
  --dart-define="CAVERNO_BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  tool/canaries/farm_unattended_live_canary_test.dart -r json >"${LOG_PATH}" 2>&1
TEST_STATUS=$?
fvm dart run tool/live_llm_canary_summary.dart \
  --log "${LOG_PATH}" --out-dir "${RUN_DIR}" \
  --canary-name farm_unattended_live_canary --surface farm_unattended_worktree \
  --base-url "${CAVERNO_LLM_ORIGIN_BASE_URL:-${CAVERNO_LLM_BASE_URL}}" \
  --effective-base-url "${CAVERNO_LLM_BASE_URL}" \
  --relay-mode "${CAVERNO_LLM_RELAY_MODE:-direct}" --model "${CAVERNO_LLM_MODEL}" \
  --session-log-dir "${RUN_DIR}/session_logs" \
  --command 'tool/with_live_llm_loopback.sh -- tool/run_farm_unattended_live_canary.sh --quiet-output' \
  >"${RUN_DIR}/summary.log" 2>&1
SUMMARY_STATUS=$?
python3 - "${RUN_DIR}" >"${RUN_DIR}/evidence_gate.log" 2>&1 <<'PYGATE'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
summary_path = root / 'canary_summary.json'
summary = json.loads(summary_path.read_text())
gaps = []
try:
    evidence = json.loads((root / 'fixtures/evidence.json').read_text())
    task = evidence.get('task', {})
    probe = evidence.get('proposalProbe', {})
    positive = probe.get('positive', {})
    negative = probe.get('negative', {})
    task_ledger = [run for run in evidence.get('ledger', []) if run.get('projectId') == 'synthetic']
    checks = {
        'fixture passed and removed': evidence.get('schemaVersion') == 2 and evidence.get('passed') is True and evidence.get('scratchRemoved') is True,
        'one real HTTP dispatch': evidence.get('dispatchCount') == 1 and evidence.get('successfulHttpCalls', 0) > 0,
        'live proposal routing': evidence.get('proposalHttpCalls', 0) >= 2 and positive.get('taskId') == 'GR1' and positive.get('automatability') == 'unattended' and positive.get('error') is None and negative.get('taskId') in ('', 'HUMAN') and negative.get('automatability') == 'needsHuman' and negative.get('error') is None,
        'human gate': probe.get('negativeEnqueueCalls') == 0 and probe.get('negativeStartCalls') == 0 and probe.get('negativeLedger', {}).get('detail') == 'needsHuman',
        'native verification': task.get('status') == 'completed' and task.get('verifiedGreen') is True and 'UNATTENDED_ORACLE_OK' in task.get('verificationSummary', ''),
        'exact file evidence': [entry['path'] for entry in task.get('changedFiles', [])] == ['greeting.txt'] and task['changedFiles'][0]['content'] == 'hello from unattended\n' and task.get('changedFileEvidenceTruncated') is False,
        'unchanged source and worktree HEAD': evidence['initialHead'] == evidence['finalHead'] == evidence['worktreeHead'],
        'review branch only': task['branchName'].startswith('feature/') and evidence['worktreeStatus'] == 'M greeting.txt',
        'daily limit ledger': [run['outcome'] for run in task_ledger] == ['enqueued', 'skipped'] and task_ledger[-1]['detail'] == 'daily_limit',
    }
    gaps = [name for name, passed in checks.items() if not passed]
except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
    gaps = [f'Missing or malformed native evidence: {type(error).__name__}']
summary['farmUnattendedEvidence'] = {'passed': not gaps, 'gaps': gaps, 'scope': 'Injected idle environment and verified snapshots; live production proposals, real launcher, scheduler, worktree, LLM, contained verifier and persistence'}
if gaps:
    summary['result'] = 'failed'
    summary['mainReadiness'] = {'status': 'blocked', 'note': '; '.join(gaps)}
summary_path.write_text(json.dumps(summary, indent=2) + '\n')
print('Unattended Farm native evidence: ' + ('passed' if not gaps else '; '.join(gaps)))
sys.exit(1 if gaps else 0)
PYGATE
EVIDENCE_STATUS=$?
set -e
if ! "${quiet}"; then cat "${RUN_DIR}/summary.log" "${RUN_DIR}/evidence_gate.log"; fi
printf 'Farm unattended canary: tests=%s summary=%s evidence=%s artifact=%s/canary_summary.json\n' \
  "${TEST_STATUS}" "${SUMMARY_STATUS}" "${EVIDENCE_STATUS}" "${RUN_DIR}"
if [[ "${TEST_STATUS}" != 0 ]]; then exit "${TEST_STATUS}"; fi
if [[ "${SUMMARY_STATUS}" != 0 ]]; then exit "${SUMMARY_STATUS}"; fi
exit "${EVIDENCE_STATUS}"
