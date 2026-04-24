#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIVE_REPEAT_COUNT="${CAVERNO_PLAN_MODE_CONVERGENCE_LIVE_REPEAT_COUNT:-3}"
SKIP_LIVE="${CAVERNO_PLAN_MODE_SKIP_LIVE:-0}"

run_step() {
  local label="$1"
  shift
  echo
  echo "==> ${label}"
  "$@"
}

run_live_readme_canary() {
  local iteration="$1"
  echo
  echo "==> Live README convergence canary ${iteration}/${LIVE_REPEAT_COUNT}"
  CAVERNO_PLAN_MODE_SCENARIOS=live_readme_first_canary \
  CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1 \
  "${ROOT_DIR}/tool/run_plan_mode_live_test.sh"
}

cd "${ROOT_DIR}"

run_step "Focused saved-validation and report regressions" \
  flutter test \
    test/features/chat/presentation/providers/chat_notifier_test.dart \
    test/integration/plan_mode_scenario_spec_test.dart \
    test/integration_support/plan_mode_report_summary_test.dart \
    test/integration_support/plan_mode_suite_report_test.dart

run_step "Static analysis" flutter analyze

if [[ "${SKIP_LIVE}" == "1" ]]; then
  echo
  echo "==> Live README convergence canary skipped"
  echo "Set CAVERNO_PLAN_MODE_SKIP_LIVE=0 and provide CAVERNO_LLM_* to include it."
  exit 0
fi

for ((iteration = 1; iteration <= LIVE_REPEAT_COUNT; iteration += 1)); do
  run_live_readme_canary "${iteration}"
done

echo
echo "Plan mode convergence full pass completed."
