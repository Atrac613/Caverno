#!/usr/bin/env bash
#
# tool/macos_dev_preflight.sh — Reset macOS dev state for Caverno builds.
#
# When more than one git worktree builds Caverno.app, macOS LaunchServices
# indexes every bundle that shares the com.noguwo.apps.caverno identifier.
# launchd then routes XPC requests to whichever Caverno Computer Use helper
# LaunchServices happened to pick — usually not the bundle the developer
# just built. TCC grants drift across helper paths, and Computer Use
# diagnostics report helper_bundle_path_mismatch / helperPathMismatch.
#
# This script:
#   1. Kills running Caverno main app + helper processes.
#   2. Removes stale Caverno*.app build artifacts under known worktree roots.
#   3. Unregisters stale LaunchServices entries for com.noguwo.apps.caverno*.
#   4. Restarts Finder so LaunchServices reloads its in-memory state.
#   5. Optionally runs `flutter clean` in the main worktree.
#
# Run this before `flutter run -d macos` when the helper reports a path
# mismatch, or whenever you have been bouncing between worktrees.

set -euo pipefail

# ----------------------------------------------------------------------------
# Defaults and configuration
# ----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_WORKTREE="$(cd "$SCRIPT_DIR/.." && pwd)"

DRY_RUN=false
SKIP_CLEAN=false
SKIP_FINDER=false
USE_COLOR=true

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Roots to scan for stale Caverno*.app build artifacts. Edit if you keep
# worktrees elsewhere on disk.
SEARCH_ROOTS=(
  "$HOME/Documents/Workspace/Flutter"
  "$HOME/.codex"
  "$HOME/.claude/worktrees"
  "/private/tmp"
)

# ----------------------------------------------------------------------------
# Usage
# ----------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage:
  tool/macos_dev_preflight.sh [options]

Options:
  --main-worktree PATH   Treat PATH as the main worktree to preserve.
                         Default: parent directory of this script.
  --dry-run              Print actions but do not execute them.
                         Implies a detect-only run with no state changes.
  --skip-clean           Do not run `flutter clean` in the main worktree.
  --skip-finder-restart  Do not `killall Finder`.
  --no-color             Disable colored output.
  -h, --help             Show this help and exit.

Examples:
  tool/macos_dev_preflight.sh
  tool/macos_dev_preflight.sh --dry-run
  tool/macos_dev_preflight.sh --skip-finder-restart --skip-clean
EOF
}

# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --main-worktree)
      [[ $# -ge 2 ]] || { echo "Error: --main-worktree requires a path" >&2; exit 2; }
      MAIN_WORKTREE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-clean)
      SKIP_CLEAN=true
      shift
      ;;
    --skip-finder-restart)
      SKIP_FINDER=true
      shift
      ;;
    --no-color)
      USE_COLOR=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Validation
# ----------------------------------------------------------------------------

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: this script only runs on macOS." >&2
  exit 1
fi

if [[ ! -d "$MAIN_WORKTREE" ]]; then
  echo "Error: main worktree does not exist: $MAIN_WORKTREE" >&2
  exit 1
fi
MAIN_WORKTREE="$(cd "$MAIN_WORKTREE" && pwd)"

if [[ ! -x "$LSREGISTER" ]]; then
  echo "Error: lsregister not found at $LSREGISTER" >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# Output helpers
# ----------------------------------------------------------------------------

if $USE_COLOR && [[ -t 1 ]]; then
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_BOLD='' C_RESET=''
fi

step() { printf '\n%s\n' "${C_BOLD}${C_BLUE}== $* ==${C_RESET}"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '  %s\n' "${C_YELLOW}! $*${C_RESET}" >&2; }
ok()   { printf '  %s\n' "${C_GREEN}[ok] $*${C_RESET}"; }
err()  { printf '  %s\n' "${C_RED}[err] $*${C_RESET}" >&2; }

# Run a command, or just print it in dry-run mode.
run() {
  if $DRY_RUN; then
    printf '  %s\n' "${C_YELLOW}[dry-run]${C_RESET} $*"
  else
    printf '  %s\n' "${C_BLUE}\$${C_RESET} $*"
    eval "$@"
  fi
}

# ----------------------------------------------------------------------------
# Steps
# ----------------------------------------------------------------------------

print_header() {
  printf '%s\n' "${C_BOLD}Caverno macOS dev preflight${C_RESET}"
  info "main worktree : $MAIN_WORKTREE"
  if $DRY_RUN; then
    info "mode          : dry-run (no changes)"
  else
    info "mode          : cleanup"
  fi
}

