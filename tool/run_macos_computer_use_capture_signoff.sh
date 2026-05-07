#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_PATH="${CAVERNO_MACOS_COMPUTER_USE_CAPTURE_SIGNOFF_REPORT_PATH:-/tmp/caverno-macos-computer-use-capture-signoff.json}"
OPEN_SETTINGS=0
REVEAL_HELPER=0
REQUIRE_CAPTURE=0
REPLACE_HELPER=0
VERBOSE_PROBE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open-settings)
      OPEN_SETTINGS=1
      shift
      ;;
    --reveal-helper)
      REVEAL_HELPER=1
      shift
      ;;
    --require-capture|--require-capture-ready)
      REQUIRE_CAPTURE=1
      shift
      ;;
    --replace-helper)
      REPLACE_HELPER=1
      shift
      ;;
    --verbose-probe)
      VERBOSE_PROBE=1
      shift
      ;;
    --report)
      REPORT_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

cd "${ROOT_DIR}"

PROBE_ARGS=(
  --require-helper-path-match
  --report "${REPORT_PATH}"
)

if [[ "${REPLACE_HELPER}" == "1" ]]; then
  PROBE_ARGS+=(--replace-helper)
fi

if [[ "${REQUIRE_CAPTURE}" == "1" ]]; then
  PROBE_ARGS+=(--require-capture)
fi

PROBE_OUTPUT="$(mktemp -t caverno-capture-signoff-probe.XXXXXX)"
trap 'rm -f "${PROBE_OUTPUT}"' EXIT

set +e
if [[ "${VERBOSE_PROBE}" == "1" ]]; then
  bash tool/run_macos_computer_use_existing_helper_probe.sh "${PROBE_ARGS[@]}"
  PROBE_EXIT=$?
else
  bash tool/run_macos_computer_use_existing_helper_probe.sh "${PROBE_ARGS[@]}" >"${PROBE_OUTPUT}"
  PROBE_EXIT=$?
fi
set -e

if [[ ! -f "${REPORT_PATH}" ]]; then
  echo "Probe did not write report: ${REPORT_PATH}" >&2
  if [[ "${VERBOSE_PROBE}" != "1" ]]; then
    cat "${PROBE_OUTPUT}" >&2
  fi
  exit "${PROBE_EXIT}"
fi

SUMMARY_JSON="$(/usr/bin/python3 - "${REPORT_PATH}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    report = json.load(handle)

helper = report.get("helper") or {}
permissions = report.get("permissionSummary") or {}
summary = {
    "ok": bool(report.get("ok")),
    "coreOk": bool(report.get("coreOk")),
    "captureReady": bool(report.get("captureReady")),
    "inputReady": bool(report.get("inputReady")),
    "audioResolved": bool(report.get("audioResolved")),
    "helperPathMatchesExpected": bool(report.get("helperPathMatchesExpected")),
    "helperPathMismatchInvalidatesSignoff": bool(report.get("helperPathMismatchInvalidatesSignoff")),
    "screenCaptureGranted": bool(permissions.get("screenCaptureGranted")),
    "accessibilityGranted": bool(permissions.get("accessibilityGranted")),
    "systemAudioRecordingSupported": bool(permissions.get("systemAudioRecordingSupported")),
    "expectedHelperPath": helper.get("expectedPath") or "",
    "runningHelperPath": helper.get("runningPath") or "",
    "failedRequiredChecks": report.get("failedRequiredChecks") or [],
    "nextAction": report.get("nextAction") or "",
    "reportPath": sys.argv[1],
}
print(json.dumps(summary, ensure_ascii=True))
PY
)"

EXPECTED_HELPER_PATH="$(/usr/bin/python3 - "${SUMMARY_JSON}" <<'PY'
import json
import sys

print(json.loads(sys.argv[1]).get("expectedHelperPath", ""))
PY
)"

echo
echo "Capture sign-off summary:"
/usr/bin/python3 - "${SUMMARY_JSON}" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
print(f"  Core ready: {summary['coreOk']}")
print(f"  Helper path matches expected: {summary['helperPathMatchesExpected']}")
print(f"  Accessibility granted: {summary['accessibilityGranted']}")
print(f"  Screen Recording granted: {summary['screenCaptureGranted']}")
print(f"  System audio supported: {summary['systemAudioRecordingSupported']}")
print(f"  Capture ready: {summary['captureReady']}")
print(f"  Input ready: {summary['inputReady']}")
print(f"  Audio resolved: {summary['audioResolved']}")
print(f"  Expected helper path: {summary['expectedHelperPath']}")
print(f"  Running helper path: {summary['runningHelperPath']}")
print(f"  Report: {summary['reportPath']}")
if summary["failedRequiredChecks"]:
    print(f"  Failed required checks: {', '.join(summary['failedRequiredChecks'])}")
if summary["helperPathMismatchInvalidatesSignoff"]:
    print("")
    print("Sign-off warning:")
    print("  The running helper is not the embedded helper. Any passing capture,")
    print("  input, or audio result belongs to the standalone helper and is not")
    print("  valid for embedded-helper sign-off.")
if summary["nextAction"]:
    print("")
    print("Next action:")
    print(f"  {summary['nextAction']}")
PY

if [[ "${REVEAL_HELPER}" == "1" && -n "${EXPECTED_HELPER_PATH}" ]]; then
  /usr/bin/open -R "${EXPECTED_HELPER_PATH}"
fi

if [[ "${OPEN_SETTINGS}" == "1" ]]; then
  /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
fi

exit "${PROBE_EXIT}"
