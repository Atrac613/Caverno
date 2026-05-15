#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M51_PRODUCTION_LAUNCH_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m51_production_launch_gate_${RUN_ID}"
OUTPUT_JSON="${RUN_DIR}/macos_computer_use_m51_production_launch_gate.json"
OUTPUT_MD="${RUN_DIR}/macos_computer_use_m51_production_launch_gate.md"
LAUNCH_CHECKLIST=""
RELEASE_ARTIFACT_REPORT=""
RELEASE_PACKAGING_REPORT=""
MANUAL_TCC_REPORT=""
M46_ELEMENT_GROUNDED_LLM_EVAL=""
M49_PRIVACY_AUDIT_RELEASE_PACK=""
M50_SIGNED_BETA_GATE=""
DIAGNOSTICS=""
EXIT_POLICY="strict"
WRITE_TEMPLATE="no"
TEMPLATE_PATH=""

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m51_production_launch_gate.sh [options]

Options:
  --root PATH                         Report root directory.
  --launch-checklist PATH             M51 launch checklist JSON.
  --release-artifact-report PATH      M7 release artifact sign-off JSON.
  --release-packaging-report PATH     M33 release packaging JSON.
  --manual-tcc-report PATH            Manual TCC summary or runtime sign-off JSON.
  --m46-element-grounded-llm-eval PATH
                                      M46 element-grounded canary_summary.json.
  --m49-privacy-audit-release-pack PATH
                                      M49 privacy_audit_release_pack.json.
  --m50-signed-beta-gate PATH         M50 signed beta gate JSON.
  --diagnostics PATH                  Computer Use diagnostics JSON.
  --output-json PATH                  Output summary JSON path.
  --output-md PATH                    Output summary Markdown path.
  --write-template [PATH]             Write a launch checklist template and exit.
  --report-only                       Always exit 0 after writing the report.
  --strict                            Exit non-zero when any M51 gate is blocked.
  --help                              Show this help.

M51 is report-only. It reads signed artifact, notarization, helper identity,
manual TCC runbook, element-grounded LLM, privacy/audit release pack, signed
beta, emergency stop, privacy copy, support diagnostics, and production launch
boundary evidence. It performs no desktop actions and does not grant TCC,
notarize, open System Settings, capture screens, move the pointer, click, type,
submit, post, purchase, export raw payloads, or operate desktop apps.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --launch-checklist)
      require_value "$@"
      LAUNCH_CHECKLIST="$2"
      shift 2
      ;;
    --release-artifact-report)
      require_value "$@"
      RELEASE_ARTIFACT_REPORT="$2"
      shift 2
      ;;
    --release-packaging-report)
      require_value "$@"
      RELEASE_PACKAGING_REPORT="$2"
      shift 2
      ;;
    --manual-tcc-report)
      require_value "$@"
      MANUAL_TCC_REPORT="$2"
      shift 2
      ;;
    --m46-element-grounded-llm-eval)
      require_value "$@"
      M46_ELEMENT_GROUNDED_LLM_EVAL="$2"
      shift 2
      ;;
    --m49-privacy-audit-release-pack)
      require_value "$@"
      M49_PRIVACY_AUDIT_RELEASE_PACK="$2"
      shift 2
      ;;
    --m50-signed-beta-gate)
      require_value "$@"
      M50_SIGNED_BETA_GATE="$2"
      shift 2
      ;;
    --diagnostics)
      require_value "$@"
      DIAGNOSTICS="$2"
      shift 2
      ;;
    --output-json)
      require_value "$@"
      OUTPUT_JSON="$2"
      shift 2
      ;;
    --output-md)
      require_value "$@"
      OUTPUT_MD="$2"
      shift 2
      ;;
    --write-template)
      WRITE_TEMPLATE="yes"
      if [[ $# -ge 2 && -n "${2:-}" && "${2}" != --* ]]; then
        TEMPLATE_PATH="$2"
        shift 2
      else
        shift 1
      fi
      ;;
    --report-only)
      EXIT_POLICY="report-only"
      shift 1
      ;;
    --strict)
      EXIT_POLICY="strict"
      shift 1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 64
      ;;
  esac
done

mkdir -p "${RUN_DIR}"

args=(
  "run"
  "tool/macos_computer_use_m51_production_launch_gate.dart"
  "--root"
  "${REPORT_ROOT}"
)

if [[ "${WRITE_TEMPLATE}" == "yes" ]]; then
  args+=("--write-template")
  if [[ -n "${TEMPLATE_PATH}" ]]; then
    args+=("${TEMPLATE_PATH}")
  fi
  echo "Writing M51 launch checklist template"
  echo "  Report root: ${REPORT_ROOT}"
  dart "${args[@]}"
  exit $?
fi

args+=(
  "--output-json"
  "${OUTPUT_JSON}"
  "--output-md"
  "${OUTPUT_MD}"
  "--exit-policy"
  "${EXIT_POLICY}"
)

if [[ -n "${LAUNCH_CHECKLIST}" ]]; then
  args+=("--launch-checklist" "${LAUNCH_CHECKLIST}")
fi
if [[ -n "${RELEASE_ARTIFACT_REPORT}" ]]; then
  args+=("--release-artifact-report" "${RELEASE_ARTIFACT_REPORT}")
fi
if [[ -n "${RELEASE_PACKAGING_REPORT}" ]]; then
  args+=("--release-packaging-report" "${RELEASE_PACKAGING_REPORT}")
fi
if [[ -n "${MANUAL_TCC_REPORT}" ]]; then
  args+=("--manual-tcc-report" "${MANUAL_TCC_REPORT}")
fi
if [[ -n "${M46_ELEMENT_GROUNDED_LLM_EVAL}" ]]; then
  args+=("--m46-element-grounded-llm-eval" "${M46_ELEMENT_GROUNDED_LLM_EVAL}")
fi
if [[ -n "${M49_PRIVACY_AUDIT_RELEASE_PACK}" ]]; then
  args+=("--m49-privacy-audit-release-pack" "${M49_PRIVACY_AUDIT_RELEASE_PACK}")
fi
if [[ -n "${M50_SIGNED_BETA_GATE}" ]]; then
  args+=("--m50-signed-beta-gate" "${M50_SIGNED_BETA_GATE}")
fi
if [[ -n "${DIAGNOSTICS}" ]]; then
  args+=("--diagnostics" "${DIAGNOSTICS}")
fi

echo "Running macOS Computer Use M51 production launch gate"
echo "  Report root: ${REPORT_ROOT}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
echo "  Boundary: report-only, user-operated notarization, TCC, and desktop actions"

dart "${args[@]}"
