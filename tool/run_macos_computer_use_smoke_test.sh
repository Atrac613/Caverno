#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DEVICE="${CAVERNO_MACOS_COMPUTER_USE_DEVICE:-macos}"
REPORTER="${CAVERNO_MACOS_COMPUTER_USE_REPORTER:-compact}"
BUILD_MODE="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_BUILD_MODE:-debug}"
STRICT="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT:-0}"
STRICT_XPC="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT_XPC:-0}"
M4_SIGNOFF="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_M4_SIGNOFF:-0}"
UNSAFE_ARMED="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_ARMED:-0}"
UNSAFE_CLICK_ARMED="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_CLICK_ARMED:-0}"
UNSAFE_TEXT_ARMED="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_TEXT_ARMED:-0}"
REQUIRE_CAPTURE_READY="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_CAPTURE_READY:-0}"
REQUIRE_INPUT_READY="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_INPUT_READY:-0}"
REQUIRE_AUDIO_RESOLVED="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_AUDIO_RESOLVED:-0}"
RUN_OVERLAY_SMOKE="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_RUN_OVERLAY:-0}"
REQUIRE_OVERLAY_READY="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_OVERLAY_READY:-0}"
REQUIRE_ONBOARDING_TRANSITION="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_ONBOARDING_TRANSITION:-0}"
REQUIRE_VISION_OBSERVE="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_VISION_OBSERVE:-0}"
REQUIRE_OBSERVE_ACTION_OBSERVE="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_OBSERVE_ACTION_OBSERVE:-0}"
REQUIRE_DESKTOP_ACTION_CANARY="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_DESKTOP_ACTION_CANARY:-0}"
REQUIRE_COMPUTER_USE_LIVE_CANARY="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_LIVE_CANARY:-0}"
REQUIRE_RELEASE_SIGNOFF="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_RELEASE_SIGNOFF:-0}"
REQUIRE_RELEASE_RUNTIME_SIGNOFF="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_RELEASE_RUNTIME_SIGNOFF:-0}"
SKIP_RELEASE_BUILD="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_SKIP_RELEASE_BUILD:-0}"
REGISTER_XPC_AGENT="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REGISTER_XPC_AGENT:-0}"
CLEANUP_XPC_AGENT="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_CLEANUP_XPC_AGENT:-0}"
REPORT_PATH="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH:-/tmp/caverno-macos-computer-use-smoke.json}"

print_m4_signoff_summary() {
  if [[ "${M4_SIGNOFF}" != "1" ]]; then
    return 0
  fi

  echo
  echo "M4 sign-off summary"

  if [[ ! -f "${REPORT_PATH}" ]]; then
    echo "  Status: report missing"
    echo "  Report: ${REPORT_PATH}"
    echo "  Next action: rerun --m4-signoff and inspect the Flutter test output."
    return 0
  fi

  REPORT_PATH="${REPORT_PATH}" python3 - <<'PY'
import json
import os
from pathlib import Path


def value_text(value, fallback="unknown"):
    if value is None:
        return fallback
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list):
        return ", ".join(str(item) for item in value) if value else "none"
    return str(value)


def map_value(value):
    return value if isinstance(value, dict) else {}


def list_value(value):
    return value if isinstance(value, list) else []


path = Path(os.environ["REPORT_PATH"])
try:
    report = json.loads(path.read_text())
except Exception as error:
    print("  Status: report unreadable")
    print(f"  Report: {path}")
    print(f"  Error: {error}")
    print("  Next action: rerun --m4-signoff and inspect the Flutter test output.")
    raise SystemExit(0)

gate = map_value(report.get("m4SignoffGate"))
helper_path = map_value(gate.get("helperPath"))
checks = [
    map_value(item)
    for item in list_value(gate.get("checks"))
    if isinstance(item, dict)
]
failed = {
    str(item)
    for item in list_value(gate.get("failed")) + list_value(gate.get("blockers"))
}

print(f"  Status: {value_text(gate.get('status'))}")
print(f"  Blockers: {value_text(gate.get('blockers'), 'none')}")
if helper_path.get("embeddedHelperPath"):
    print(f"  Embedded helper: {helper_path['embeddedHelperPath']}")
if helper_path.get("runningHelperPath"):
    print(f"  Running helper: {helper_path['runningHelperPath']}")

next_action = gate.get("nextAction")
if next_action:
    print(f"  Next action: {next_action}")

for check in checks:
    check_id = str(check.get("id", ""))
    if check.get("ok") is True and check_id not in failed:
        continue
    label = value_text(check.get("label"), check_id or "check")
    status = value_text(check.get("status"))
    action = check.get("nextAction")
    if action:
        print(f"  - {label}: {status}; {action}")
    else:
        print(f"  - {label}: {status}")

print(
    "  Grant helper: bash tool/run_macos_computer_use_capture_signoff.sh "
    "--reveal-helper --open-settings"
)
print(
    "  Rerun: bash tool/run_macos_computer_use_smoke_test.sh "
    "--reporter compact --m4-signoff"
)
PY
}

print_release_signoff_summary() {
  if [[ "${BUILD_MODE}" != "release" && "${REQUIRE_RELEASE_SIGNOFF}" != "1" ]]; then
    return 0
  fi

  echo
  echo "M7 release sign-off summary"

  if [[ ! -f "${REPORT_PATH}" ]]; then
    echo "  Status: report missing"
    echo "  Report: ${REPORT_PATH}"
    echo "  Next action: rerun --m7-signoff and inspect the Flutter build output."
    return 0
  fi

  REPORT_PATH="${REPORT_PATH}" python3 - <<'PY'
import json
import os
from pathlib import Path


def value_text(value, fallback="unknown"):
    if value is None:
        return fallback
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list):
        return ", ".join(str(item) for item in value) if value else "none"
    return str(value)


