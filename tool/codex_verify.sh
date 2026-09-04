#!/usr/bin/env bash
#
# Local verification entrypoint for Codex-driven Caverno changes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RUN_CODEGEN=true
RUN_ANALYZE=true
RUN_TESTS=true
RUN_COVERAGE=false
COVERAGE_THRESHOLD=60
QUIET_TESTS=true
FORCE_PUB_GET=false
ALL_SUITES=false
PACKAGE_CONFIG=".dart_tool/package_config.json"
PUB_GET_STAMP=".dart_tool/codex_verify_pub_get.stamp"
TEST_TARGETS=()
PACKAGE_DIRS=()
PACKAGE_COVERAGE_DIR=""
NOTIFICATION_RELAY_DIR="services/notification_relay"

usage() {
  cat <<'EOF'
Usage:
  tool/codex_verify.sh [options]

Options:
  --coverage                 Run tests with coverage and print a line summary.
  --force-pub-get            Run `pub get` even when dependencies already look
                             resolved. The default skips it in that case.
  --all-suites               With --test, also run the workspace package suites
                             and the notification relay checks. The default
                             keeps a focused run focused.
  --raw-tests                Echo every Flutter test progress and log line.
                             The default summarizes the run through
                             tool/flutter_test_quiet.sh, which prints one line
                             on success and only the failing tests otherwise.
  --coverage-threshold PCT   Show files below this line coverage percent.
                             Default: 60.
  --test PATH                Run a focused test target. May be repeated.
  --no-codegen               Skip build_runner and generated-file diff checks.
  --no-analyze               Skip Flutter static analysis.
  --no-tests                 Skip Flutter tests.
  -h, --help                 Show this help and exit.

Examples:
  tool/codex_verify.sh
  tool/codex_verify.sh --test test/core/utils/content_parser_test.dart
  tool/codex_verify.sh --coverage --coverage-threshold 75
  tool/codex_verify.sh --raw-tests
  tool/codex_verify.sh --force-pub-get
  tool/codex_verify.sh --test test/widget_test.dart --all-suites
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --coverage)
      RUN_COVERAGE=true
      shift
      ;;
    --force-pub-get)
      FORCE_PUB_GET=true
      shift
      ;;
    --all-suites)
      ALL_SUITES=true
      shift
      ;;
    --raw-tests)
      QUIET_TESTS=false
      shift
      ;;
    --coverage-threshold)
      [[ $# -ge 2 ]] || { echo "Error: --coverage-threshold requires a value." >&2; exit 2; }
      COVERAGE_THRESHOLD="$2"
      shift 2
      ;;
    --test)
      [[ $# -ge 2 ]] || { echo "Error: --test requires a path." >&2; exit 2; }
      TEST_TARGETS+=("$2")
      shift 2
      ;;
    --no-codegen)
      RUN_CODEGEN=false
      shift
      ;;
    --no-analyze)
      RUN_ANALYZE=false
      shift
      ;;
    --no-tests)
      RUN_TESTS=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'." >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

if command -v fvm >/dev/null 2>&1 && { [[ -f .fvmrc ]] || [[ -d .fvm ]]; }; then
  FLUTTER_CMD=(fvm flutter)
  DART_CMD=(fvm dart)
else
  FLUTTER_CMD=(flutter)
  DART_CMD=(dart)
fi

