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
echo "  MVP readiness JSON (final sign-off output): ${MVP_READINESS_JSON}"
echo "  MVP readiness Markdown (final sign-off output): ${MVP_READINESS_MD}"
echo "  Dry-run note: final readiness JSON and Markdown are not written by this preflight."
echo "  PR Review Summary: ${ARTIFACT_INDEX_MD}"
echo "  PR Review Artifacts: ${HANDOFF_MD}"
echo "  M15 action proposal: inspect the artifact index for the report-only command when M14 observe-only evidence is present"
echo "  M15 LLM review: inspect the artifact index for the report-only review command after M15 handoff is ready; blocked m15_llm_review_canary evidence stops final aggregation"
echo "  M16 approval packet: inspect the artifact index for the report-only approval packet command after M15 evidence is ready; blocked m16_approval_packet evidence stops final aggregation"
echo "  M17 execution rehearsal: inspect the artifact index for the report-only rehearsal command after M16 approval is approved; blocked m17_execution_rehearsal evidence stops final aggregation"
echo "  M18 execution handoff: inspect the artifact index for the report-only handoff command after M17 rehearsal is ready; blocked m18_execution_handoff evidence stops final aggregation"
echo "  M20 execution result intake: inspect the artifact index for the report-only result intake command after the user completes the M18-guided runtime step; blocked m20_execution_result_intake evidence stops final aggregation"
echo "  M22 post-action review: inspect the artifact index for the report-only post-action review command after M20 is ready; blocked m22_post_action_review evidence stops final aggregation"
echo "  M23 cycle outcome handoff: inspect the artifact index for the report-only cycle outcome handoff command after M22 is ready; blocked m23_cycle_outcome_handoff evidence stops final aggregation"
echo "  M25 next-cycle seed handoff: inspect the artifact index for the report-only next-cycle seed command after M23 restarts the cycle; blocked m25_next_cycle_seed_handoff evidence stops final aggregation"
echo "  M26 observe restart packet: inspect the artifact index for the report-only M14 observe restart packet command after M25 is ready; blocked m26_observe_restart_packet evidence stops final aggregation"
echo "  M27 screenshot request handoff: inspect the artifact index for the report-only manual screenshot request command after M26 is ready; blocked m27_screenshot_request_handoff evidence stops final aggregation"
echo "  M28 screenshot evidence intake: inspect the artifact index for the report-only screenshot evidence intake command after M27 is ready and the user provides a screenshot; blocked m28_screenshot_evidence_intake evidence stops final aggregation"
echo "  M29 observe canary run packet: inspect the artifact index for the report-only M14 observe run packet command after M28 is ready; blocked m29_observe_canary_run_packet evidence stops final aggregation"
echo "  M30 observe result intake: inspect the artifact index for the report-only M14 result intake command after the user-produced M14 observe summary is ready; blocked m30_observe_result_intake evidence stops final aggregation"
echo "Expected final input paths:"
echo "  Manual TCC: macos_computer_use_manual_tcc_<timestamp>/manual_tcc_report_summary.json"
echo "  Desktop action: macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json"
echo "  MVP fixture LLM: macos_computer_use_mvp_fixture_llm_canary_<timestamp>/canary_summary.json"
echo "MVP readiness preflight complete"
