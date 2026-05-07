#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_MVP_PREFLIGHT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_mvp_readiness_preflight.sh [options]

Options:
  --root PATH  Report root directory.
  --help       Show this help.

This report-only preflight reads existing MVP readiness artifacts, regenerates
the artifact index, and writes an MVP sign-off dry-run handoff. It never grants
TCC, edits TCC, operates System Settings, launches apps, moves the pointer,
clicks, types, records audio, or runs desktop actions.
USAGE
}

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
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

mkdir -p "${REPORT_ROOT}"

ARTIFACT_INDEX_JSON="${REPORT_ROOT}/macos_computer_use_readiness_artifact_index.json"
ARTIFACT_INDEX_MD="${REPORT_ROOT}/macos_computer_use_readiness_artifact_index.md"
HANDOFF_MD="${REPORT_ROOT}/macos_computer_use_mvp_handoff.md"
MVP_READINESS_JSON="${REPORT_ROOT}/macos_computer_use_mvp_readiness.json"
MVP_READINESS_MD="${REPORT_ROOT}/macos_computer_use_mvp_readiness.md"

echo "Running macOS Computer Use MVP readiness preflight"
echo "  Report root: ${REPORT_ROOT}"
echo "  Boundary: report-only, no TCC, no System Settings, no desktop actions"

(
  cd "${ROOT_DIR}"
  dart run tool/macos_computer_use_readiness_artifact_index.dart \
    --root "${REPORT_ROOT}"
)

bash "${ROOT_DIR}/tool/run_macos_computer_use_mvp_signoff.sh" \
  --root "${REPORT_ROOT}" \
  --dry-run \
  --output-json "${MVP_READINESS_JSON}" \
  --output-md "${MVP_READINESS_MD}" \
  --handoff-md "${HANDOFF_MD}"

echo "MVP readiness preflight outputs:"
echo "  Artifact index JSON: ${ARTIFACT_INDEX_JSON}"
echo "  Artifact index Markdown: ${ARTIFACT_INDEX_MD}"
echo "  MVP handoff Markdown: ${HANDOFF_MD}"
echo "  MVP readiness JSON: ${MVP_READINESS_JSON}"
echo "  MVP readiness Markdown: ${MVP_READINESS_MD}"
echo "  PR Review Summary: ${ARTIFACT_INDEX_MD}"
echo "  PR Review Artifacts: ${HANDOFF_MD}"
echo "MVP readiness preflight complete"