kill_running_caverno() {
  step "1/5  Running Caverno processes"

  # Collect PIDs of the Caverno main app or helper executables. Filter out
  # this preflight script and unrelated processes (e.g., Claude.app).
  local pids=()
  while IFS= read -r pid; do
    [[ -n "$pid" ]] && pids+=("$pid")
  done < <(
    pgrep -f 'Caverno\.app/Contents/MacOS/Caverno' 2>/dev/null || true
    pgrep -f 'Caverno Computer Use\.app/Contents/MacOS/Caverno Computer Use' 2>/dev/null || true
  )

  if [[ ${#pids[@]} -eq 0 ]]; then
    ok "No Caverno processes running."
    return
  fi

  warn "Found ${#pids[@]} Caverno process(es):"
  for pid in "${pids[@]}"; do
    local cmd
    cmd="$(ps -p "$pid" -o command= 2>/dev/null || echo '?')"
    info "  pid=$pid  $cmd"
  done

  run "pkill -f 'Caverno\\.app/Contents/MacOS/Caverno' 2>/dev/null || true"
  run "pkill -f 'Caverno Computer Use\\.app/Contents/MacOS/Caverno Computer Use' 2>/dev/null || true"
  run "sleep 1"
}

remove_stale_apps() {
  step "2/5  Stale Caverno*.app build artifacts outside main worktree"

  # Build a list of stale .app bundles to remove. `find -prune` ensures we
  # don't recurse into a Caverno*.app that contains another Caverno*.app
  # (e.g., the embedded Caverno Computer Use.app inside Caverno.app).
  local stale=()
  while IFS= read -r app; do
    case "$app" in
      "$MAIN_WORKTREE"/*) continue ;;
      '') continue ;;
    esac
    stale+=("$app")
  done < <(
    find "${SEARCH_ROOTS[@]}" \
      -name 'Caverno*.app' \
      -type d \
      -path '*/build/*' \
      -prune \
      2>/dev/null || true
  )

  if [[ ${#stale[@]} -eq 0 ]]; then
    ok "No stale Caverno*.app builds found."
    return
  fi

  warn "Found ${#stale[@]} stale Caverno*.app build(s):"
  for app in "${stale[@]}"; do
    info "  $app"
  done

  for app in "${stale[@]}"; do
    run "rm -rf \"$app\""
  done
}

unregister_stale_ls_entries() {
  step "3/5  Stale LaunchServices entries for com.noguwo.apps.caverno*"

  # Parse lsregister -dump output. Each app entry has a `path:` line near
  # the top, followed (later) by a CFBundleIdentifier line. We capture the
  # most recent `path:` and emit it when we see our bundle id.
  local stale_paths=()
  while IFS= read -r p; do
    case "$p" in
      "$MAIN_WORKTREE"/*) continue ;;
      '') continue ;;
    esac
    stale_paths+=("$p")
  done < <(
    "$LSREGISTER" -dump 2>/dev/null \
      | awk '
          /^path:/ {
            path=$0
            sub(/^path:[ \t]+/, "", path)
            # Strip trailing LaunchServices handle like " (0xa178)"
            sub(/[ \t]*\(0x[0-9a-fA-F]+\)[ \t]*$/, "", path)
          }
          /CFBundleIdentifier = "com\.noguwo\.apps\.caverno/ {
            if (path != "") {
              print path
              path=""
            }
          }
        ' \
      | sort -u
  )

  if [[ ${#stale_paths[@]} -eq 0 ]]; then
    ok "No stale LaunchServices entries."
    return
  fi

  warn "Found ${#stale_paths[@]} stale LS entry/entries:"
  for p in "${stale_paths[@]}"; do
    info "  $p"
  done

  for p in "${stale_paths[@]}"; do
    run "\"$LSREGISTER\" -u \"$p\" 2>/dev/null || true"
  done
}

restart_finder() {
  step "4/5  Restart Finder"
  if $SKIP_FINDER; then
    info "(skipped via --skip-finder-restart)"
    return
  fi
  run "killall Finder 2>/dev/null || true"
}

flutter_clean() {
  step "5/5  flutter clean in main worktree"
  if $SKIP_CLEAN; then
    info "(skipped via --skip-clean)"
    return
  fi
  if [[ ! -d "$MAIN_WORKTREE/build" ]]; then
    ok "No build/ to clean."
    return
  fi
  # Prefer fvm flutter when available so we match the project's pinned SDK.
  if command -v fvm >/dev/null 2>&1; then
    run "(cd \"$MAIN_WORKTREE\" && fvm flutter clean >/dev/null)"
  else
    run "(cd \"$MAIN_WORKTREE\" && flutter clean >/dev/null)"
  fi
}

print_summary() {
  printf '\n%s\n' "${C_BOLD}Next steps${C_RESET}"
  info "1. cd \"$MAIN_WORKTREE\""
  if command -v fvm >/dev/null 2>&1; then
    info "2. fvm flutter run -d macos"
  else
    info "2. flutter run -d macos"
  fi
  info "3. In the Caverno Computer Use window, grant Accessibility and"
  info "   Screen & System Audio Recording to Caverno Computer Use."
  info "4. If macOS shows a \"Caverno would like to record\" prompt for the"
  info "   main app, click Deny. Only the helper needs Screen Recording."
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

print_header
kill_running_caverno
remove_stale_apps
unregister_stale_ls_entries
restart_finder
flutter_clean
print_summary