def map_value(value):
    return value if isinstance(value, dict) else {}


def list_value(value):
    return value if isinstance(value, list) else []


path = Path(os.environ["REPORT_PATH"])
try:
    report = json.loads(path.read_text())
except Exception as error:
    print("  Status: report unreadable")
    print(f"  Report: {path}")
    print(f"  Error: {error}")
    print("  Next action: rerun --m7-signoff and inspect the Flutter build output.")
    raise SystemExit(0)

gate = map_value(report.get("releaseSignoffGate"))
runtime = map_value(report.get("releaseRuntimeReadiness"))
checks = [
    map_value(item)
    for item in list_value(gate.get("checks"))
    if isinstance(item, dict)
]

print(f"  Status: {value_text(gate.get('status'))}")
print(f"  Blockers: {value_text(gate.get('blockers'), 'none')}")
if gate.get("helperPath"):
    print(f"  Release helper: {gate['helperPath']}")
if runtime.get("status"):
    print(f"  Runtime TCC: {runtime['status']}")

next_action = gate.get("nextAction")
if next_action:
    print(f"  Next action: {next_action}")

for check in checks:
    if check.get("ok") is True:
        continue
    label = value_text(check.get("label"), value_text(check.get("id"), "check"))
    status = value_text(check.get("status"))
    action = check.get("nextAction")
    if action:
        print(f"  - {label}: {status}; {action}")
    else:
        print(f"  - {label}: {status}")
PY
}

print_release_runtime_signoff_summary() {
  if [[ "${REQUIRE_RELEASE_RUNTIME_SIGNOFF}" != "1" ]]; then
    return 0
  fi

  echo
  echo "M8 release runtime sign-off summary"

  if [[ ! -f "${REPORT_PATH}" ]]; then
    echo "  Status: report missing"
    echo "  Report: ${REPORT_PATH}"
    echo "  Next action: rerun --m8-runtime-signoff and inspect the runtime output."
    return 0
  fi

  REPORT_PATH="${REPORT_PATH}" python3 - <<'PY'
import json
import os
from pathlib import Path


def value_text(value, fallback="unknown"):
    if value is None:
        return fallback
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list):
        return ", ".join(str(item) for item in value) if value else "none"
    return str(value)


def map_value(value):
    return value if isinstance(value, dict) else {}


def list_value(value):
    return value if isinstance(value, list) else []


path = Path(os.environ["REPORT_PATH"])
try:
    report = json.loads(path.read_text())
except Exception as error:
    print("  Status: report unreadable")
    print(f"  Report: {path}")
    print(f"  Error: {error}")
    print("  Next action: rerun --m8-runtime-signoff and inspect the runtime output.")
    raise SystemExit(0)

gate = map_value(report.get("releaseRuntimeSignoffGate"))
readiness = map_value(report.get("releaseRuntimeReadiness"))
checks = [
    map_value(item)
    for item in list_value(gate.get("checks"))
    if isinstance(item, dict)
]

print(f"  Status: {value_text(gate.get('status'))}")
print(f"  Blockers: {value_text(gate.get('blockers'), 'none')}")
if gate.get("appPath"):
    print(f"  Release app: {gate['appPath']}")
if gate.get("helperPath"):
    print(f"  Release helper: {gate['helperPath']}")
if readiness.get("status"):
    print(f"  Runtime readiness: {readiness['status']}")

next_action = gate.get("nextAction")
if next_action:
    print(f"  Next action: {next_action}")

for check in checks:
    if check.get("ok") is True:
        continue
    label = value_text(check.get("label"), value_text(check.get("id"), "check"))
    status = value_text(check.get("status"))
    action = check.get("nextAction")
    if action:
        print(f"  - {label}: {status}; {action}")
    else:
        print(f"  - {label}: {status}")
PY
}

print_manual_tcc_notice() {
  if [[ "${REQUIRE_RELEASE_RUNTIME_SIGNOFF}" != "1" ]]; then
    return 0
  fi

  echo
  echo "Manual TCC sign-off notice"
  echo "  This command measures macOS TCC state only; it does not grant permissions or edit TCC."
  echo "  Run it from a user-controlled terminal after granting the release helper in System Settings."
  echo "  Automation agents should stop here and ask the user to run this command manually."
}

finish() {
  local exit_code=$?
  set +e
  print_m4_signoff_summary
  print_release_signoff_summary
  print_release_runtime_signoff_summary
  exit "${exit_code}"
}

trap finish EXIT

