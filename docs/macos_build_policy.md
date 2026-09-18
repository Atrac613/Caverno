# macOS Build Policy

Extracted from `CLAUDE.md`. `CLAUDE.md` keeps the rule; the reasoning, the
wrapper details and the recovery scripts live here.


This repo is regularly checked out as multiple git worktrees (feature branches under `caverno-worktrees/`, AI-agent sandboxes under `~/.codex/worktrees/` and `~/.claude/worktrees/`, milestone branches under `/private/tmp/caverno-m*`, etc.). Each worktree that builds the macOS app emits its own `Caverno.app` claiming `com.noguwo.apps.caverno`. macOS LaunchServices then routes launchd / XPC requests to whichever copy was registered last, TCC grants drift across helper paths, and the Computer Use helper reports `helper_bundle_path_mismatch`.

**Rule:** macOS builds (`flutter build macos`, `flutter run -d macos`, etc.) are allowed only in one worktree, designated as canonical via a gitignored `.macos-canonical` sentinel.

## Designate the canonical worktree

```bash
# Run this once in the worktree that should own macOS builds:
touch .macos-canonical
```

## Build macOS through tool/safe-flutter

The wrapper refuses macOS subcommands when `.macos-canonical` is absent, and otherwise delegates to `fvm flutter` (or `flutter`):

```bash
tool/safe-flutter run -d macos
tool/safe-flutter build macos --release
```

Non-macOS subcommands (`analyze`, `test`, `pub get`, `build apk`, `build ipa`, ...) pass through unchanged, so any worktree can still run lint and tests.

The wrapper is also where compile-time defines are injected: build provenance
(`CAVERNO_BUILD_*`) and the Remote Coding relay origin
(`CAVERNO_NOTIFICATION_RELAY_URL`, from the gitignored
`firebase/dart_defines.json` via `tool/caverno_dart_defines.sh`). **A binary
built with bare `flutter` sends no push notifications** — the relay client
resolves to `null` and delivery is skipped with no error anywhere except a
log line and a warning on the desktop Remote Coding settings page. Use
`tool/safe-flutter` for anything you intend to test on a device. See
"Supplying the relay origin" in `docs/remote_coding_fcm_release_gate.md`.

For convenience, optionally add to your shell init:

```bash
alias caverno-flutter='/Users/<you>/Documents/Workspace/Flutter/caverno/tool/safe-flutter'
```

One-off bypass without designating the worktree:

```bash
FLUTTER_ALLOW_MACOS_HERE=1 tool/safe-flutter build macos --release
```

## Recovery scripts

If multiple worktrees have already produced conflicting `Caverno.app` bundles, or TCC reports the helper as missing permissions:

```bash
# 1. Clean stale Caverno*.app artifacts + LaunchServices entries.
tool/macos_dev_preflight.sh

# 2. Diagnose TCC state. Grant Full Disk Access to the terminal for the
#    richer TCC.db view; the script still runs (via tccutil) without it.
tool/macos_tcc_diagnose.sh

# 3. Auto-fix detected issues (sudo tccutil reset + helper restart).
tool/macos_tcc_diagnose.sh --fix
```

After recovery, the canonical worktree should be the only one that holds a Debug `Caverno.app`. Run `tool/macos_dev_preflight.sh --dry-run` in other worktrees periodically to confirm nothing else has been built.
