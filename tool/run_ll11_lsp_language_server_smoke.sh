#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

REPORT_ROOT="${CAVERNO_LL11_LSP_SMOKE_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/ll11_lsp_language_server_smoke_$(date +%s)"
OUT_JSON="${RUN_DIR}/canary_summary.json"
OUT_MD="${RUN_DIR}/canary_summary.md"
WORK_ROOT="${RUN_DIR}/workspace"
LANGUAGES="${CAVERNO_LL11_LSP_SMOKE_LANGUAGES:-dart,typescript,python,swift}"
REQUIRE_LANGUAGE_SERVER="${CAVERNO_LL11_LSP_SMOKE_REQUIRE_LANGUAGE_SERVER:-0}"
DIAGNOSTIC_TIMEOUT_MS="${CAVERNO_LL11_LSP_SMOKE_DIAGNOSTIC_TIMEOUT_MS:-2500}"
SYMBOL_TIMEOUT_MS="${CAVERNO_LL11_LSP_SMOKE_SYMBOL_TIMEOUT_MS:-1500}"
DEFINITION_TIMEOUT_MS="${CAVERNO_LL11_LSP_SMOKE_DEFINITION_TIMEOUT_MS:-1500}"

echo "Running LL11 LSP language-server smoke"
echo "  Languages: ${LANGUAGES}"
echo "  Require language server: ${REQUIRE_LANGUAGE_SERVER}"
echo "  Report directory: ${RUN_DIR}"
echo "  Workspace root: ${WORK_ROOT}"

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"

ARGS=(
  run
  "${ROOT_DIR}/tool/ll11_lsp_language_server_smoke.dart"
  --languages
  "${LANGUAGES}"
  --diagnostic-timeout-ms
  "${DIAGNOSTIC_TIMEOUT_MS}"
  --symbol-timeout-ms
  "${SYMBOL_TIMEOUT_MS}"
  --definition-timeout-ms
  "${DEFINITION_TIMEOUT_MS}"
  --work-root
  "${WORK_ROOT}"
  --out-json
  "${OUT_JSON}"
  --out-md
  "${OUT_MD}"
  --command
  "tool/run_ll11_lsp_language_server_smoke.sh"
)

if [[ "${REQUIRE_LANGUAGE_SERVER}" == "1" ||
  "${REQUIRE_LANGUAGE_SERVER}" == "true" ||
  "${REQUIRE_LANGUAGE_SERVER}" == "yes" ]]; then
  ARGS+=(--require-language-server)
fi

dart "${ARGS[@]}"

echo "LL11 LSP smoke JSON: ${OUT_JSON}"
echo "LL11 LSP smoke Markdown: ${OUT_MD}"