run_step() {
  local label="$1"
  shift

  printf '\n== %s ==\n' "$label"
  printf '$'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

run_in_directory_step() {
  local label="$1"
  local directory="$2"
  shift 2

  printf '\n== %s ==\n' "$label"
  printf '$ cd %q &&' "$directory"
  printf ' %q' "$@"
  printf '\n'
  (
    cd "$directory"
    "$@"
  )
}

package_uses_flutter() {
  local package_dir="$1"
  grep -Eq '^  flutter:[[:space:]]*$' "$package_dir/pubspec.yaml"
}

package_uses_codegen() {
  local package_dir="$1"
  grep -Eq '^  build_runner:' "$package_dir/pubspec.yaml"
}

package_command() {
  local package_dir="$1"
  if package_uses_flutter "$package_dir"; then
    PACKAGE_CMD=("${FLUTTER_CMD[@]}")
  else
    PACKAGE_CMD=("${DART_CMD[@]}")
  fi
}

merge_package_coverage() {
  local lcov_file="coverage/lcov.info"
  if [[ -z "$PACKAGE_COVERAGE_DIR" ]] || [[ ! -d "$PACKAGE_COVERAGE_DIR" ]]; then
    return
  fi

  local package_lcov_files=()
  while IFS= read -r package_lcov; do
    package_lcov_files+=("$package_lcov")
  done < <(find "$PACKAGE_COVERAGE_DIR" -maxdepth 1 -name '*.info' -print | sort)

  if [[ ${#package_lcov_files[@]} -eq 0 ]]; then
    return
  fi

  mkdir -p "$(dirname "$lcov_file")"
  touch "$lcov_file"
  for package_lcov in "${package_lcov_files[@]}"; do
    cat "$package_lcov" >> "$lcov_file"
  done
}

summarize_coverage() {
  local lcov_file="coverage/lcov.info"
  if [[ ! -f "$lcov_file" ]]; then
    echo "Coverage summary skipped because $lcov_file was not found."
    return
  fi

  local low_file
  local summary_file
  local total_file
  low_file="$(mktemp)"
  summary_file="$(mktemp)"
  total_file="$(mktemp)"

  awk \
    -v threshold="$COVERAGE_THRESHOLD" \
    -v low_file="$low_file" \
    -v total_file="$total_file" '
      function flush_file() {
        if (file != "" && include && found > 0) {
          total_found += found
          total_hit += hit
          rate = (hit * 100.0) / found
          if (rate < threshold) {
            printf "%09.4f\t%s\t%d\t%d\n", rate, file, hit, found >> low_file
          }
        }
      }

      /^SF:/ {
        flush_file()
        file = substr($0, 4)
        include = file !~ /\.(freezed|g)\.dart$/
        found = 0
        hit = 0
        next
      }

      /^LF:/ {
        found = substr($0, 4) + 0
        next
      }

      /^LH:/ {
        hit = substr($0, 4) + 0
        next
      }

      END {
        flush_file()
        if (total_found > 0) {
          rate = (total_hit * 100.0) / total_found
          printf "Line coverage: %.2f%% (%d/%d)\n", rate, total_hit, total_found > total_file
        } else {
          print "Line coverage: no executable lines found." > total_file
        }
      }
    ' "$lcov_file"

  {
    printf '\n== Coverage summary ==\n'
    cat "$total_file"
    echo "Report: $lcov_file"

    if [[ -s "$low_file" ]]; then
      printf '\nFiles below %s%% line coverage:\n' "$COVERAGE_THRESHOLD"
      sort -n "$low_file" | awk -F '\t' '{ printf "  %6.2f%% %5d/%-5d %s\n", $1, $3, $4, $2 }'
    else
      printf '\nNo files below %s%% line coverage.\n' "$COVERAGE_THRESHOLD"
    fi
  } | tee "$summary_file"

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "## Flutter coverage"
      echo
      sed 's/^/    /' "$summary_file"
    } >> "$GITHUB_STEP_SUMMARY"
  fi

  rm -f "$low_file" "$summary_file" "$total_file"
}

while IFS= read -r package_pubspec; do
  PACKAGE_DIRS+=("${package_pubspec%/pubspec.yaml}")
done < <(find packages -mindepth 2 -maxdepth 2 -name pubspec.yaml -print 2>/dev/null | sort)

# `pub get` dominates the runtime of an otherwise focused verification and is
# usually a no-op: the resolved package config only goes stale when a pubspec
# changes. Agent harnesses that time-slice a command pay for that no-op with an
# empty result, so skip it when nothing has changed.
# The stamp records when this script last saw `pub get` succeed. Pub's own
# artifacts cannot serve as the anchor: a no-op `pub get` leaves
# package_config.json untouched, and pubspec.lock is rewritten after it, so
# either comparison reports "stale" forever once a pubspec is touched.
dependencies_resolved() {
  [[ -f "$PACKAGE_CONFIG" && -f "$PUB_GET_STAMP" ]] || return 1
  [[ ! -f pubspec.yaml || "$PUB_GET_STAMP" -nt pubspec.yaml ]] || return 1
  [[ ! -f pubspec.lock || "$PUB_GET_STAMP" -nt pubspec.lock ]] || return 1
  local package_dir
  for package_dir in ${PACKAGE_DIRS[@]+"${PACKAGE_DIRS[@]}"}; do
    [[ "$PUB_GET_STAMP" -nt "$package_dir/pubspec.yaml" ]] || return 1
  done
  return 0
}

if $FORCE_PUB_GET || ! dependencies_resolved; then
  # `pub get` writes into the Flutter SDK cache, which sandboxed agent sessions
  # deny ("Operation not permitted"). That denial says nothing about the
  # resolution itself, so keep going when a resolved package config is present
  # rather than aborting the whole verification before a single test runs.
  if run_step "Install dependencies" "${FLUTTER_CMD[@]}" pub get; then
    mkdir -p "$(dirname "$PUB_GET_STAMP")"
    : > "$PUB_GET_STAMP"
  else
    if [[ -f "$PACKAGE_CONFIG" ]]; then
      printf '\nWarning: pub get failed; continuing with the existing %s.\n' \
        "$PACKAGE_CONFIG"
    else
      echo "Error: pub get failed and no resolved package config exists." >&2
      exit 1
    fi
  fi
else
  printf '\n== Install dependencies ==\n'
  printf 'Skipped: no pubspec changed since the last successful pub get.'
  printf ' Use --force-pub-get to run it anyway.\n'
fi

run_step "List workspace packages" "${DART_CMD[@]}" pub workspace list

# A `--test` run asks for one target. Running every workspace package suite and
# the relay checks alongside it triples the wall time, which pushes the run past
# the window some agent harnesses give a command before they stop waiting.
FOCUSED=false
if [[ ${#TEST_TARGETS[@]} -gt 0 ]] && ! $ALL_SUITES && ! $RUN_COVERAGE; then
  FOCUSED=true
fi

if [[ -f "$NOTIFICATION_RELAY_DIR/package-lock.json" ]] && ! $FOCUSED; then
  run_in_directory_step \
    "Install notification relay dependencies" \
    "$NOTIFICATION_RELAY_DIR" \
    npm ci --ignore-scripts
fi

if $RUN_CODEGEN; then
  run_step "Regenerate Freezed and JSON files" \
    "${DART_CMD[@]}" run build_runner build --delete-conflicting-outputs
  for package_dir in "${PACKAGE_DIRS[@]}"; do
    if package_uses_codegen "$package_dir"; then
      run_in_directory_step \
        "Regenerate package code: $package_dir" \
        "$package_dir" \
        "${DART_CMD[@]}" run build_runner build --delete-conflicting-outputs
    fi
  done
  run_step "Verify generated files are committed" \
    git diff --exit-code -- ':(glob)**/*.freezed.dart' ':(glob)**/*.g.dart'
fi

if $RUN_ANALYZE; then
  run_step "Analyze project" "${FLUTTER_CMD[@]}" analyze
  for package_dir in ${PACKAGE_DIRS[@]+"${PACKAGE_DIRS[@]}"}; do
    package_command "$package_dir"
    run_in_directory_step \
      "Analyze package: $package_dir" \
      "$package_dir" \
      "${PACKAGE_CMD[@]}" analyze
  done
  if [[ -f "$NOTIFICATION_RELAY_DIR/package.json" ]] && ! $FOCUSED; then
    run_in_directory_step \
      "Check notification relay" \
      "$NOTIFICATION_RELAY_DIR" \
      npm run check
  fi
fi

if $RUN_TESTS; then
  if $RUN_COVERAGE; then
    PACKAGE_COVERAGE_DIR="$(mktemp -d)"
    trap 'rm -rf "$PACKAGE_COVERAGE_DIR"' EXIT
  fi

  if $FOCUSED && [[ ${#PACKAGE_DIRS[@]} -gt 0 ]]; then
    printf '\n== Test packages ==\n'
    printf 'Skipped for a focused run. Use --all-suites to include them.\n'
    PACKAGE_DIRS=()
  fi

  for package_dir in ${PACKAGE_DIRS[@]+"${PACKAGE_DIRS[@]}"}; do
    package_command "$package_dir"
    if $RUN_COVERAGE; then
      package_name="$(basename "$package_dir")"
      if package_uses_flutter "$package_dir"; then
        run_in_directory_step \
          "Test package with coverage: $package_dir" \
          "$package_dir" \
          "${PACKAGE_CMD[@]}" test \
          --coverage \
          --coverage-path="$PACKAGE_COVERAGE_DIR/$package_name.info"
      else
        run_in_directory_step \
          "Test package with coverage: $package_dir" \
          "$package_dir" \
          "${PACKAGE_CMD[@]}" test \
          --coverage-path="$PACKAGE_COVERAGE_DIR/$package_name.info"
      fi
    else
      run_in_directory_step \
        "Test package: $package_dir" \
        "$package_dir" \
        "${PACKAGE_CMD[@]}" test
    fi
  done

  # The wrapper forwards unknown arguments to `flutter test`, so --coverage
  # still produces coverage/lcov.info while the console output stays summarized.
  if $QUIET_TESTS; then
    TEST_CMD=("$SCRIPT_DIR/flutter_test_quiet.sh")
  else
    TEST_CMD=("${FLUTTER_CMD[@]}" test)
  fi

  COVERAGE_ARGS=()
  if $RUN_COVERAGE; then
    COVERAGE_ARGS=(--coverage)
  fi

  if [[ ${#TEST_TARGETS[@]} -gt 0 ]]; then
    run_step "Run focused tests" \
      "${TEST_CMD[@]}" ${COVERAGE_ARGS[@]+"${COVERAGE_ARGS[@]}"} \
      "${TEST_TARGETS[@]}"
  else
    run_step "Run tests" \
      "${TEST_CMD[@]}" ${COVERAGE_ARGS[@]+"${COVERAGE_ARGS[@]}"}
  fi

  if [[ -f "$NOTIFICATION_RELAY_DIR/package.json" ]] && ! $FOCUSED; then
    run_in_directory_step \
      "Test notification relay" \
      "$NOTIFICATION_RELAY_DIR" \
      npm test
  fi

  if $RUN_COVERAGE; then
    merge_package_coverage
  fi
fi

if $RUN_COVERAGE; then
  summarize_coverage
fi

printf '\nCodex verification completed successfully.\n'
