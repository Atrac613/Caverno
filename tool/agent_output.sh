#!/usr/bin/env bash
# Shared bounded-output support for repository-owned long-running commands.
#
# This file intentionally exposes functions rather than a generic command-line
# runner. Each owning script remains responsible for interpreting its command's
# success, failure markers, and evidence artifacts.

_agent_output_restore_trap() {
  local saved_trap="$1"
  local signal_name="$2"
  if [[ -n "${saved_trap}" ]]; then
    eval "${saved_trap}"
  else
    trap - "${signal_name}"
  fi
}

_agent_output_stop_pid() {
  local process_id="$1"
  if [[ "${process_id}" -gt 0 ]]; then
    kill -TERM "${process_id}" 2>/dev/null || true
  fi
}

agent_output_run() {
  local log_path="$1"
  local label="$2"
  local output_mode="$3"
  shift 3

  local heartbeat_seconds="${CAVERNO_AGENT_OUTPUT_HEARTBEAT_SECONDS:-30}"
  local failure_lines="${CAVERNO_AGENT_OUTPUT_FAILURE_LINES:-40}"

  case "${output_mode}" in
    quiet|raw)
      ;;
    *)
      echo "Unsupported agent output mode: ${output_mode}" >&2
      return 64
      ;;
  esac
  if ! [[ "${heartbeat_seconds}" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
    [[ "${heartbeat_seconds}" == "0" || "${heartbeat_seconds}" == "0.0" ]]; then
    echo "CAVERNO_AGENT_OUTPUT_HEARTBEAT_SECONDS must be positive." >&2
    return 64
  fi
  if ! [[ "${failure_lines}" =~ ^[1-9][0-9]*$ ]]; then
    echo "CAVERNO_AGENT_OUTPUT_FAILURE_LINES must be a positive integer." >&2
    return 64
  fi

  mkdir -p "$(dirname "${log_path}")"
  local previous_umask
  previous_umask="$(umask)"
  umask 077
  : >"${log_path}"
  chmod 600 "${log_path}"
  echo "Running ${label}"
  echo "  Full log: ${log_path}"

  local command_status=0
  if [[ "${output_mode}" == "raw" ]]; then
    local pipeline_status=()
    if "$@" 2>&1 | tee "${log_path}"; then
      command_status=0
    else
      pipeline_status=("${PIPESTATUS[@]}")
      command_status="${pipeline_status[0]}"
      if [[ "${command_status}" -eq 0 && "${pipeline_status[1]}" -ne 0 ]]; then
        command_status="${pipeline_status[1]}"
      fi
    fi
  else
    local command_pid=0
    local heartbeat_pid=0
    local interrupted_status=0
    local helper_dir
    helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local previous_int_trap
    local previous_term_trap
    previous_int_trap="$(trap -p INT || true)"
    previous_term_trap="$(trap -p TERM || true)"
    # Non-interactive shells start asynchronous children with SIGINT ignored,
    # so translate an interrupt into SIGTERM while preserving exit status 130.
    trap 'interrupted_status=130; _agent_output_stop_pid "${command_pid}"; _agent_output_stop_pid "${heartbeat_pid}"' INT
    trap 'interrupted_status=143; _agent_output_stop_pid "${command_pid}"; _agent_output_stop_pid "${heartbeat_pid}"' TERM

    "$@" >"${log_path}" 2>&1 &
    command_pid=$!
    if [[ "${interrupted_status}" -ne 0 ]]; then
      kill -TERM "${command_pid}" 2>/dev/null || true
    fi
    python3 "${helper_dir}/agent_output_heartbeat.py" \
      "${command_pid}" \
      "${heartbeat_seconds}" \
      "${label}" \
      "${log_path}" &
    heartbeat_pid=$!
    if [[ "${interrupted_status}" -ne 0 ]]; then
      kill -TERM "${heartbeat_pid}" 2>/dev/null || true
    fi

    if wait "${command_pid}"; then
      command_status=0
    else
      command_status=$?
    fi
    if [[ "${interrupted_status}" -ne 0 ]]; then
      wait "${command_pid}" 2>/dev/null || true
    fi
    if [[ "${heartbeat_pid}" -ne 0 ]]; then
      kill "${heartbeat_pid}" 2>/dev/null || true
      wait "${heartbeat_pid}" 2>/dev/null || true
    fi
    _agent_output_restore_trap "${previous_int_trap}" INT
    _agent_output_restore_trap "${previous_term_trap}" TERM
    if [[ "${interrupted_status}" -ne 0 ]]; then
      command_status="${interrupted_status}"
    fi
  fi

  umask "${previous_umask}"
  echo "Finished ${label} with status ${command_status}"
  if [[ "${command_status}" -ne 0 ]]; then
    echo "Diagnostic tail (${failure_lines} lines maximum):"
    tail -n "${failure_lines}" "${log_path}"
  fi
  return "${command_status}"
}
