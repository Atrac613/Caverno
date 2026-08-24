# SEC4.3e HTML Preview Active-Content Containment

Status: completed 2026-08-24.

## Task

- Goal: prevent a malicious or model-generated HTML preview from reading
  arbitrary project files or sending project data outside its loopback origin.
- User-visible behavior: the selected HTML entry and ordinary same-origin web
  assets continue to load, while source/configuration files and external
  subresources fail closed.
- Non-goals: sanitizing or rewriting project HTML, disabling JavaScript, adding
  a general-purpose browser, or changing non-preview file tools.

## Context

- Affected components: the loopback preview server, preview session startup,
  browser resource interception, and focused server/browser/session tests.
- Related docs: `docs/security_followup_review_2026-08-24.md` SA-20 and
  `docs/security_audit_2026-08-14.md`.
- Release gate: P0 follow-up whenever HTML Preview is shipped.

## Implementation Notes

- Bind the server to the selected entry and expose only browser-consumable
  assets within that entry directory.
- Apply a restrictive CSP plus no-referrer, no-sniff, and no-store headers to
  every response, including failures.
- Keep the existing top-level navigation decision and reject non-preview
  subresource requests through the WebView interception callback when the
  platform reports them.
- Treat server policy and CSP as the primary cross-platform boundary;
  interception is defense in depth because callback coverage varies by
  platform.
- No generated files, migrations, or new dependencies are required.

## Similar-Pattern Search

- Search terms: `HtmlPreviewStaticServer`, `openLocalPreview`,
  `shouldOverrideUrlLoading`, `shouldInterceptRequest`, `Content-Security-Policy`,
  and `localPreviewOrigin`.
- Files inspected: preview detector/session/server/provider, browser session
  service, WebView host, and their focused tests.
- Follow-up tasks found: none within SEC4.3e; application-owned input size limits
  remain SEC4.3f.

## Acceptance Criteria

- The selected HTML entry and same-directory JS, CSS, image, font, media, and
  WebAssembly assets load from the preview origin.
- Source, credential, configuration, map, JSON, and text files outside the
  declared preview surface return 404.
- CSP blocks connect, form, frame, object, worker, manifest, and external
  script/style/image/font/media channels.
- All responses use `Referrer-Policy: no-referrer`,
  `X-Content-Type-Options: nosniff`, and `Cache-Control: no-store`.
- The WebView interception policy rejects HTTP(S) subresources outside the
  active preview origin while retaining local `data:` and `blob:` assets.

## Verification

```bash
tool/codex_verify.sh --coverage \
  --test test/features/chat/domain/services/html_preview_static_server_test.dart \
  --test test/features/chat/domain/services/html_preview_session_controller_test.dart \
  --test test/core/services/browser_session_service_test.dart \
  --test test/features/chat/presentation/widgets/html_preview_control_section_test.dart
```

## Handoff Notes

- Summary: the preview server now binds to the selected entry directory,
  exposes only browser-consumable assets after canonical symlink resolution,
  and applies a restrictive CSP plus no-referrer, no-sniff, no-store, and DNS
  prefetch controls. Platform-reported WebView subresources are independently
  restricted to the active preview origin.
- Tests run: `fvm flutter analyze --no-pub` passed. Four focused suites passed
  26 tests, both normally and with coverage enabled.
- Coverage or low-coverage notes: focused coverage was 80.00% (120/150) for the
  static server, 81.94% (59/72) for the session controller, and 30.89%
  (139/450) for the broader browser service.
- Risks or follow-ups: platform interception is defense in depth; response
  policy and the reduced server surface remain authoritative.
