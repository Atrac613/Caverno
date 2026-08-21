#!/usr/bin/env bash

set -euo pipefail

print_usage() {
  printf '%s\n' \
    'Usage: tool/with_live_llm_loopback.sh -- COMMAND [ARGUMENT ...]' \
    '' \
    'Run a live LLM canary through managed ephemeral IPv4 loopback relays.' \
    '' \
    'Required environment:' \
    '  CAVERNO_LLM_BASE_URL  Origin HTTP endpoint, including the API path.' \
    '' \
    'The child receives CAVERNO_LLM_ORIGIN_BASE_URL,' \
    'CAVERNO_LLM_EFFECTIVE_BASE_URL, CAVERNO_LLM_RELAY_MODE=loopbackTcp,' \
    'and a rewritten CAVERNO_LLM_BASE_URL. HTTPS is intentionally rejected.' \
    'When CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH is set, HTTP MCP' \
    'endpoints are relayed and the child receives a rewritten temporary config.' \
    '' \
    'Runbook: docs/live_llm_canary_agent_runbook.md'
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  print_usage
  exit 0
fi

if [[ "${1:-}" != "--" || "$#" -lt 2 ]]; then
  print_usage >&2
  exit 64
fi
shift

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL to the HTTP LAN endpoint before starting the loopback relay.}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ORIGIN_BASE_URL="${CAVERNO_LLM_BASE_URL}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/caverno-live-llm-loopback.XXXXXX")"
READY_FILE="${WORK_DIR}/ready"
RELAY_LOG="${WORK_DIR}/relay.log"
RELAY_PID=""
MCP_READY_FILE="${WORK_DIR}/mcp-ready"
MCP_RELAY_LOG="${WORK_DIR}/mcp-relay.log"
MCP_EFFECTIVE_CONFIG="${WORK_DIR}/mcp-config.json"
MCP_RELAY_PID=""

if [[ -n "${CAVERNO_DART_EXECUTABLE:-}" ]]; then
  DART_COMMAND=("${CAVERNO_DART_EXECUTABLE}")
elif command -v fvm >/dev/null 2>&1 && { [[ -f "${ROOT_DIR}/.fvmrc" ]] || [[ -d "${ROOT_DIR}/.fvm" ]]; }; then
  DART_COMMAND=(fvm dart)
else
  DART_COMMAND=(dart)
fi

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -n "${RELAY_PID}" ]] && kill -0 "${RELAY_PID}" 2>/dev/null; then
    kill "${RELAY_PID}" 2>/dev/null || true
    wait "${RELAY_PID}" 2>/dev/null || true
  fi
  if [[ -n "${MCP_RELAY_PID}" ]] && kill -0 "${MCP_RELAY_PID}" 2>/dev/null; then
    kill "${MCP_RELAY_PID}" 2>/dev/null || true
    wait "${MCP_RELAY_PID}" 2>/dev/null || true
  fi
  rm -f "${READY_FILE}" "${RELAY_LOG}" "${MCP_READY_FILE}" "${MCP_RELAY_LOG}" "${MCP_EFFECTIVE_CONFIG}"
  rmdir "${WORK_DIR}" 2>/dev/null || true
  exit "${status}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "${ROOT_DIR}"
"${DART_COMMAND[@]}" --disable-dart-dev tool/live_llm_loopback_relay.dart \
  --base-url "${ORIGIN_BASE_URL}" \
  --ready-file "${READY_FILE}" \
  >"${RELAY_LOG}" 2>&1 &
RELAY_PID=$!

for _ in {1..200}; do
  if [[ -s "${READY_FILE}" ]]; then
    break
  fi
  if ! kill -0 "${RELAY_PID}" 2>/dev/null; then
    echo "Live LLM loopback relay exited before becoming ready." >&2
    sed -n '1,120p' "${RELAY_LOG}" >&2
    exit 70
  fi
  sleep 0.05
done

if [[ ! -s "${READY_FILE}" ]]; then
  echo "Timed out waiting for the live LLM loopback relay." >&2
  sed -n '1,120p' "${RELAY_LOG}" >&2
  exit 70
fi

IFS= read -r EFFECTIVE_BASE_URL <"${READY_FILE}"
export CAVERNO_LLM_ORIGIN_BASE_URL="${ORIGIN_BASE_URL}"
export CAVERNO_LLM_EFFECTIVE_BASE_URL="${EFFECTIVE_BASE_URL}"
export CAVERNO_LLM_RELAY_MODE="loopbackTcp"
export CAVERNO_LLM_BASE_URL="${EFFECTIVE_BASE_URL}"

if [[ -n "${CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH:-}" ]]; then
  MCP_ORIGIN_CONFIG="${CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH}"
  "${DART_COMMAND[@]}" --disable-dart-dev tool/live_mcp_loopback_relay.dart \
    --config "${MCP_ORIGIN_CONFIG}" \
    --output-config "${MCP_EFFECTIVE_CONFIG}" \
    --ready-file "${MCP_READY_FILE}" \
    >"${MCP_RELAY_LOG}" 2>&1 &
  MCP_RELAY_PID=$!

  for _ in {1..200}; do
    if [[ -s "${MCP_READY_FILE}" && -s "${MCP_EFFECTIVE_CONFIG}" ]]; then
      break
    fi
    if ! kill -0 "${MCP_RELAY_PID}" 2>/dev/null; then
      echo "Live MCP loopback relay exited before becoming ready." >&2
      sed -n '1,120p' "${MCP_RELAY_LOG}" >&2
      exit 70
    fi
    sleep 0.05
  done

  if [[ ! -s "${MCP_READY_FILE}" || ! -s "${MCP_EFFECTIVE_CONFIG}" ]]; then
    echo "Timed out waiting for the live MCP loopback relay." >&2
    sed -n '1,120p' "${MCP_RELAY_LOG}" >&2
    exit 70
  fi

  chmod 600 "${MCP_EFFECTIVE_CONFIG}"
  IFS= read -r MCP_RELAY_COUNT <"${MCP_READY_FILE}"
  export CAVERNO_BENCHMARK_CANARY_MCP_ORIGIN_CONFIG_PATH="${MCP_ORIGIN_CONFIG}"
  export CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH="${MCP_EFFECTIVE_CONFIG}"
  export CAVERNO_BENCHMARK_CANARY_MCP_RELAY_MODE="loopbackTcp"
fi

echo "Running command through the Caverno live LLM loopback relay"
echo "  Origin base URL: ${CAVERNO_LLM_ORIGIN_BASE_URL}"
echo "  Effective base URL: ${CAVERNO_LLM_EFFECTIVE_BASE_URL}"
echo "  Relay mode: ${CAVERNO_LLM_RELAY_MODE}"
if [[ -n "${MCP_RELAY_PID}" ]]; then
  echo "  MCP relay mode: ${CAVERNO_BENCHMARK_CANARY_MCP_RELAY_MODE} (${MCP_RELAY_COUNT} HTTP endpoint(s))"
fi

set +e
"$@"
COMMAND_STATUS=$?
set -e

# A relay that dies mid-run leaves the child with unexplained connection
# resets, so hand over the reason rather than deleting it during cleanup.
if [[ "${COMMAND_STATUS}" -ne 0 && -s "${RELAY_LOG}" ]]; then
  echo "Live LLM loopback relay log:" >&2
  sed -n '1,120p' "${RELAY_LOG}" >&2
fi

exit "${COMMAND_STATUS}"
