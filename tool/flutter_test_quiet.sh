#!/usr/bin/env bash
#
# Token-frugal wrapper around `flutter test`.
#
# `flutter test` prints one progress line per test plus every Logger/print line
# emitted by passing tests. A full green run of this repository is ~3.4 MB of
# stdout, which is expensive for an agent to read and is usually truncated
# before the interesting part. This wrapper routes the run through the JSON
# reporter and prints a one-line verdict on success, or only the failing tests
# (error, filtered stack, and the output captured for that test) on failure.
#
# The full JSON log is always kept so a deeper dive stays one command away.
#
# Usage:
#   tool/flutter_test_quiet.sh [--slowest N] [--verbose] [flutter test args...]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

REPORT_DIR="${CAVERNO_TEST_REPORT_DIR:-build/test_reports}"
JSON_LOG="$REPORT_DIR/flutter_test.json"
RAW_LOG="$REPORT_DIR/flutter_test_stdout.txt"
SLOWEST=0
VERBOSE=false
SUMMARY_ARGS=()
TEST_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slowest)
      [[ $# -ge 2 ]] || { echo "Error: --slowest requires a count." >&2; exit 2; }
      SLOWEST="$2"
      shift 2
      ;;
    --max-failures|--max-error-lines|--max-stack-lines|--max-print-lines)
      [[ $# -ge 2 ]] || { echo "Error: $1 requires a value." >&2; exit 2; }
      SUMMARY_ARGS+=("$1" "$2")
      shift 2
      ;;
    --verbose)
      # Stream the ordinary reporter as well; useful when a run hangs.
      VERBOSE=true
      shift
      ;;
    --)
      shift
      TEST_ARGS+=("$@")
      break
      ;;
    *)
      TEST_ARGS+=("$1")
      shift
      ;;
  esac
done

if command -v fvm >/dev/null 2>&1 && { [[ -f .fvmrc ]] || [[ -d .fvm ]]; }; then
  FLUTTER_CMD=(fvm flutter)
else
  FLUTTER_CMD=(flutter)
fi

mkdir -p "$REPORT_DIR"
rm -f "$JSON_LOG"

if $VERBOSE; then
  REPORTER=(--reporter expanded)
else
  REPORTER=(--reporter silent)
fi

set +e
if $VERBOSE; then
  "${FLUTTER_CMD[@]}" test \
    "${REPORTER[@]}" \
    --file-reporter "json:$JSON_LOG" \
    ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} \
    2>&1 | tee "$RAW_LOG"
  RUN_STATUS=${PIPESTATUS[0]}
else
  "${FLUTTER_CMD[@]}" test \
    "${REPORTER[@]}" \
    --file-reporter "json:$JSON_LOG" \
    ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} \
    >"$RAW_LOG" 2>&1
  RUN_STATUS=$?
fi
set -e

if [[ ! -s "$JSON_LOG" ]]; then
  # No JSON at all means the run never reached the reporter (compile failure in
  # a test's imports, a bad argument, a missing toolchain). The raw output is
  # the only evidence, so show it verbatim.
  echo "FAIL: flutter test exited $RUN_STATUS before producing a JSON report."
  cat "$RAW_LOG"
  exit "${RUN_STATUS:-1}"
fi

SUMMARY_STATUS=0
python3 "$SCRIPT_DIR/summarize_flutter_test_json.py" "$JSON_LOG" \
  --root "$ROOT_DIR" \
  --slowest "$SLOWEST" \
  ${SUMMARY_ARGS[@]+"${SUMMARY_ARGS[@]}"} || SUMMARY_STATUS=$?

if [[ $RUN_STATUS -ne 0 && $SUMMARY_STATUS -eq 0 ]]; then
  # The run failed but the JSON stream looked clean: the failure happened
  # outside the reporter (compilation, a bad flag, a crashed host). Surface the
  # compiler diagnostics from the raw log so the cause is not invisible.
  COMPILE_ERRORS="$(grep -hE '(: Error:|^Failed to load|^Compilation failed)' "$RAW_LOG" | head -40 || true)"
  echo
  echo "flutter test exited $RUN_STATUS with no failing test in the report."
  if [[ -n "$COMPILE_ERRORS" ]]; then
    echo "Load/compile errors:"
    echo "$COMPILE_ERRORS" | sed 's/^/  /'
  else
    echo "Last lines of raw output:"
    tail -20 "$RAW_LOG" | sed 's/^/  /'
  fi
fi

echo
echo "Full JSON log: $JSON_LOG (raw stdout: $RAW_LOG)"

if [[ $RUN_STATUS -ne 0 ]]; then
  exit "$RUN_STATUS"
fi
exit "$SUMMARY_STATUS"
