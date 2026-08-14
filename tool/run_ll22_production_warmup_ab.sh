#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE_URL="${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL}"
MODEL="${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL}"
BLOCK_COUNT="${CAVERNO_LL22_AB_BLOCK_COUNT:-3}"
POLL_LIMIT="${CAVERNO_LL22_AB_POLL_LIMIT:-120}"
ROUTER_ROOT="${BASE_URL%/}"
ROUTER_ROOT="${ROUTER_ROOT%/v1}"

if [[ ! "${BLOCK_COUNT}" =~ ^[1-9][0-9]*$ || "${BLOCK_COUNT}" -gt 10 ]]; then
  echo "CAVERNO_LL22_AB_BLOCK_COUNT must be between 1 and 10." >&2
  exit 64
fi
if [[ ! "${POLL_LIMIT}" =~ ^[1-9][0-9]*$ ]]; then
  echo "CAVERNO_LL22_AB_POLL_LIMIT must be a positive integer." >&2
  exit 64
fi

model_state() {
  curl -fsS --max-time 10 "${ROUTER_ROOT}/v1/models" |
    jq -r --arg model "${MODEL}" \
      '.data[] | select(.id == $model) | .status.value' |
    head -n 1
}

wait_for_state() {
  local expected="$1"
  local attempt state
  for ((attempt = 1; attempt <= POLL_LIMIT; attempt += 1)); do
    state="$(model_state)"
    if [[ "${state}" == "${expected}" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for ${MODEL} to become ${expected}." >&2
  return 1
}

lifecycle_action() {
  local action="$1"
  local payload
  payload="$(jq -nc --arg model "${MODEL}" '{model: $model}')"
  curl -fsS --max-time 30 \
    -H 'content-type: application/json' \
    -d "${payload}" \
    "${ROUTER_ROOT}/models/${action}" >/dev/null
  wait_for_state "${action}ed"
}

restore_model() {
  local state
  state="$(model_state 2>/dev/null || true)"
  if [[ "${state}" != "loaded" ]]; then
    echo "Restoring ${MODEL} to loaded state"
    lifecycle_action load || true
  fi
}

if [[ "$(model_state)" != "loaded" ]]; then
  echo "Refusing to run: ${MODEL} must start loaded." >&2
  exit 69
fi

trap restore_model EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

reset_model() {
  echo "Resetting ${MODEL} to a fresh loaded state"
  lifecycle_action unload
  lifecycle_action load
}

run_arm() {
  local block="$1"
  local arm="$2"
  reset_model
  echo "Running LL22 block ${block}, arm ${arm}"
  CAVERNO_LL22_WARMUP_ARM="${arm}" \
  CAVERNO_LL22_REPORT_ROOT="${CAVERNO_LL22_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports/ll22_production_warmup_ab}" \
    "${ROOT_DIR}/tool/with_live_llm_loopback.sh" -- \
      "${ROOT_DIR}/tool/run_ll22_production_warmup_canary.sh"
}

for ((block = 1; block <= BLOCK_COUNT; block += 1)); do
  if ((block % 2 == 1)); then
    arms=(cold warm)
  else
    arms=(warm cold)
  fi
  for arm in "${arms[@]}"; do
    run_arm "${block}" "${arm}"
  done
done

echo "LL22 production warm-up A/B completed successfully."
