#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DART_BIN="${CAVERNO_PERSONAL_EVAL_DART_BIN:-dart}"
PIPELINE_HELPER="${CAVERNO_PERSONAL_EVAL_SUITE_PIPELINE_HELPER:-${ROOT_DIR}/tool/personal_eval_suite_pipeline.dart}"
REPORT_ROOT="${CAVERNO_PERSONAL_EVAL_SUITE_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports/personal_eval_suite_pipeline_$(date +%s)}"
OUT_DIR="${CAVERNO_PERSONAL_EVAL_SUITE_OUT_DIR:-${REPORT_ROOT}}"
LABEL="${CAVERNO_PERSONAL_EVAL_SUITE_LABEL:-}"

usage() {
  cat <<EOF
Usage: tool/run_personal_eval_suite_pipeline.sh --manifest PATH [--manifest PATH ...] \\
  --incumbent-label LABEL --candidate-label LABEL \\
  --incumbent-case-log CASE_ID=PATH --candidate-case-log CASE_ID=PATH \\
  --incumbent-verification-result CASE_ID=passed|failed|inconclusive \\
  --candidate-verification-result CASE_ID=passed|failed|inconclusive \\
  [--out-dir PATH] [--label LABEL] [pipeline options...]

Environment:
  CAVERNO_PERSONAL_EVAL_SUITE_REPORT_ROOT   Default report root.
  CAVERNO_PERSONAL_EVAL_SUITE_OUT_DIR       Output directory passed to the Dart pipeline.
  CAVERNO_PERSONAL_EVAL_SUITE_LABEL         Optional report label when --label is not provided.
  CAVERNO_PERSONAL_EVAL_DART_BIN            Dart executable used to run the pipeline.
  CAVERNO_PERSONAL_EVAL_SUITE_PIPELINE_HELPER
                                              Dart pipeline entrypoint.
EOF
}

option_value() {
  local option="$1"
  shift
  local next_is_value=0
  for arg in "$@"; do
    if [[ "${next_is_value}" == "1" ]]; then
      printf '%s\n' "${arg}"
      return 0
    fi
    if [[ "${arg}" == "${option}" ]]; then
      next_is_value=1
      continue
    fi
    if [[ "${arg}" == "${option}="* ]]; then
      printf '%s\n' "${arg#*=}"
      return 0
    fi
  done
  return 1
}

if [[ "$#" -eq 0 ]]; then
  usage >&2
  exit 64
fi

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

args=("$@")
effective_out_dir="$(option_value "--out-dir" "${args[@]}" || true)"
if [[ -z "${effective_out_dir}" ]]; then
  effective_out_dir="${OUT_DIR}"
  args+=("--out-dir" "${effective_out_dir}")
fi
effective_label="$(option_value "--label" "${args[@]}" || true)"
if [[ -n "${LABEL}" && -z "${effective_label}" ]]; then
  effective_label="${LABEL}"
  args+=("--label" "${effective_label}")
fi

mkdir -p "${effective_out_dir}"

echo "Running personal eval suite pipeline"
echo "  Output directory: ${effective_out_dir}"
if [[ -n "${effective_label}" ]]; then
  echo "  Report label: ${effective_label}"
fi

"${DART_BIN}" run "${PIPELINE_HELPER}" "${args[@]}"

echo
echo "Personal eval suite artifacts"
echo "  Incumbent replay: ${effective_out_dir}/incumbent_replay_run.json"
echo "  Candidate replay: ${effective_out_dir}/candidate_replay_run.json"
echo "  Report JSON: ${effective_out_dir}/personal_eval_suite_report.json"
echo "  Report Markdown: ${effective_out_dir}/personal_eval_suite_report.md"
