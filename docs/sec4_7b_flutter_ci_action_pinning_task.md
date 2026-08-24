# SEC4.7b Flutter CI Action Pinning

Status: completed on 2026-08-23.

## Task

- Goal: prevent mutable upstream GitHub Action tags from changing the code
  executed by the pull-request CI workflow without a repository review.
- User-visible behavior: pull-request CI behavior is unchanged, but every
  external action is immutable until its reviewed SHA is updated.
- Non-goals: changing CI jobs, pinning the separate SDK-update and manual-smoke
  workflows, or pinning FVM and the Gradle distribution.

## Context

- Affected components: `.github/workflows/flutter_ci.yml`, its regression test,
  roadmap, and security audit.
- Related finding: SA-16 in `docs/security_audit_2026-08-14.md`.
- Release gate: SEC4.7 supply-chain and release hardening.

## Implementation Notes

- Resolve each existing major-version tag against the action's official Git
  remote and use its 40-character commit SHA.
- Retain the exact semantic version as an inline maintenance comment.
- Keep action inputs, job permissions, triggers, and behavior unchanged.
- Use an explicit allowlist regression so a new action or a floating tag fails
  repository verification.

## Pinned Actions

| Action | Version | Commit |
|---|---|---|
| `actions/checkout` | `v7.0.1` | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/setup-java` | `v5.7.0` | `b6effb05e454b25005698d916606bdc6ffcbf961` |
| `subosito/flutter-action` | `v2.23.0` | `1a449444c387b1966244ae4d4f8c696479add0b2` |
| `actions/upload-artifact` | `v7.0.1` | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |

The tag-to-commit mappings were verified from the four official Git remotes on
2026-08-23. Review the upstream release and resolve the immutable SHA again
before changing any pin.

## Similar-Pattern Search

- Search terms: `uses:`, `@v`, action repository names, workflow permissions,
  FVM installation, and release automation.
- Files inspected: every workflow under `.github/workflows`, the security audit,
  roadmap, and existing workflow compatibility tests.
- Follow-up tasks found: `flutter_sdk_update.yml` and
  `plan_mode_smoke_manual.yml` still use mutable tags. The write-capable update
  workflow also needs pinned FVM and tighter credential exposure.

## Acceptance Criteria

- Every external action in `flutter_ci.yml` uses a 40-character commit SHA.
- Each pin has an exact semantic-version maintenance comment.
- The approved action, SHA, version, and occurrence count are regression-tested.
- CI triggers, permissions, job structure, and action inputs remain unchanged.

## Verification

```bash
fvm flutter test --no-pub test/tool/flutter_ci_action_pinning_test.dart
fvm flutter analyze --no-pub
tool/codex_verify.sh --no-codegen \
  --test test/tool/flutter_ci_action_pinning_test.dart
```

## Handoff Notes

- Summary: all ten external-action invocations in pull-request CI now resolve to
  four reviewed, immutable commits.
- Tests run: focused workflow regression, static analysis, and the repository
  verification gate.
- Risks or follow-ups: Dependabot cannot update SHA comments automatically
  without a matching GitHub Actions update policy. Continue SA-16 by pinning the
  two remaining workflows, then configure update monitoring.
