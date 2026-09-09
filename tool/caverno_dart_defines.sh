#!/usr/bin/env bash
#
# tool/caverno_dart_defines.sh — shared resolver for environment-owned Flutter
# build defines.
#
# Why:
#   CAVERNO_NOTIFICATION_RELAY_URL is read at compile time by
#   lib/features/remote_coding/data/remote_coding_notification_relay_providers.dart
#   via String.fromEnvironment. When it is absent the relay client provider
#   silently resolves to null, so the desktop sends no push notifications at
#   all and the mobile app reports "Notification relay is not configured."
#   A build that forgets the define therefore looks healthy while push is
#   entirely dead. Every build path routes through this helper so the define
#   cannot be forgotten in one path and remembered in another.
#
#   The value lives in a gitignored file rather than in source because this
#   repository is public: hardcoding the origin would point every fork's build
#   at the maintainer's own relay.
#
# Usage (source, do not execute):
#   source "$WORKTREE/tool/caverno_dart_defines.sh"
#   caverno_load_dart_define_args "$WORKTREE" [warn]
#   flutter build ... "${CAVERNO_DART_DEFINE_ARGS[@]}"
#
# Override the file location with CAVERNO_DART_DEFINES_FILE.

# Populates the CAVERNO_DART_DEFINE_ARGS array with the
# --dart-define-from-file argument, or leaves it empty when no defines file is
# present.
#
# The second argument selects what absence means:
#   (omitted) stay silent  — callers that do not produce a testable binary
#   warn      one-line stderr notice — local run/build
#   require   exit 1       — release builds, where shipping inert push is worse
#                            than failing the build. Override for a deliberate
#                            push-less release with
#                            CAVERNO_ALLOW_MISSING_DART_DEFINES=1.
caverno_load_dart_define_args() {
  local worktree="${1:-$PWD}"
  local on_absent="${2:-}"
  local defines_file="${CAVERNO_DART_DEFINES_FILE:-${worktree}/firebase/dart_defines.json}"

  CAVERNO_DART_DEFINE_ARGS=()
  if [[ -f "${defines_file}" ]]; then
    CAVERNO_DART_DEFINE_ARGS=(--dart-define-from-file="${defines_file}")
    return 0
  fi

  if [[ "${on_absent}" == "require" \
        && "${CAVERNO_ALLOW_MISSING_DART_DEFINES:-0}" != "1" ]]; then
    cat >&2 <<EOF
Error: ${defines_file} not found.

A release built without CAVERNO_NOTIFICATION_RELAY_URL resolves the Remote
Coding relay client to null: the desktop sends no push notifications and the
mobile app reports "Notification relay is not configured." Nothing else fails,
so the defect only surfaces on a device.

Create the file (values are environment-owned and gitignored):
  mkdir -p "${worktree}/firebase"
  cat > "${defines_file}" <<'JSON'
  { "CAVERNO_NOTIFICATION_RELAY_URL": "https://<project>.web.app" }
JSON

To release deliberately without push:
  CAVERNO_ALLOW_MISSING_DART_DEFINES=1 \$0 ...
EOF
    return 1
  fi

  if [[ "${on_absent}" == "warn" || "${on_absent}" == "require" ]]; then
    echo "Warning: ${defines_file} not found; building without CAVERNO_NOTIFICATION_RELAY_URL." >&2
    echo "         Remote Coding push notifications will be inert in this build." >&2
    echo "         See docs/remote_coding_fcm_release_gate.md." >&2
  fi
  return 0
}
