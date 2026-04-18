#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT="${1:-${CAVERNO_PLAN_MODE_USER_PROMPT:-}}"

if [[ -z "${PROMPT}" ]]; then
  echo "Pass the target user prompt as the first argument or set CAVERNO_PLAN_MODE_USER_PROMPT."
  exit 1
fi

cd "${ROOT_DIR}"

CAVERNO_PLAN_MODE_USER_PROMPT="${PROMPT}" \
CAVERNO_PLAN_MODE_SCENARIOS="live_ping_cli_completion" \
CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS="1" \
"${ROOT_DIR}/tool/run_plan_mode_live_test.sh"
