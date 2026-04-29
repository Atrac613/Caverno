#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRESET="ci"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_READINESS_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
MANUAL_TCC_REPORT="${CAVERNO_MACOS_COMPUTER_USE_MANUAL_TCC_REPORT:-}"
REFRESH_SAFE_INPUTS=1
REFRESH_LLM_CANARY=0
LLM_CANARY_PROMPT="${CAVERNO_MACOS_COMPUTER_USE_LLM_CANARY_PROMPT:-Create a Python CLI script that pings a specific host.}"
OUTPUT_JSON=""
OUTPUT_MD=""
EXTRA_ARGS=()

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_release_readiness.sh [--ci|--signoff] [options]

Options:
  --ci                     Refresh non-TCC inputs and use CI exit policy.
  --signoff                Use strict exit policy for release sign-off.
  --root PATH              Report root directory.
  --manual-tcc-report PATH User-produced M8 runtime report or summary.
  --no-refresh             Do not refresh M7 or Computer Use canary history.
  --refresh-llm-canary     Run the LLM canary only when CAVERNO_LLM_* is set.
  --llm-canary-prompt TEXT Override the LLM canary prompt.
  --output-json PATH       Override readiness JSON output path.
  --output-md PATH         Override readiness Markdown output path.
  --                       Pass remaining args to the Dart readiness CLI.

This wrapper never runs M8 runtime sign-off or operates macOS TCC.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ci)
      PRESET="ci"
      shift
      ;;
    --signoff|--strict)
      PRESET="signoff"
      shift
      ;;
    --root)
      if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
        echo "--root requires a value." >&2
        exit 64
      fi
      REPORT_ROOT="$2"
      shift 2
      ;;
    --manual-tcc-report)
      if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
        echo "--manual-tcc-report requires a value." >&2
        exit 64
      fi
      MANUAL_TCC_REPORT="$2"
      shift 2
      ;;
    --no-refresh)
      REFRESH_SAFE_INPUTS=0
      shift
      ;;
    --refresh-llm-canary)
      REFRESH_LLM_CANARY=1
      shift
      ;;
    --llm-canary-prompt)
      if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
        echo "--llm-canary-prompt requires a value." >&2
        exit 64
      fi
      LLM_CANARY_PROMPT="$2"
      shift 2
      ;;
    --output-json)
      if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
        echo "--output-json requires a value." >&2
        exit 64
      fi
      OUTPUT_JSON="$2"
      shift 2
      ;;
    --output-md)
      if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
        echo "--output-md requires a value." >&2
        exit 64
      fi
      OUTPUT_MD="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    --)
      shift
      EXTRA_ARGS+=("$@")
      break
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

case "${PRESET}" in
  ci)
    EXIT_POLICY="ci"
    ;;
  signoff)
    EXIT_POLICY="strict"
    ;;
  *)
    echo "Unknown preset: ${PRESET}" >&2
    exit 64
    ;;
esac

if [[ -z "${OUTPUT_JSON}" ]]; then
  OUTPUT_JSON="${REPORT_ROOT}/macos_computer_use_release_readiness_${PRESET}.json"
fi

if [[ -z "${OUTPUT_MD}" ]]; then
  OUTPUT_MD="${REPORT_ROOT}/macos_computer_use_release_readiness_${PRESET}.md"
fi

COMMAND=(
  dart run tool/macos_computer_use_release_readiness.dart
  --root "${REPORT_ROOT}"
  --exit-policy "${EXIT_POLICY}"
  --output-json "${OUTPUT_JSON}"
  --output-md "${OUTPUT_MD}"
)

if [[ "${REFRESH_SAFE_INPUTS}" == "1" ]]; then
  COMMAND+=(--refresh-safe-inputs)
fi

if [[ -n "${MANUAL_TCC_REPORT}" ]]; then
  COMMAND+=(--manual-tcc-report "${MANUAL_TCC_REPORT}")
fi

if [[ "${#EXTRA_ARGS[@]}" -gt 0 ]]; then
  COMMAND+=("${EXTRA_ARGS[@]}")
fi

echo "Running macOS Computer Use release readiness"
echo "  Preset: ${PRESET}"
echo "  Report root: ${REPORT_ROOT}"
echo "  Refresh safe inputs: ${REFRESH_SAFE_INPUTS}"
echo "  Refresh LLM canary: ${REFRESH_LLM_CANARY}"
echo "  Exit policy: ${EXIT_POLICY}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
if [[ -n "${MANUAL_TCC_REPORT}" ]]; then
  echo "  Manual TCC report: ${MANUAL_TCC_REPORT}"
else
  echo "  Manual TCC report: discovery only"
fi
echo "  TCC boundary: user-operated manual verification only"

cd "${ROOT_DIR}"

if [[ "${REFRESH_LLM_CANARY}" == "1" ]]; then
  if [[ -n "${CAVERNO_LLM_BASE_URL:-}" && -n "${CAVERNO_LLM_API_KEY:-}" && -n "${CAVERNO_LLM_MODEL:-}" ]]; then
    echo "Refreshing LLM canary"
    CAVERNO_PLAN_MODE_REPEAT_COUNT="${CAVERNO_PLAN_MODE_REPEAT_COUNT:-1}" \
      bash tool/run_plan_mode_ping_cli_live_canary.sh "${LLM_CANARY_PROMPT}"
  else
    echo "Skipping LLM canary refresh because CAVERNO_LLM_BASE_URL, CAVERNO_LLM_API_KEY, or CAVERNO_LLM_MODEL is not set."
    echo "Existing LLM canary summaries will be discovered instead."
  fi
fi

set +e
"${COMMAND[@]}"
readiness_exit=$?
set -e

dart run tool/macos_computer_use_readiness_artifact_index.dart --root "${REPORT_ROOT}"

exit "${readiness_exit}"
