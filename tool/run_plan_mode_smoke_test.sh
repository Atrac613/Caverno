#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DEVICE="${CAVERNO_PLAN_MODE_DEVICE:-macos}"
REPORTER="${CAVERNO_PLAN_MODE_REPORTER:-compact}"
SCENARIOS="${CAVERNO_PLAN_MODE_SCENARIOS:-}"
TAGS="${CAVERNO_PLAN_MODE_TAGS:-smoke}"
HEADLESS="${CAVERNO_PLAN_MODE_HEADLESS:-auto}"

echo "Running Plan mode smoke scenarios"
echo "  Device: ${DEVICE}"
echo "  Reporter: ${REPORTER}"
if [[ -n "${SCENARIOS}" ]]; then
  echo "  Scenarios: ${SCENARIOS}"
fi
if [[ -n "${TAGS}" ]]; then
  echo "  Tags: ${TAGS}"
fi

cd "${ROOT_DIR}"

if [[ "${DEVICE}" == "linux" && "${HEADLESS}" != "0" ]]; then
  if command -v xvfb-run >/dev/null 2>&1; then
    CAVERNO_PLAN_MODE_DEVICE="${DEVICE}" \
    CAVERNO_PLAN_MODE_SCENARIOS="${SCENARIOS}" \
    CAVERNO_PLAN_MODE_TAGS="${TAGS}" \
    xvfb-run -a flutter test integration_test/plan_mode_scenario_test.dart -d "${DEVICE}" -r "${REPORTER}"
  elif [[ "${HEADLESS}" == "auto" ]]; then
    CAVERNO_PLAN_MODE_DEVICE="${DEVICE}" \
    CAVERNO_PLAN_MODE_SCENARIOS="${SCENARIOS}" \
    CAVERNO_PLAN_MODE_TAGS="${TAGS}" \
    flutter test integration_test/plan_mode_scenario_test.dart -d "${DEVICE}" -r "${REPORTER}"
  else
    echo "xvfb-run is required for Linux headless smoke runs."
    exit 1
  fi
else
  CAVERNO_PLAN_MODE_DEVICE="${DEVICE}" \
  CAVERNO_PLAN_MODE_SCENARIOS="${SCENARIOS}" \
  CAVERNO_PLAN_MODE_TAGS="${TAGS}" \
  flutter test integration_test/plan_mode_scenario_test.dart -d "${DEVICE}" -r "${REPORTER}"
fi
