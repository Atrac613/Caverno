#!/usr/bin/env bash
#
# tool/macos_tcc_diagnose.sh — Diagnose and (optionally) fix Caverno TCC state.
#
# Verifies the macOS TCC state for Caverno and Caverno Computer Use:
#   1. Inspects code signing identity and Designated Requirement.
#   2. Reads TCC.db entries for our bundle IDs (requires Full Disk Access
#      on the terminal app). Falls back to a `tccutil`-only flow without it.
#   3. Confirms the running helper matches the expected embedded path.
#   4. Cross-references the helper's most recent shareable content probe
#      from /tmp/caverno-computer-use-helper-diagnostics.json.
#   5. Reports a single most-likely root cause.
#
# With --fix, applies the proper auto-correction:
#   - Resets explicit DENY entries via `tccutil reset` per bundle.
#   - Restarts the helper so it re-reads TCC state.
#   - Runs `tool/macos_dev_preflight.sh` when stale builds pollute LS.
#
# Run from anywhere; the script locates the main worktree relative to itself.

set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_WORKTREE="$(cd "$SCRIPT_DIR/.." && pwd)"

FIX=false
NO_COLOR=false

MAIN_BUNDLE_ID="com.noguwo.apps.caverno"
HELPER_BUNDLE_ID="com.noguwo.apps.caverno.computer-use"

USER_TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
SYSTEM_TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"

HELPER_SHARED_DIAGNOSTICS="/tmp/caverno-computer-use-helper-diagnostics.json"
PREFLIGHT_SCRIPT="$SCRIPT_DIR/macos_dev_preflight.sh"

# Glob for the user's most recent diagnostic export. The Caverno UI writes
# /var/folders/.../caverno-computer-use-onboarding-*.json on each export.
ONBOARDING_EXPORT_GLOB="/var/folders/*/*/T/caverno-computer-use-onboarding-*.json"

# ----------------------------------------------------------------------------
# Usage
# ----------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage:
  tool/macos_tcc_diagnose.sh [options]

Options:
  --fix          Apply auto-corrections for detected problems.
                 Without this, only diagnostics are reported.
  --no-color     Disable colored output.
  -h, --help     Show this help and exit.

Diagnostics:
  - Code signing identity and Designated Requirement.
  - TCC.db rows for com.noguwo.apps.caverno*. Requires Full Disk Access
    on the terminal: System Settings > Privacy & Security > Full Disk
    Access > + > Terminal/iTerm. The script still runs without FDA, but
    with reduced detail.
  - Running helper path vs embedded path.
  - Last shareable-content probe outcome from the helper diagnostics.

Auto-fixes (--fix):
  - sudo tccutil reset ScreenCapture <bundle> for DENY entries.
  - Restart the helper so it re-reads TCC state.
  - Invoke tool/macos_dev_preflight.sh when LaunchServices is polluted.
EOF
}

# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)
      FIX=true
      shift
      ;;
    --no-color)
      NO_COLOR=true
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

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: this script only runs on macOS." >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# Output helpers
# ----------------------------------------------------------------------------

if ! $NO_COLOR && [[ -t 1 ]]; then
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_DIM='' C_BOLD='' C_RESET=''
fi

step()   { printf '\n%s\n' "${C_BOLD}${C_BLUE}== $* ==${C_RESET}"; }
info()   { printf '  %s\n' "$*"; }
warn()   { printf '  %s\n' "${C_YELLOW}! $*${C_RESET}" >&2; }
ok()     { printf '  %s\n' "${C_GREEN}[ok] $*${C_RESET}"; }
err()    { printf '  %s\n' "${C_RED}[err] $*${C_RESET}" >&2; }
action() { printf '  %s\n' "${C_BLUE}\$${C_RESET} $*"; }

# ----------------------------------------------------------------------------
# Phase helpers
# ----------------------------------------------------------------------------

check_full_disk_access() {
  sqlite3 "$USER_TCC_DB" 'SELECT 1;' >/dev/null 2>&1
}

# Convert TCC auth_value to a human label and color tag.
# Modern macOS: 0=DENY, 2=ALLOW, 3=limited, 4=auth_required.
auth_label() {
  case "$1" in
    0) printf '%sDENY%s' "$C_RED" "$C_RESET" ;;
    1) printf 'unknown' ;;
    2) printf '%sALLOW%s' "$C_GREEN" "$C_RESET" ;;
    3) printf 'limited' ;;
    4) printf 'auth-required' ;;
    *) printf 'auth=%s' "$1" ;;
  esac
}