dart_bool_define() {
  case "$1" in
    1|true|TRUE|yes|YES)
      echo "true"
      ;;
    *)
      echo "false"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=1
      shift
      ;;
    --strict-xpc)
      STRICT_XPC=1
      REGISTER_XPC_AGENT=1
      shift
      ;;
    --m4-signoff)
      M4_SIGNOFF=1
      STRICT_XPC=1
      REGISTER_XPC_AGENT=1
      UNSAFE_ARMED=1
      REQUIRE_CAPTURE_READY=1
      REQUIRE_AUDIO_RESOLVED=1
      RUN_OVERLAY_SMOKE=1
      REQUIRE_OVERLAY_READY=1
      REQUIRE_ONBOARDING_TRANSITION=1
      shift
      ;;
    --m7-signoff|--release-signoff)
      BUILD_MODE=release
      STRICT_XPC=1
      REGISTER_XPC_AGENT=1
      CLEANUP_XPC_AGENT=1
      REQUIRE_RELEASE_SIGNOFF=1
      shift
      ;;
    --m8-runtime-signoff|--release-runtime-signoff)
      BUILD_MODE=release
      STRICT_XPC=1
      REGISTER_XPC_AGENT=1
      CLEANUP_XPC_AGENT=1
      REQUIRE_RELEASE_SIGNOFF=1
      REQUIRE_RELEASE_RUNTIME_SIGNOFF=1
      SKIP_RELEASE_BUILD=1
      shift
      ;;
    --require-release-signoff)
      REQUIRE_RELEASE_SIGNOFF=1
      shift
      ;;
    --require-release-runtime-signoff)
      REQUIRE_RELEASE_SIGNOFF=1
      REQUIRE_RELEASE_RUNTIME_SIGNOFF=1
      shift
      ;;
    --no-release-build|--skip-release-build)
      SKIP_RELEASE_BUILD=1
      shift
      ;;
    --rebuild-release)
      SKIP_RELEASE_BUILD=0
      shift
      ;;
    --debug|--profile|--release)
      BUILD_MODE="${1#--}"
      shift
      ;;
    --unsafe-armed)
      UNSAFE_ARMED=1
      shift
      ;;
    --unsafe-click-armed)
      UNSAFE_ARMED=1
      UNSAFE_CLICK_ARMED=1
      shift
      ;;
    --unsafe-text-armed)
      UNSAFE_ARMED=1
      UNSAFE_TEXT_ARMED=1
      shift
      ;;
    --require-capture|--require-capture-ready)
      REQUIRE_CAPTURE_READY=1
      shift
      ;;
    --require-input|--require-input-ready)
      REQUIRE_INPUT_READY=1
      shift
      ;;
    --require-audio|--require-audio-resolved)
      REQUIRE_AUDIO_RESOLVED=1
      shift
      ;;
    --overlay-smoke|--run-overlay)
      RUN_OVERLAY_SMOKE=1
      shift
      ;;
    --require-overlay|--require-overlay-ready)
      RUN_OVERLAY_SMOKE=1
      REQUIRE_OVERLAY_READY=1
      shift
      ;;
    --require-onboarding-transition|--require-allow-transition)
      RUN_OVERLAY_SMOKE=1
      REQUIRE_ONBOARDING_TRANSITION=1
      shift
      ;;
    --require-vision-observe|--require-vision-loop)
      REQUIRE_VISION_OBSERVE=1
      shift
      ;;
    --require-observe-action-observe|--require-m6-loop)
      UNSAFE_ARMED=1
      REQUIRE_VISION_OBSERVE=1
      REQUIRE_OBSERVE_ACTION_OBSERVE=1
      shift
      ;;
    --desktop-action-canary|--require-desktop-action-canary|--require-click-canary)
      UNSAFE_ARMED=1
      UNSAFE_CLICK_ARMED=1
      REQUIRE_VISION_OBSERVE=1
      REQUIRE_DESKTOP_ACTION_CANARY=1
      shift
      ;;
    --computer-use-live-canary|--require-computer-use-live-canary|--canary)
      REQUIRE_COMPUTER_USE_LIVE_CANARY=1
      STRICT=0
      REQUIRE_CAPTURE_READY=0
      REQUIRE_INPUT_READY=0
      REQUIRE_AUDIO_RESOLVED=0
      RUN_OVERLAY_SMOKE=0
      REQUIRE_OVERLAY_READY=0
      REQUIRE_ONBOARDING_TRANSITION=0
      REQUIRE_VISION_OBSERVE=0
      REQUIRE_OBSERVE_ACTION_OBSERVE=0
      REQUIRE_DESKTOP_ACTION_CANARY=0
      UNSAFE_ARMED=0
      UNSAFE_CLICK_ARMED=0
      UNSAFE_TEXT_ARMED=0
      shift
      ;;
    --register-xpc-agent)
      REGISTER_XPC_AGENT=1
      shift
      ;;
    --cleanup-xpc-agent|--unregister-xpc-agent)
      CLEANUP_XPC_AGENT=1
      shift
      ;;
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --reporter)
      REPORTER="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 2
      ;;
  esac
done

echo "Running macOS computer-use live smoke"
echo "  Device: ${DEVICE}"
echo "  Reporter: ${REPORTER}"
echo "  Build mode: ${BUILD_MODE}"
echo "  Strict: ${STRICT}"
echo "  Strict XPC: ${STRICT_XPC}"
echo "  M4 sign-off: ${M4_SIGNOFF}"
echo "  Unsafe armed: ${UNSAFE_ARMED}"
echo "  Unsafe click armed: ${UNSAFE_CLICK_ARMED}"
echo "  Unsafe text armed: ${UNSAFE_TEXT_ARMED}"
echo "  Require capture ready: ${REQUIRE_CAPTURE_READY}"
echo "  Require input ready: ${REQUIRE_INPUT_READY}"
echo "  Require audio resolved: ${REQUIRE_AUDIO_RESOLVED}"
echo "  Run overlay smoke: ${RUN_OVERLAY_SMOKE}"
echo "  Require overlay ready: ${REQUIRE_OVERLAY_READY}"
echo "  Require onboarding transition: ${REQUIRE_ONBOARDING_TRANSITION}"
echo "  Require vision observe: ${REQUIRE_VISION_OBSERVE}"
echo "  Require observe-action-observe: ${REQUIRE_OBSERVE_ACTION_OBSERVE}"
echo "  Require desktop action canary: ${REQUIRE_DESKTOP_ACTION_CANARY}"
echo "  Require Computer Use live canary: ${REQUIRE_COMPUTER_USE_LIVE_CANARY}"
echo "  Require release sign-off: ${REQUIRE_RELEASE_SIGNOFF}"
echo "  Require release runtime sign-off: ${REQUIRE_RELEASE_RUNTIME_SIGNOFF}"
echo "  Skip release build: ${SKIP_RELEASE_BUILD}"
echo "  Register XPC agent: ${REGISTER_XPC_AGENT}"
echo "  Cleanup XPC agent: ${CLEANUP_XPC_AGENT}"
echo "  Report: ${REPORT_PATH}"

