#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_LL10_DEPENDENCY_GROUNDING_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_DIR="${REPORT_ROOT}/ll10_dependency_grounding_release_gate_$(date +%s)"
GATE_JSON="${RUN_DIR}/release_gate.json"
GATE_MARKDOWN="${RUN_DIR}/release_gate.md"

echo "Running LL10 dependency grounding release gate"
echo "  Report directory: ${RUN_DIR}"

mkdir -p "${RUN_DIR}"
cd "${ROOT_DIR}"

dart run "${ROOT_DIR}/tool/ll10_dependency_grounding_release_gate.dart" \
  --out-json "${GATE_JSON}" \
  --out-md "${GATE_MARKDOWN}"

echo "LL10 dependency grounding release gate JSON: ${GATE_JSON}"
echo "LL10 dependency grounding release gate Markdown: ${GATE_MARKDOWN}"