# Query a TCC.db for our bundle IDs. Output: tab-separated rows
# service<TAB>client<TAB>auth_value<TAB>last_modified
query_tcc() {
  local db="$1"
  [[ -r "$db" ]] || { return 1; }
  sqlite3 -separator $'\t' "$db" "
    SELECT service, client, auth_value,
           datetime(last_modified, 'unixepoch') AS last_modified
    FROM access
    WHERE client LIKE 'com.noguwo.apps.caverno%'
    ORDER BY service, last_modified DESC;
  " 2>/dev/null
}

# ----------------------------------------------------------------------------
# Inspection phases
# ----------------------------------------------------------------------------

inspect_signing() {
  step "Code signing"

  for entry in \
    "Main app|$MAIN_WORKTREE/build/macos/Build/Products/Debug/Caverno.app" \
    "Helper  |$MAIN_WORKTREE/build/macos/Build/Products/Debug/Caverno.app/Contents/Helpers/Caverno Computer Use.app"
  do
    local label="${entry%%|*}"
    local path="${entry#*|}"
    if [[ ! -d "$path" ]]; then
      warn "$label not found: $path"
      continue
    fi
    # Capture full codesign output first to avoid SIGPIPE when awk exits early.
    local sig
    sig="$(codesign -dvv "$path" 2>&1 || true)"
    if [[ -z "$sig" ]]; then
      err "$label codesign produced no output."
      continue
    fi
    local id team auth
    id="$(awk -F= '/^Identifier=/{print $2}' <<<"$sig" | head -n1)"
    team="$(awk -F= '/^TeamIdentifier=/{print $2}' <<<"$sig" | head -n1)"
    auth="$(awk -F'=' '/^Authority=Apple Development/{print $2}' <<<"$sig" | head -n1)"
    if [[ -z "$id" ]]; then
      err "$label not signed."
      continue
    fi
    printf '  %-7s  id=%-45s  team=%-10s  authority=%s\n' \
      "$label" "$id" "${team:--}" "${auth:--}"
  done
}