print_manual_tcc_notice

STRICT_DART="$(dart_bool_define "${STRICT}")"
STRICT_XPC_DART="$(dart_bool_define "${STRICT_XPC}")"
M4_SIGNOFF_DART="$(dart_bool_define "${M4_SIGNOFF}")"
UNSAFE_ARMED_DART="$(dart_bool_define "${UNSAFE_ARMED}")"
UNSAFE_CLICK_ARMED_DART="$(dart_bool_define "${UNSAFE_CLICK_ARMED}")"
UNSAFE_TEXT_ARMED_DART="$(dart_bool_define "${UNSAFE_TEXT_ARMED}")"
REQUIRE_CAPTURE_READY_DART="$(dart_bool_define "${REQUIRE_CAPTURE_READY}")"
REQUIRE_INPUT_READY_DART="$(dart_bool_define "${REQUIRE_INPUT_READY}")"
REQUIRE_AUDIO_RESOLVED_DART="$(dart_bool_define "${REQUIRE_AUDIO_RESOLVED}")"
RUN_OVERLAY_SMOKE_DART="$(dart_bool_define "${RUN_OVERLAY_SMOKE}")"
REQUIRE_OVERLAY_READY_DART="$(dart_bool_define "${REQUIRE_OVERLAY_READY}")"
REQUIRE_ONBOARDING_TRANSITION_DART="$(dart_bool_define "${REQUIRE_ONBOARDING_TRANSITION}")"
REQUIRE_VISION_OBSERVE_DART="$(dart_bool_define "${REQUIRE_VISION_OBSERVE}")"
REQUIRE_OBSERVE_ACTION_OBSERVE_DART="$(dart_bool_define "${REQUIRE_OBSERVE_ACTION_OBSERVE}")"
REQUIRE_DESKTOP_ACTION_CANARY_DART="$(dart_bool_define "${REQUIRE_DESKTOP_ACTION_CANARY}")"
REQUIRE_COMPUTER_USE_LIVE_CANARY_DART="$(dart_bool_define "${REQUIRE_COMPUTER_USE_LIVE_CANARY}")"
REQUIRE_RELEASE_SIGNOFF_DART="$(dart_bool_define "${REQUIRE_RELEASE_SIGNOFF}")"
REQUIRE_RELEASE_RUNTIME_SIGNOFF_DART="$(dart_bool_define "${REQUIRE_RELEASE_RUNTIME_SIGNOFF}")"
SKIP_RELEASE_BUILD_DART="$(dart_bool_define "${SKIP_RELEASE_BUILD}")"
REGISTER_XPC_AGENT_DART="$(dart_bool_define "${REGISTER_XPC_AGENT}")"
CLEANUP_XPC_AGENT_DART="$(dart_bool_define "${CLEANUP_XPC_AGENT}")"

cd "${ROOT_DIR}"

