#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE_URL="${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL}"
MODEL="${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL}"
API_KEY="${CAVERNO_LLM_API_KEY:-no-key}"
MCP_CONFIG_PATH="${CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH:?Set CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH}"
BLOCK_COUNT="${CAVERNO_COLD_PATH_AB_BLOCK_COUNT:-3}"
POLL_LIMIT="${CAVERNO_COLD_PATH_AB_POLL_LIMIT:-120}"
ROUTER_ROOT="${BASE_URL%/}"
ROUTER_ROOT="${ROUTER_ROOT%/v1}"

if [[ ! "${BLOCK_COUNT}" =~ ^[1-9][0-9]*$ || "${BLOCK_COUNT}" -gt 10 ]]; then
  echo "CAVERNO_COLD_PATH_AB_BLOCK_COUNT must be between 1 and 10." >&2
  exit 64
fi
if [[ ! "${POLL_LIMIT}" =~ ^[1-9][0-9]*$ ]]; then
  echo "CAVERNO_COLD_PATH_AB_POLL_LIMIT must be a positive integer." >&2
  exit 64
fi
if [[ ! -f "${MCP_CONFIG_PATH}" ]]; then
  echo "MCP config not found: ${MCP_CONFIG_PATH}" >&2
  exit 66
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
initial_state="$(model_state)"
if [[ "${initial_state}" != "loaded" ]]; then
  echo "Refusing to run: ${MODEL} must start loaded, found ${initial_state:-missing}." >&2
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
  local warmup_count=0
  local warmup_mode=diagnostic
  if [[ "${arm}" == "unrelated" ]]; then
    warmup_count=1
    warmup_mode=unrelatedCompletion
  elif [[ "${arm}" == "diagnostic" ]]; then
    warmup_count=1
  fi

  reset_model
  echo "Running cold-path block ${block}, arm ${arm}"
  CAVERNO_LLM_BASE_URL="${BASE_URL}" \
  CAVERNO_LLM_MODEL="${MODEL}" \
  CAVERNO_LLM_API_KEY="${API_KEY}" \
  CAVERNO_EFFECTIVE_CONTEXT_MAX_TOKENS="${CAVERNO_EFFECTIVE_CONTEXT_MAX_TOKENS:-65536}" \
  CAVERNO_BENCHMARK_CANARY_NAME="ll39_cold_path_b${block}_${arm}" \
  CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH="${MCP_CONFIG_PATH}" \
  CAVERNO_BENCHMARK_CANARY_APP_TOOL_PROFILE=1 \
  CAVERNO_BENCHMARK_CANARY_PROBE_IDS=initial_harness_selection \
  CAVERNO_BENCHMARK_CANARY_REQUIRED_PROBE_IDS=initial_harness_selection \
  CAVERNO_BENCHMARK_CANARY_WARMUP_REPEAT_COUNT="${warmup_count}" \
  CAVERNO_BENCHMARK_CANARY_WARMUP_MODE="${warmup_mode}" \
  CAVERNO_BENCHMARK_CANARY_REPEAT_COUNT=1 \
    "${ROOT_DIR}/tool/with_live_llm_loopback.sh" -- \
      "${ROOT_DIR}/tool/run_live_llm_benchmark_canary.sh"
}

for ((block = 1; block <= BLOCK_COUNT; block += 1)); do
  case "$(((block - 1) % 3))" in
    0) arms=(none unrelated diagnostic) ;;
    1) arms=(unrelated diagnostic none) ;;
    2) arms=(diagnostic none unrelated) ;;
  esac
  for arm in "${arms[@]}"; do
    run_arm "${block}" "${arm}"
  done
done

echo "Cold-path A/B blocks completed successfully."