inspect_running_processes() {
  step "Running helper processes"

  local found=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    found=$((found + 1))
    local pid path
    pid="$(awk '{print $1}' <<<"$line")"
    path="$(awk '{$1=""; print}' <<<"$line" | sed 's/^ //')"

    if [[ "$path" == "$MAIN_WORKTREE"/* ]]; then
      ok "pid=$pid (main worktree)"
      info "  $path"
    else
      err "pid=$pid (stale path)"
      info "  $path"
    fi
  done < <(
    ps -ax -o pid=,command= \
      | grep -E 'Caverno Computer Use\.app/Contents/MacOS/Caverno Computer Use' \
      || true
  )

  if (( found == 0 )); then
    warn "No Caverno Computer Use helper is running."
  fi
}

inspect_tcc_db() {
  step "TCC.db entries for com.noguwo.apps.caverno*"

  if ! check_full_disk_access; then
    warn "Full Disk Access not granted to this terminal."
    info "Grant it for richer diagnostics:"
    info "  System Settings > Privacy & Security > Full Disk Access > + > Terminal/iTerm"
    info "Continuing without TCC.db introspection. Auto-fix still works via tccutil."
    HAS_FDA=false
    return
  fi

  HAS_FDA=true
  local rows
  rows="$(query_tcc "$USER_TCC_DB" || true)"
  if [[ -z "$rows" ]]; then
    info "(no entries in $USER_TCC_DB)"
    return
  fi

  printf '  %s%-26s %-44s %s%s\n' \
    "$C_DIM" "service" "client" "auth_value | last_modified" "$C_RESET"
  while IFS=$'\t' read -r service client auth_value last_modified; do
    printf '  %-26s %-44s %-13s %s\n' \
      "${service#kTCCService}" "$client" "$(auth_label "$auth_value")" "$last_modified"
  done <<<"$rows"

  # Also peek the system-level DB (typically empty for normal Macs).
  if [[ -r "$SYSTEM_TCC_DB" ]]; then
    local sys_rows
    sys_rows="$(query_tcc "$SYSTEM_TCC_DB" || true)"
    if [[ -n "$sys_rows" ]]; then
      info ""
      info "${C_DIM}(also in system-level TCC.db)${C_RESET}"
      while IFS=$'\t' read -r service client auth_value last_modified; do
        printf '  %-26s %-44s %-13s %s\n' \
          "${service#kTCCService}" "$client" "$(auth_label "$auth_value")" "$last_modified"
      done <<<"$sys_rows"
    fi
  fi
}

_latest_export() {
  # shellcheck disable=SC2086
  local latest
  latest="$(ls -1t $ONBOARDING_EXPORT_GLOB 2>/dev/null | head -n1 || true)"
  printf '%s' "$latest"
}

inspect_helper_probe() {
  step "Last helper probe (SCShareableContent)"

  local export_file
  export_file="$(_latest_export)"

  if [[ -z "$export_file" || ! -r "$export_file" ]]; then
    info "No onboarding diagnostic export found."
    info "Click 'Export Diagnostics' in Caverno's Computer Use settings, then rerun."
    return
  fi

  info "source : $export_file"

  python3 - "$export_file" <<'PY' 2>/dev/null || warn "Could not parse export file."
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception as exc:
    print(f"  parse error: {exc}")
    sys.exit(0)

# Probe fields live in two places: top-level "permissions" (rich live
# snapshot from the helper IPC reply) and setupChecklist.permissions
# (filtered, used by the UI). Prefer top-level since it carries the
# probeError/probeDetail fields.
top_perms = data.get("permissions", {}) or {}
checklist_perms = data.get("setupChecklist", {}).get("permissions", {}) or {}

def pick(key):
    v = top_perms.get(key)
    if v is None:
        v = checklist_perms.get(key)
    return v

generated = data.get("generatedAt", "")
method = pick("screenCaptureDetectionMethod") or "(unknown)"
preflight = pick("screenCapturePreflightGranted")
probe_attempted = pick("screenCaptureProbeAttempted")
probe_succeeded = pick("screenCaptureProbeSucceeded")
probe_error = pick("screenCaptureProbeError") or ""
probe_detail = pick("screenCaptureProbeDetail") or ""

def fmt(v):
    return "(unknown)" if v is None else str(v)

print(f"  generated     : {generated}")
print(f"  method        : {method}")
print(f"  preflight     : {fmt(preflight)}")
print(f"  probe attempt : {fmt(probe_attempted)}")
if probe_succeeded is True:
    print(f"  probe success : \033[32mtrue\033[0m")
elif probe_succeeded is False:
    print(f"  probe success : \033[31mfalse\033[0m")
else:
    print(f"  probe success : (unknown)")
if probe_error:
    print(f"  probe error   : \033[33m{probe_error}\033[0m")
if probe_detail:
    print(f"  probe detail  : {probe_detail}")
PY
}

# ----------------------------------------------------------------------------
# Diagnosis (root-cause inference)
# ----------------------------------------------------------------------------

# Populated by diagnose(). Consumed by fix() and print_next_steps().
DIAG_FLAGS=()

diagnose() {
  step "Root cause"

  # Helper running from wrong path?
  if ps -ax -o command= 2>/dev/null \
       | grep -E 'Caverno Computer Use\.app/Contents/MacOS/Caverno Computer Use' \
       | grep -v "$MAIN_WORKTREE" >/dev/null
  then
    DIAG_FLAGS+=("helper_wrong_path")
    err "A helper is running from a path outside $MAIN_WORKTREE."
  fi

  if $HAS_FDA; then
    # Combine entries from both user-level and (readable) system-level TCC.db.
    # System-level often holds the authoritative ALLOW after explicit grants
    # via System Settings, while user-level holds older session decisions.
    local combined
    combined="$(
      { query_tcc "$USER_TCC_DB" 2>/dev/null || true; query_tcc "$SYSTEM_TCC_DB" 2>/dev/null || true; }
    )"

    # Latest entry per (service, client) wins. last_modified is the 4th column
    # and is already sorted DESC by the SQL query, so the first match is newest.
    pick_latest_auth() {
      local service="$1" client="$2"
      awk -F'\t' -v s="$service" -v c="$client" '$1==s && $2==c {print $3; exit}' <<<"$combined"
    }

    local helper_sc
    helper_sc="$(pick_latest_auth kTCCServiceScreenCapture "$HELPER_BUNDLE_ID")"
    case "$helper_sc" in
      0)
        DIAG_FLAGS+=("helper_screencapture_deny")
        err "Helper has an explicit DENY entry for Screen Recording in TCC.db."
        ;;
      2)
        ok "Helper has ALLOW entry for Screen Recording in TCC.db."
        ;;
      "")
        # Don't add helper_screencapture_missing here when the probe already
        # flagged a deny — adding both leads to duplicate tccutil reset runs.
        warn "Helper has no Screen Recording entry yet in user/system TCC.db."
        ;;
      *)
        warn "Helper Screen Recording auth_value=$helper_sc (unrecognized)."
        ;;
    esac

    # The main app should not own Screen Recording. Treat DENY specially so the
    # operator knows why the misleading "Caverno would like to record" prompt
    # may have appeared.
    local main_sc
    main_sc="$(pick_latest_auth kTCCServiceScreenCapture "$MAIN_BUNDLE_ID")"
    case "$main_sc" in
      0)
        DIAG_FLAGS+=("main_screencapture_denied")
        warn "Main app ($MAIN_BUNDLE_ID) has a DENY Screen Recording entry."
        info "This is harmless after the main app stopped calling Screen"
        info "Recording APIs, but clearing it removes a stale UI entry."
        ;;
      2)
        DIAG_FLAGS+=("main_screencapture_allowed")
        warn "Main app ($MAIN_BUNDLE_ID) has an ALLOW Screen Recording entry."
        info "The main app no longer needs Screen Recording; resetting clears it."
        ;;
      *)
        :
        ;;
    esac
  fi

  # Cross-reference probe outcome from the latest diagnostic export.
  local export_file
  export_file="$(_latest_export)"
  if [[ -n "$export_file" && -r "$export_file" ]]; then
    local probe_state
    probe_state="$(python3 - "$export_file" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    top = d.get("permissions", {}) or {}
    cl = d.get("setupChecklist", {}).get("permissions", {}) or {}
    def pick(key):
        v = top.get(key)
        return cl.get(key) if v is None else v
    succeeded = pick("screenCaptureProbeSucceeded")
    err = pick("screenCaptureProbeError") or ""
    print(f"{'' if succeeded is None else str(succeeded).lower()}|{err}")
except Exception:
    print("|")
PY
    )"
    local probe_succeeded="${probe_state%%|*}"
    local probe_error="${probe_state#*|}"

    # If probe failed because the user declined TCC, that's a strong signal
    # for tccutil reset even if FDA can't read TCC.db directly.
    if [[ "$probe_succeeded" == "false" ]] && [[ "$probe_error" == *"declined"* || "$probe_error" == *"declined TCC"* ]]; then
      DIAG_FLAGS+=("helper_screencapture_deny")
      err "Helper SCShareableContent probe reports the user declined Screen Recording."
    fi

    if $HAS_FDA && [[ "$probe_succeeded" == "false" ]]; then
      local helper_sc
      helper_sc="$(query_tcc "$USER_TCC_DB" \
        | awk -F'\t' -v c="$HELPER_BUNDLE_ID" '$1=="kTCCServiceScreenCapture" && $2==c {print $3; exit}')"
      if [[ "$helper_sc" == "2" ]]; then
        DIAG_FLAGS+=("helper_needs_restart")
        warn "TCC says ALLOW but probe failed. Helper likely needs a restart."
      fi
    fi
  fi

  # De-duplicate diagnostic flags so the fix loop doesn't run identical
  # actions twice (e.g., when both TCC.db and the probe agree on DENY).
  if [[ ${#DIAG_FLAGS[@]} -gt 0 ]]; then
    local seen=()
    local unique=()
    local flag
    for flag in "${DIAG_FLAGS[@]}"; do
      local already=0
      local s
      for s in "${seen[@]+"${seen[@]}"}"; do
        if [[ "$s" == "$flag" ]]; then already=1; break; fi
      done
      if (( already == 0 )); then
        seen+=("$flag")
        unique+=("$flag")
      fi
    done
    DIAG_FLAGS=("${unique[@]}")
  fi

  if [[ ${#DIAG_FLAGS[@]} -eq 0 ]]; then
    ok "No issues detected."
  fi
}

# ----------------------------------------------------------------------------
# Fix
# ----------------------------------------------------------------------------

apply_fix() {
  step "Auto-fix"

  if [[ ${#DIAG_FLAGS[@]} -eq 0 ]]; then
    info "Nothing to fix."
    return
  fi

  local flag
  local need_helper_restart=false
  local helper_reset_done=false
  local main_reset_done=false
  for flag in "${DIAG_FLAGS[@]}"; do
    case "$flag" in
      helper_screencapture_deny | helper_screencapture_missing)
        if $helper_reset_done; then continue; fi
        action "sudo tccutil reset ScreenCapture $HELPER_BUNDLE_ID"
        if sudo tccutil reset ScreenCapture "$HELPER_BUNDLE_ID"; then
          ok "Reset Screen Recording for $HELPER_BUNDLE_ID"
          helper_reset_done=true
          need_helper_restart=true
        else
          err "tccutil reset failed."
        fi
        ;;
      main_screencapture_denied | main_screencapture_allowed | main_screencapture_registered)
        if $main_reset_done; then continue; fi
        action "sudo tccutil reset ScreenCapture $MAIN_BUNDLE_ID"
        if sudo tccutil reset ScreenCapture "$MAIN_BUNDLE_ID"; then
          ok "Reset Screen Recording for $MAIN_BUNDLE_ID"
          main_reset_done=true
        else
          err "tccutil reset failed."
        fi
        ;;
      helper_wrong_path)
        if [[ -x "$PREFLIGHT_SCRIPT" ]]; then
          action "$PREFLIGHT_SCRIPT --skip-clean"
          "$PREFLIGHT_SCRIPT" --skip-clean
        else
          warn "Preflight script not found: $PREFLIGHT_SCRIPT"
        fi
        need_helper_restart=true
        ;;
      helper_needs_restart)
        need_helper_restart=true
        ;;
    esac
  done

  # After resetting TCC or fixing paths, the helper must re-read state.
  # Restart it so the next probe runs fresh.
  if $need_helper_restart; then
    action "pkill -f 'Caverno Computer Use.app/Contents/MacOS/Caverno Computer Use'"
    pkill -f 'Caverno Computer Use\.app/Contents/MacOS/Caverno Computer Use' 2>/dev/null || true
    sleep 2
    if pgrep -f 'Caverno Computer Use\.app/Contents/MacOS/Caverno Computer Use' >/dev/null; then
      ok "Helper respawned by launchd."
    else
      warn "Helper not running. It will start on the next IPC request from Caverno."
    fi
  fi
}

# ----------------------------------------------------------------------------
# Next steps
# ----------------------------------------------------------------------------

print_next_steps() {
  step "Next steps"

  local needs_manual_grant=false
  local flag
  for flag in "${DIAG_FLAGS[@]+"${DIAG_FLAGS[@]}"}"; do
    case "$flag" in
      helper_screencapture_deny | helper_screencapture_missing)
        needs_manual_grant=true
        ;;
    esac
  done

  if $FIX && $needs_manual_grant; then
    info "1. Open Caverno's Computer Use settings."
    info "2. Click 'Open Screen Recording' to surface the macOS prompt."
    info "3. When prompted, click ${C_GREEN}Allow${C_RESET} for ${C_BOLD}Caverno Computer Use${C_RESET}."
    info "4. Re-run this script to verify."
  elif ! $FIX && [[ ${#DIAG_FLAGS[@]} -gt 0 ]]; then
    info "Re-run with --fix to apply auto-corrections."
    info "  $SCRIPT_DIR/macos_tcc_diagnose.sh --fix"
  elif [[ ${#DIAG_FLAGS[@]} -eq 0 ]]; then
    info "Caverno Computer Use TCC state looks healthy."
  fi

  if ! $HAS_FDA; then
    info ""
    info "(For richer diagnostics, grant Full Disk Access to this terminal.)"
  fi
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

HAS_FDA=false

printf '%s\n' "${C_BOLD}Caverno TCC diagnose${C_RESET}"
info "main worktree : $MAIN_WORKTREE"
if $FIX; then
  info "mode          : diagnose + fix"
else
  info "mode          : diagnose only"
fi

inspect_signing
inspect_running_processes
inspect_tcc_db
inspect_helper_probe
diagnose

if $FIX; then
  apply_fix
fi

print_next_steps
