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

finish() {
  local exit_code=$?
  set +e
  print_m4_signoff_summary
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
echo "  Register XPC agent: ${REGISTER_XPC_AGENT}"
echo "  Cleanup XPC agent: ${CLEANUP_XPC_AGENT}"
echo "  Report: ${REPORT_PATH}"

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
    flutter build macos --release "${COMMON_DART_DEFINES[@]}"
    RELEASE_APP="${ROOT_DIR}/build/macos/Build/Products/Release/Caverno.app"
    RELEASE_HELPER="${RELEASE_APP}/Contents/Helpers/Caverno Computer Use.app"
    RELEASE_AGENT="${RELEASE_APP}/Contents/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist"
    test -d "${RELEASE_APP}"
    test -d "${RELEASE_HELPER}"
    test -f "${RELEASE_AGENT}"
    /usr/bin/plutil -lint "${RELEASE_AGENT}"
    /usr/libexec/PlistBuddy \
      -c "Print :MachServices:com.noguwo.apps.caverno.computer-use.xpc" \
      "${RELEASE_AGENT}"
    /usr/bin/codesign --verify --deep --strict "${RELEASE_APP}"
    RELEASE_REPORT_PATH="${REPORT_PATH}" \
    RELEASE_APP="${RELEASE_APP}" \
    RELEASE_HELPER="${RELEASE_HELPER}" \
    RELEASE_AGENT="${RELEASE_AGENT}" \
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


def run_command(args):
    completed = subprocess.run(args, capture_output=True, text=True, check=False)
    return {
        "exitCode": completed.returncode,
        "stdout": completed.stdout.strip(),
        "stderr": completed.stderr.strip(),
    }


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


report_path = os.environ["RELEASE_REPORT_PATH"]
app = os.environ["RELEASE_APP"]
helper = os.environ["RELEASE_HELPER"]
agent = os.environ["RELEASE_AGENT"]
app_signing = codesign_diagnostics(app, "app")
helper_signing = codesign_diagnostics(helper, "helper")
signing_blockers = [
    f"app:{blocker}" for blocker in app_signing["launchConstraintBlockers"]
] + [
    f"helper:{blocker}" for blocker in helper_signing["launchConstraintBlockers"]
]
report = {
    "schemaName": "macos_computer_use_release_bundle_smoke",
    "schemaVersion": 1,
    "generatedAt": datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
    "buildMode": "release",
    "strict": os.environ["STRICT_DART"] == "true",
    "strictXpc": os.environ["STRICT_XPC_DART"] == "true",
    "m4Signoff": os.environ["M4_SIGNOFF_DART"] == "true",
    "registerXpcAgent": os.environ["REGISTER_XPC_AGENT_DART"] == "true",
    "cleanupXpcAgent": os.environ["CLEANUP_XPC_AGENT_DART"] == "true",
    "ok": True,
    "releaseBundle": {
        "appExists": os.path.isdir(app),
        "helperExists": os.path.isdir(helper),
        "launchAgentExists": os.path.isfile(agent),
        "launchAgentPlistValid": True,
        "machServiceDeclared": True,
        "codesignVerified": True,
        "appPath": app,
        "helperPath": helper,
        "launchAgentPath": agent,
        "xpcServiceName": "com.noguwo.apps.caverno.computer-use.xpc",
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
    "reportPath": report_path,
}
encoded = json.dumps(report, indent=2)
if report_path:
    path = Path(report_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(encoded)
print(f"CAVERNO_MACOS_COMPUTER_USE_SMOKE_JSON={encoded}")
PY
    echo "Release bundle XPC artifacts verified"
    ;;
  *)
    echo "Unknown build mode: ${BUILD_MODE}"
    exit 2
    ;;
esac