COMMON_DART_DEFINES=(
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT="${STRICT_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT_XPC="${STRICT_XPC_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_M4_SIGNOFF="${M4_SIGNOFF_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_ARMED="${UNSAFE_ARMED_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_CLICK_ARMED="${UNSAFE_CLICK_ARMED_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_TEXT_ARMED="${UNSAFE_TEXT_ARMED_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_CAPTURE_READY="${REQUIRE_CAPTURE_READY_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_INPUT_READY="${REQUIRE_INPUT_READY_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_AUDIO_RESOLVED="${REQUIRE_AUDIO_RESOLVED_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_RUN_OVERLAY="${RUN_OVERLAY_SMOKE_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_OVERLAY_READY="${REQUIRE_OVERLAY_READY_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_ONBOARDING_TRANSITION="${REQUIRE_ONBOARDING_TRANSITION_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_VISION_OBSERVE="${REQUIRE_VISION_OBSERVE_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_OBSERVE_ACTION_OBSERVE="${REQUIRE_OBSERVE_ACTION_OBSERVE_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_DESKTOP_ACTION_CANARY="${REQUIRE_DESKTOP_ACTION_CANARY_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_LIVE_CANARY="${REQUIRE_COMPUTER_USE_LIVE_CANARY_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_RELEASE_SIGNOFF="${REQUIRE_RELEASE_SIGNOFF_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REQUIRE_RELEASE_RUNTIME_SIGNOFF="${REQUIRE_RELEASE_RUNTIME_SIGNOFF_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_SKIP_RELEASE_BUILD="${SKIP_RELEASE_BUILD_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REGISTER_XPC_AGENT="${REGISTER_XPC_AGENT_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_CLEANUP_XPC_AGENT="${CLEANUP_XPC_AGENT_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH="${REPORT_PATH}"
)

case "${BUILD_MODE}" in
  debug)
    flutter test integration_test/macos_computer_use_smoke_test.dart \
      -d "${DEVICE}" \
      -r "${REPORTER}" \
      "${COMMON_DART_DEFINES[@]}"
    ;;
  profile)
    flutter drive \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/macos_computer_use_smoke_test.dart \
      --"${BUILD_MODE}" \
      -d "${DEVICE}" \
      "${COMMON_DART_DEFINES[@]}"
    ;;
  release)
    if [[ "${SKIP_RELEASE_BUILD}" == "1" ]]; then
      echo "Skipping release build; using the existing release app artifact."
    else
      flutter build macos --release "${COMMON_DART_DEFINES[@]}"
    fi
    RELEASE_APP="${ROOT_DIR}/build/macos/Build/Products/Release/Caverno.app"
    RELEASE_HELPER="${RELEASE_APP}/Contents/Helpers/Caverno Computer Use.app"
    RELEASE_AGENT="${RELEASE_APP}/Contents/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist"
    RELEASE_ARTIFACT_REPORT_PATH="${REPORT_PATH}"
    if [[ "${REQUIRE_RELEASE_RUNTIME_SIGNOFF}" == "1" ]]; then
      RELEASE_ARTIFACT_REPORT_PATH="${REPORT_PATH}.release-artifact.json"
    fi
    RELEASE_REPORT_PATH="${RELEASE_ARTIFACT_REPORT_PATH}" \
    RELEASE_APP="${RELEASE_APP}" \
    RELEASE_HELPER="${RELEASE_HELPER}" \
    RELEASE_AGENT="${RELEASE_AGENT}" \
    REQUIRE_RELEASE_SIGNOFF_DART="${REQUIRE_RELEASE_SIGNOFF_DART}" \
    REQUIRE_RELEASE_RUNTIME_SIGNOFF_DART="${REQUIRE_RELEASE_RUNTIME_SIGNOFF_DART}" \
    SKIP_RELEASE_BUILD_DART="${SKIP_RELEASE_BUILD_DART}" \
    STRICT_DART="${STRICT_DART}" \
    STRICT_XPC_DART="${STRICT_XPC_DART}" \
    M4_SIGNOFF_DART="${M4_SIGNOFF_DART}" \
    REGISTER_XPC_AGENT_DART="${REGISTER_XPC_AGENT_DART}" \
    CLEANUP_XPC_AGENT_DART="${CLEANUP_XPC_AGENT_DART}" \
      python3 - <<'PY'
import datetime
import json
import os
import subprocess
from pathlib import Path

APP_BUNDLE_ID = "com.noguwo.apps.caverno"
HELPER_BUNDLE_ID = "com.noguwo.apps.caverno.computer-use"
XPC_SERVICE_NAME = "com.noguwo.apps.caverno.computer-use.xpc"


def run_command(args):
    completed = subprocess.run(args, capture_output=True, text=True, check=False)
    return {
        "exitCode": completed.returncode,
        "stdout": completed.stdout.strip(),
        "stderr": completed.stderr.strip(),
    }


def check_item(check_id, label, ok, status=None, next_action=None, details=None):
    item = {
        "id": check_id,
        "label": label,
        "ok": bool(ok),
        "status": status or ("ready" if ok else "blocked"),
    }
    if next_action:
        item["nextAction"] = next_action
    if details is not None:
        item["details"] = details
    return item


def parse_codesign_details(output):
    values = {}
    authorities = []
    code_directory_flags = None
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if line.startswith("Authority="):
            authorities.append(line.split("=", 1)[1])
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
        if " flags=" in line:
            flags = line.split(" flags=", 1)[1].split(" ", 1)[0]
            code_directory_flags = flags
    team_identifier = values.get("TeamIdentifier")
    signature = values.get("Signature")
    ad_hoc = signature == "adhoc" or (
        team_identifier in (None, "", "not set") and not authorities
    )
    hardened_runtime = "Runtime Version" in values or (
        code_directory_flags is not None and "runtime" in code_directory_flags
    )
    return {
        "identifier": values.get("Identifier"),
        "format": values.get("Format"),
        "signature": signature,
        "teamIdentifier": team_identifier,
        "authorities": authorities,
        "codeDirectoryFlags": code_directory_flags,
        "hardenedRuntime": hardened_runtime,
        "adHoc": ad_hoc,
    }


def codesign_diagnostics(path, role):
    exists = os.path.exists(path)
    verify = run_command(["/usr/bin/codesign", "--verify", "--strict", path]) if exists else None
    details = run_command(["/usr/bin/codesign", "-dv", "--verbose=4", path]) if exists else None
    parsed = parse_codesign_details(details["stderr"] if details else "")
    team_identifier = parsed.get("teamIdentifier")
    blockers = []
    if not exists:
        blockers.append("bundle_missing")
    if verify is None or verify["exitCode"] != 0:
        blockers.append("codesign_verify_failed")
    if parsed.get("adHoc"):
        blockers.append("ad_hoc_signature")
    if team_identifier in (None, "", "not set"):
        blockers.append("team_identifier_missing")
    return {
        "role": role,
        "path": path,
        "exists": exists,
        "verifyExitCode": None if verify is None else verify["exitCode"],
        "verifyStderr": None if verify is None else verify["stderr"],
        "launchConstraintLikelyAccepted": len(blockers) == 0,
        "launchConstraintBlockers": blockers,
        **parsed,
    }


def command_ok(result):
    return result is not None and result["exitCode"] == 0


def first_failure_action(blockers):
    if not blockers:
        return "M7 release helper sign-off is complete."
    if "release_app_missing" in blockers:
        return "Rebuild the release app and verify build/macos/Build/Products/Release/Caverno.app exists."
    if "release_helper_missing" in blockers:
        return "Verify the release build embeds Caverno Computer Use.app in Contents/Helpers."
    if "release_launch_agent_missing" in blockers:
        return "Verify the release build copies the LaunchAgent plist into Contents/Library/LaunchAgents."
    if "release_launch_agent_plist_invalid" in blockers:
        return "Fix the release LaunchAgent plist and rerun --m7-signoff."
    if "release_mach_service_missing" in blockers:
        return "Declare the helper MachService in the release LaunchAgent plist."
    if "release_codesign_failed" in blockers:
        return "Fix release app or helper code signing, then rerun --m7-signoff."
    if "release_app_identity_mismatch" in blockers or "release_helper_identity_mismatch" in blockers:
        return "Fix release bundle identifiers before requesting macOS permissions."
    if "release_launch_constraints_blocked" in blockers:
        return (
            "Use a valid code signing identity and TeamIdentifier for release "
            "LaunchAgent constraints. Add local overrides in "
            "macos/Runner/Configs/Signing.local.xcconfig, verify "
            "`security find-identity -v -p codesigning` lists a valid identity, "
            "then rerun --m7-signoff."
        )
    return "Resolve the failed M7 release sign-off checks, then rerun --m7-signoff."


report_path = os.environ["RELEASE_REPORT_PATH"]
app = os.environ["RELEASE_APP"]
helper = os.environ["RELEASE_HELPER"]
agent = os.environ["RELEASE_AGENT"]
app_signing = codesign_diagnostics(app, "app")
helper_signing = codesign_diagnostics(helper, "helper")
app_exists = os.path.isdir(app)
helper_exists = os.path.isdir(helper)
agent_exists = os.path.isfile(agent)
plist_lint = run_command(["/usr/bin/plutil", "-lint", agent]) if agent_exists else None
mach_service = (
    run_command([
        "/usr/libexec/PlistBuddy",
        "-c",
        f"Print :MachServices:{XPC_SERVICE_NAME}",
        agent,
    ])
    if agent_exists
    else None
)
deep_codesign = (
    run_command(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    if app_exists
    else None
)
plist_valid = command_ok(plist_lint)
mach_service_declared = command_ok(mach_service)
codesign_verified = command_ok(deep_codesign)
signing_blockers = [
    f"app:{blocker}" for blocker in app_signing["launchConstraintBlockers"]
] + [
    f"helper:{blocker}" for blocker in helper_signing["launchConstraintBlockers"]
]
blockers = []
if not app_exists:
    blockers.append("release_app_missing")
if not helper_exists:
    blockers.append("release_helper_missing")
if not agent_exists:
    blockers.append("release_launch_agent_missing")
if agent_exists and not plist_valid:
    blockers.append("release_launch_agent_plist_invalid")
if agent_exists and not mach_service_declared:
    blockers.append("release_mach_service_missing")
if not codesign_verified:
    blockers.append("release_codesign_failed")
if app_signing.get("identifier") not in (None, APP_BUNDLE_ID):
    blockers.append("release_app_identity_mismatch")
if helper_signing.get("identifier") not in (None, HELPER_BUNDLE_ID):
    blockers.append("release_helper_identity_mismatch")
if signing_blockers:
    blockers.append("release_launch_constraints_blocked")

checks = [
    check_item(
        "release_app_bundle",
        "Release app bundle",
        app_exists,
        details={"path": app},
    ),
    check_item(
        "release_helper_bundle",
        "Release helper bundle",
        helper_exists,
        next_action="Verify the release build embeds Caverno Computer Use.app in Contents/Helpers.",
        details={"path": helper},
    ),
    check_item(
        "release_launch_agent",
        "Release LaunchAgent",
        agent_exists,
        next_action="Verify the release build copies the LaunchAgent plist into Contents/Library/LaunchAgents.",
        details={
            "path": agent,
            "plistLint": plist_lint,
        },
    ),
    check_item(
        "release_mach_service",
        "Release MachService",
        mach_service_declared,
        next_action=f"Declare {XPC_SERVICE_NAME} in the release LaunchAgent plist.",
        details={"command": mach_service},
    ),
    check_item(
        "release_codesign",
        "Release codesign",
        codesign_verified,
        next_action="Fix release app or helper code signing, then rerun --m7-signoff.",
        details={"deepVerify": deep_codesign},
    ),
    check_item(
        "release_app_identity",
        "Release app bundle identifier",
        app_signing.get("identifier") in (None, APP_BUNDLE_ID),
        next_action=f"Set the release app bundle identifier to {APP_BUNDLE_ID}.",
        details={"identifier": app_signing.get("identifier")},
    ),
    check_item(
        "release_helper_identity",
        "Release helper bundle identifier",
        helper_signing.get("identifier") in (None, HELPER_BUNDLE_ID),
        next_action=f"Set the release helper bundle identifier to {HELPER_BUNDLE_ID}.",
        details={"identifier": helper_signing.get("identifier")},
    ),
    check_item(
        "release_launch_constraints",
        "Release LaunchAgent signing constraints",
        len(signing_blockers) == 0,
        next_action=(
            "Use a valid code signing identity and TeamIdentifier for release "
            "LaunchAgent constraints. Add local overrides in "
            "macos/Runner/Configs/Signing.local.xcconfig, verify "
            "`security find-identity -v -p codesigning` lists a valid identity, "
            "then rerun --m7-signoff."
        ),
        details={"blockers": signing_blockers},
    ),
]
runtime_readiness = {
    "status": "not_measured",
    "helperBundleIdentifier": helper_signing.get("identifier") or HELPER_BUNDLE_ID,
    "helperPath": helper,
    "requiredPermissions": [
        "Accessibility",
        "Screen & System Audio Recording",
    ],
    "nextAction": (
        "Install and launch the release app, grant Accessibility to the release helper "
        "and Screen & System Audio Recording to Caverno.app in macOS Privacy & Security, "
        "then run a live release runtime smoke on that installed app."
    ),
}
gate = {
    "status": "ready" if not blockers else "blocked",
    "blockers": blockers,
    "checks": checks,
    "helperPath": helper,
    "appPath": app,
    "launchAgentPath": agent,
    "xpcServiceName": XPC_SERVICE_NAME,
    "runtimeTccStatus": runtime_readiness["status"],
    "nextAction": first_failure_action(blockers),
}
report = {
    "schemaName": "macos_computer_use_release_bundle_smoke",
    "schemaVersion": 2,
    "generatedAt": datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
    "buildMode": "release",
    "strict": os.environ["STRICT_DART"] == "true",
    "strictXpc": os.environ["STRICT_XPC_DART"] == "true",
    "m4Signoff": os.environ["M4_SIGNOFF_DART"] == "true",
    "releaseSignoff": os.environ["REQUIRE_RELEASE_SIGNOFF_DART"] == "true",
    "skipReleaseBuild": os.environ["SKIP_RELEASE_BUILD_DART"] == "true",
    "registerXpcAgent": os.environ["REGISTER_XPC_AGENT_DART"] == "true",
    "cleanupXpcAgent": os.environ["CLEANUP_XPC_AGENT_DART"] == "true",
    "ok": len(blockers) == 0,
    "releaseBundle": {
        "appExists": app_exists,
        "helperExists": helper_exists,
        "launchAgentExists": agent_exists,
        "launchAgentPlistValid": plist_valid,
        "machServiceDeclared": mach_service_declared,
        "codesignVerified": codesign_verified,
        "appPath": app,
        "helperPath": helper,
        "launchAgentPath": agent,
        "xpcServiceName": XPC_SERVICE_NAME,
        "plistLint": plist_lint,
        "machServiceProbe": mach_service,
        "codesignDeepVerify": deep_codesign,
    },
    "signingDiagnostics": {
        "app": app_signing,
        "helper": helper_signing,
        "launchAgent": {
            "path": agent,
            "exists": os.path.isfile(agent),
        },
        "launchConstraintLikelyAccepted": len(signing_blockers) == 0,
        "launchConstraintBlockers": signing_blockers,
    },
    "releaseRuntimeReadiness": runtime_readiness,
    "releaseSignoffGate": gate,
    "reportPath": report_path,
}
encoded = json.dumps(report, indent=2)
if report_path:
    path = Path(report_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(encoded)
print(f"CAVERNO_MACOS_COMPUTER_USE_SMOKE_JSON={encoded}")
if (
    os.environ["REQUIRE_RELEASE_SIGNOFF_DART"] == "true"
    and os.environ["REQUIRE_RELEASE_RUNTIME_SIGNOFF_DART"] != "true"
    and blockers
):
    raise SystemExit(1)
PY
    if [[ "${REQUIRE_RELEASE_RUNTIME_SIGNOFF}" == "1" ]]; then
      RELEASE_RUNTIME_PROBE_REPORT_PATH="${REPORT_PATH}.runtime-probe.json"
      set +e
      CAVERNO_MACOS_COMPUTER_USE_EXISTING_HELPER_REPORT_PATH="${RELEASE_RUNTIME_PROBE_REPORT_PATH}" \
        bash tool/run_macos_computer_use_existing_helper_probe.sh \
        --app "${RELEASE_APP}" \
        --helper "${RELEASE_HELPER}" \
        --replace-app \
        --replace-helper \
        --require-app-path-match \
        --require-helper-path-match \
        --require-capture \
        --require-input \
        --require-audio
      RELEASE_RUNTIME_PROBE_EXIT=$?
      set -e
      RELEASE_ARTIFACT_REPORT_PATH="${RELEASE_ARTIFACT_REPORT_PATH}" \
      RELEASE_RUNTIME_PROBE_REPORT_PATH="${RELEASE_RUNTIME_PROBE_REPORT_PATH}" \
      RELEASE_REPORT_PATH="${REPORT_PATH}" \
      RELEASE_RUNTIME_PROBE_EXIT="${RELEASE_RUNTIME_PROBE_EXIT}" \
        python3 - <<'PY'
import datetime
import json
import os
from pathlib import Path


def map_value(value):
    return value if isinstance(value, dict) else {}


def list_value(value):
    return value if isinstance(value, list) else []


def redact_images(value):
    if isinstance(value, dict):
        return {
            key: "<redacted: see runtime probe report>"
            if key == "imageBase64"
            else redact_images(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact_images(item) for item in value]
    return value


def check_item(check_id, label, ok, status=None, next_action=None, details=None):
    item = {
        "id": check_id,
        "label": label,
        "ok": bool(ok),
        "status": status or ("ready" if ok else "blocked"),
    }
    if next_action:
        item["nextAction"] = next_action
    if details is not None:
        item["details"] = details
    return item


def step_ok(probe, step_id):
    for step in list_value(probe.get("steps")):
        if map_value(step).get("id") == step_id:
            return map_value(step).get("ok") is True
    return False


def next_action(blockers):
    if not blockers:
        return "M8 release runtime sign-off is complete."
    if "release_artifact_gate_blocked" in blockers:
        return "Resolve the release artifact blockers, then rerun --m8-runtime-signoff."
    if "release_runtime_app_path_mismatch" in blockers:
        return "Stop the running Caverno.app and rerun --m8-runtime-signoff."
    if "release_runtime_helper_path_mismatch" in blockers:
        return "Stop the running helper and rerun --m8-runtime-signoff."
    if "release_runtime_permissions_blocked" in blockers:
        return "Ask the user to grant Accessibility to the release helper and Screen & System Audio Recording to the release Caverno.app, then rerun --m8-runtime-signoff manually."
    if "release_runtime_capture_blocked" in blockers:
        return "Ask the user to grant Screen & System Audio Recording to the release Caverno.app, then rerun --m8-runtime-signoff manually."
    return "Resolve the failed M8 runtime checks, then ask the user to rerun --m8-runtime-signoff manually."


artifact_path = Path(os.environ["RELEASE_ARTIFACT_REPORT_PATH"])
probe_path = Path(os.environ["RELEASE_RUNTIME_PROBE_REPORT_PATH"])
report_path = Path(os.environ["RELEASE_REPORT_PATH"])
artifact = json.loads(artifact_path.read_text())
probe = json.loads(probe_path.read_text()) if probe_path.exists() else {}
artifact_gate = map_value(artifact.get("releaseSignoffGate"))
artifact_blockers = list_value(artifact_gate.get("blockers"))
permission_summary = map_value(probe.get("permissionSummary"))
app = map_value(probe.get("app"))
helper = map_value(probe.get("helper"))
probe_exit = int(os.environ["RELEASE_RUNTIME_PROBE_EXIT"])
app_path_ok = probe.get("appPathMatchesExpected") is True
helper_path_ok = probe.get("helperPathMatchesExpected") is True
permission_status_ok = step_ok(probe, "permission_status")
display_ok = step_ok(probe, "display_screenshot")
windows_ok = step_ok(probe, "list_windows")
window_ok = step_ok(probe, "window_capture")
accessibility_ok = permission_summary.get("accessibilityGranted") is True
screen_capture_ok = permission_summary.get("screenCaptureGranted") is True
capture_ready = probe.get("captureReady") is True
input_ready = probe.get("inputReady") is True
audio_resolved = probe.get("audioResolved") is True
runtime_blockers = []
if artifact_blockers:
    runtime_blockers.append("release_artifact_gate_blocked")
if probe_exit != 0 and not probe:
    runtime_blockers.append("release_runtime_probe_failed")
if not app_path_ok:
    runtime_blockers.append("release_runtime_app_path_mismatch")
if not helper_path_ok:
    runtime_blockers.append("release_runtime_helper_path_mismatch")
if not permission_status_ok:
    runtime_blockers.append("release_runtime_permission_status_failed")
if not accessibility_ok or not screen_capture_ok:
    runtime_blockers.append("release_runtime_permissions_blocked")
if not capture_ready:
    runtime_blockers.append("release_runtime_capture_blocked")
if not input_ready:
    runtime_blockers.append("release_runtime_input_blocked")
if not audio_resolved:
    runtime_blockers.append("release_runtime_audio_blocked")

checks = [
    check_item(
        "release_artifact_gate",
        "Release artifact gate",
        not artifact_blockers,
        details={"blockers": artifact_blockers},
    ),
    check_item(
        "release_app_path",
        "Running release app path",
        app_path_ok,
        next_action="Stop the running Caverno.app and rerun --m8-runtime-signoff.",
        details=app,
    ),
    check_item(
        "release_helper_path",
        "Running release helper path",
        helper_path_ok,
        next_action="Stop the running helper and rerun --m8-runtime-signoff.",
        details=helper,
    ),
    check_item(
        "permission_status",
        "Release helper permission status",
        permission_status_ok,
        next_action="Launch the release app and helper, then rerun --m8-runtime-signoff.",
    ),
    check_item(
        "accessibility",
        "Release helper Accessibility",
        accessibility_ok,
        next_action="Grant Accessibility to the release Caverno Computer Use helper.",
    ),
    check_item(
        "screen_capture",
        "Release app Screen & System Audio Recording",
        screen_capture_ok,
        next_action="Ask the user to grant Screen & System Audio Recording to the release Caverno.app.",
    ),
    check_item(
        "display_screenshot",
        "Release display screenshot",
        display_ok,
        next_action="Ask the user to grant Screen & System Audio Recording to the release Caverno.app, then rerun --m8-runtime-signoff manually.",
    ),
    check_item(
        "list_windows",
        "Release list windows",
        windows_ok,
        next_action="Launch the release app on the desktop, then rerun --m8-runtime-signoff.",
    ),
    check_item(
        "window_capture",
        "Release window capture",
        window_ok,
        next_action="Ask the user to grant Screen & System Audio Recording to the release Caverno.app, then rerun --m8-runtime-signoff manually.",
    ),
    check_item(
        "system_audio_resolved",
        "Release system audio readiness",
        audio_resolved,
        next_action="Ask the user to grant Screen & System Audio Recording to the release Caverno.app, then rerun --m8-runtime-signoff manually.",
    ),
]
runtime_status = "ready" if not runtime_blockers else "blocked"
runtime_readiness = {
    "status": runtime_status,
    "appPath": app.get("expectedPath"),
    "helperPath": helper.get("expectedPath"),
    "runningAppPath": app.get("runningPath"),
    "runningHelperPath": helper.get("runningPath"),
    "helperBundleIdentifier": helper.get("bundleIdentifier"),
    "requiredPermissions": [
        "Accessibility",
        "Screen & System Audio Recording",
    ],
    "permissionSummary": permission_summary,
    "runtimeProbeReportPath": str(probe_path),
    "nextAction": next_action(runtime_blockers),
}
runtime_gate = {
    "status": runtime_status,
    "blockers": runtime_blockers,
    "checks": checks,
    "appPath": app.get("expectedPath"),
    "helperPath": helper.get("expectedPath"),
    "runtimeProbeReportPath": str(probe_path),
    "nextAction": next_action(runtime_blockers),
}
report = {
    "schemaName": "macos_computer_use_release_runtime_signoff",
    "schemaVersion": 1,
    "generatedAt": datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
    "buildMode": "release",
    "skipReleaseBuild": artifact.get("skipReleaseBuild"),
    "ok": not runtime_blockers,
    "releaseBundle": artifact.get("releaseBundle"),
    "signingDiagnostics": artifact.get("signingDiagnostics"),
    "releaseSignoffGate": artifact_gate,
    "releaseRuntimeReadiness": runtime_readiness,
    "releaseRuntimeSignoffGate": runtime_gate,
    "releaseRuntimeProbe": redact_images(probe),
    "artifactReportPath": str(artifact_path),
    "runtimeProbeReportPath": str(probe_path),
    "reportPath": str(report_path),
}
encoded = json.dumps(report, indent=2)
report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(encoded)
print(f"CAVERNO_MACOS_COMPUTER_USE_SMOKE_JSON={encoded}")
if runtime_blockers:
    raise SystemExit(1)
PY
    fi
    echo "Release bundle XPC artifacts verified"
    ;;
  *)
    echo "Unknown build mode: ${BUILD_MODE}"
    exit 2
    ;;
esac
