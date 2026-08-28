# SEC4.7c Supply-Chain Residuals

Status: completed on 2026-08-28.

## Task

- Goal: close the four SA-16 supply-chain controls that SEC4.7a and SEC4.7b left
  open, so no unreviewed third-party code, unpinned toolchain, or unverified
  build distribution can enter a release path.
- User-visible behavior: unchanged. CI, the weekly SDK update, and the manual
  Plan Mode smoke run the same steps against the same reviewed code.
- Non-goals: changing job structure, adding new workflows, or upgrading any
  pinned version. Pins record what already runs today.

## Context

- Affected components: `.github/workflows/flutter_sdk_update.yml`,
  `.github/workflows/plan_mode_smoke_manual.yml`,
  `android/gradle/wrapper/gradle-wrapper.properties`, `.github/dependabot.yml`,
  and the supply-chain regression test.
- Related finding: SA-16 in `docs/security_audit_2026-08-14.md`.
- Release gate: SEC4.7 supply-chain and release hardening. With this slice the
  six SA-16 controls are complete: immutable actions, minimized write
  credentials, pinned automation tooling, npm monitoring, the Gradle
  distribution checksum, and fail-closed Android release signing (SEC4.7a).

## Changes

### Immutable actions in the two remaining workflows

`flutter_sdk_update.yml` and `plan_mode_smoke_manual.yml` were the last mutable
tag consumers. Every major tag they referenced currently resolves to the exact
commit already reviewed for SEC4.7b, so pinning is behavior-preserving.

| Action | Version | Commit | Workflow |
|---|---|---|---|
| `actions/checkout` | `v7.0.1` | `3d3c42e5aac5ba805825da76410c181273ba90b1` | both |
| `actions/setup-java` | `v5.7.0` | `b6effb05e454b25005698d916606bdc6ffcbf961` | smoke |
| `subosito/flutter-action` | `v2.23.0` | `1a449444c387b1966244ae4d4f8c696479add0b2` | both |
| `peter-evans/create-pull-request` | `v8.1.1` | `5f6978faf089d4d20b00c7766989d076bb2fc7f1` | SDK update |

Tag-to-commit mappings were resolved from each action's official Git remote on
2026-08-28. Resolve the immutable SHA again before changing any pin.

### Minimized write credentials

The SDK-update job held `contents: write` and `pull-requests: write` while every
write it performs already runs through `AUTOMATION_GITHUB_TOKEN` inside
`create-pull-request`. A preceding step fails the job closed when that secret is
absent, so the job token no longer needs write scope and is now `contents: read`.
This was the highest-value item in the slice: a mutable tag in a write-capable
job could push to `main`.

### Pinned automation tooling

`dart pub global activate fvm` resolved the latest FVM at run time. It is now
pinned to `4.1.2`, the version this repository is developed against, so CI and
local `fvm use` cannot diverge silently.

### Gradle distribution checksum

`gradle-wrapper.properties` now carries
`distributionSha256Sum=efe9a3d147d948d7528a9887fa35abcf24ca1a43ad06439996490f77569b02d1`.
The value was confirmed twice: from `services.gradle.org` over HTTPS, and by
hashing the already-cached `gradle-8.14-all.zip` that has built this project.

### npm dependency monitoring

Dependabot covered `pub` and `github-actions` only, leaving
`services/notification_relay` — a deployed Cloud Functions relay with
`firebase-admin` and `firebase-functions` — unmonitored. An `npm` policy for
that directory now runs on the same weekly schedule.

## Similar-Pattern Search

- Search terms: `uses:`, `@v`, `permissions:`, `pub global activate`,
  `distributionUrl`, `package.json`, `package-ecosystem`.
- Files inspected: every workflow under `.github/workflows`, every tracked
  `package.json`, both Gradle wrapper properties candidates (only one is
  tracked), `.github/dependabot.yml`, the security audit, and the roadmap.
- Follow-up tasks found: none for SA-16. Dependabot still cannot update a SHA
  pin's version comment automatically; the comment is asserted by the
  regression test instead.

## Acceptance Criteria

- Every external action in every workflow uses a 40-character commit SHA with an
  exact semantic-version maintenance comment.
- No job holds write scope it does not use.
- The FVM version installed by CI is pinned.
- The Gradle distribution is checksum-verified.
- Every tracked npm package has a Dependabot update policy.
- All five controls are regression-tested, and a new workflow, a new action, a
  new npm package, or a removed checksum fails the gate.

## Verification

```bash
fvm flutter test --no-pub test/tool/supply_chain_pinning_test.dart
```

Negative controls (each reverted after the run) confirmed the gate detects a
known-bad state rather than passing vacuously:

| Injected defect | Failing test |
|---|---|
| Restore a mutable `actions/checkout@v7` tag | pins every external action to an approved commit SHA |
| Substitute an unreviewed 40-hex SHA | pins every external action to an approved commit SHA |
| Delete `distributionSha256Sum` | downloads over HTTPS and verifies a distribution checksum |
| Delete the npm Dependabot policy | monitors every tracked npm package |

`cd android && ./gradlew --version` succeeds with the checksum in place.

## Handoff Notes

- Summary: SA-16 is closed. Seventeen external action invocations across three
  workflows resolve to five reviewed immutable commits, the write-capable job
  runs on a read-only job token, FVM and the Gradle distribution are pinned and
  verified, and the deployed npm relay is monitored.
- Tests run: the supply-chain regression gate with four negative controls, and a
  real Gradle wrapper invocation.
- Risks or follow-ups: the `contents: read` reduction cannot be exercised until
  the weekly SDK-update workflow next runs or is dispatched manually. If
  `AUTOMATION_GITHUB_TOKEN` turns out to be unset in this repository, that
  workflow already fails closed on its own preflight step, before any push.
- Supersedes `test/tool/flutter_ci_action_pinning_test.dart`, which was renamed
  to `test/tool/supply_chain_pinning_test.dart` and generalized to every
  workflow so the allowlist is not duplicated.
