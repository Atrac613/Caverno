# macOS Computer Use Polish Review Summary

This summary captures the M13 polish branch state before merging Computer Use
review hardening back to `main`.

## Review Scope

- Computer Use entry points stay behind `Settings > Advanced`.
- The root Settings list shows `Advanced`, not a top-level Computer Use status
  panel.
- The Computer Use page keeps helper-owned desktop control copy and primary
  actions visible.
- Detailed runtime fields, saved smoke reports, and redacted audit entries stay
  behind the collapsed `Diagnostics` section.
- `Caverno Computer Use.app` remains the helper-owned boundary for macOS
  permissions and desktop actions.

## Automation-Safe Verification

Use the post-merge sanity runner for static review checks:

```bash
bash tool/run_macos_computer_use_post_merge_sanity.sh
```

Use `--print-commands` to inspect the command list without running checks:

```bash
bash tool/run_macos_computer_use_post_merge_sanity.sh --print-commands
```

The runner covers static analysis, focused Computer Use tests, and a debug
macOS build. It must not grant TCC, edit TCC, operate System Settings, launch
apps, move the pointer, click, type, record audio, or run desktop actions.

## Manual-Only Follow-Ups

Request user-operated evidence only when runtime sign-off is needed:

- Manual TCC runtime sign-off.
- Helper foreground and permission overlay checks.
- Smoke sequence execution.
- Desktop action canary against the safe fixture target.

## Next Milestone

After M13 merges, M14 expands real-app observe-only canaries. Those canaries are
for visual classification of targets, text fields, submission boundaries, and
confirmation requirements. They must not click, type, submit, post, purchase, or
otherwise mutate external state.
