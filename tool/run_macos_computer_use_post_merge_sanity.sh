#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRINT_COMMANDS=false
RUN_ANALYZE=true
RUN_TESTS=true
RUN_BUILD=true

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_post_merge_sanity.sh [options]

Options:
  --print-commands  Print the checks without running them.
  --skip-analyze    Skip flutter analyze.
  --skip-tests      Skip focused Flutter tests.
  --skip-build      Skip flutter build macos --debug.
  --help            Show this help.

This post-merge sanity runner executes only static analysis, focused tests, and
debug macOS build checks. It never grants TCC, edits TCC, operates System
Settings, launches apps, moves the pointer, clicks, types, records audio, or
runs desktop actions.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --print-commands)
      PRINT_COMMANDS=true
      shift
      ;;
    --skip-analyze)
      RUN_ANALYZE=false
      shift
      ;;
    --skip-tests)
      RUN_TESTS=false
      shift
      ;;
    --skip-build)
      RUN_BUILD=false
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 64
      ;;
  esac
done

run_step() {
  local label="$1"
  shift
  local command=("$@")
  echo "==> ${label}"
  printf '    %q' "${command[0]}"
  printf ' %q' "${command[@]:1}"
  echo
  if [[ "${PRINT_COMMANDS}" == "false" ]]; then
    "${command[@]}"
  fi
}

echo "Running macOS Computer Use post-merge sanity checks"
echo "  Boundary: static checks only, no TCC, no System Settings, no desktop actions"
echo "  Review scope: Advanced navigation, collapsed Diagnostics, manual runtime handoff, M14 observe-only evidence, M15 review/gate consistency"
echo "  Checklist: docs/macos_computer_use_manual_process_checklist.md#M13-Review-Hardening"
echo "  Observe checklist: docs/macos_computer_use_manual_process_checklist.md#M14-Observe-Only-Evidence"

cd "${ROOT_DIR}"

if [[ "${RUN_ANALYZE}" == "true" ]]; then
  run_step "Analyze" flutter analyze
fi

if [[ "${RUN_TESTS}" == "true" ]]; then
  run_step "Focused tests" \
    flutter test \
    test/features/settings/presentation/pages/advanced_settings_page_test.dart \
    test/features/settings/presentation/pages/settings_page_test.dart \
    test/features/settings/presentation/pages/computer_use_debug_page_test.dart \
    test/integration_support/macos_computer_use_release_readiness_test.dart \
    test/tool/run_macos_computer_use_smoke_test_test.dart \
    test/core/services/macos_computer_use_service_test.dart \
    test/core/services/macos_computer_use_setup_test.dart \
    test/core/services/macos_computer_use_transport_test.dart \
    -r compact
fi

if [[ "${RUN_BUILD}" == "true" ]]; then
  run_step "Debug macOS build" flutter build macos --debug
fi

echo "macOS Computer Use post-merge sanity checks complete"
