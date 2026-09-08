# Caverno v1.3.27

> Release date: 2026-09-08

## Summary

This release fixes macOS Remote Coding TLS identity storage in distributed builds.

## Fixes

- Preserve Keychain entitlements when re-signing the macOS app for Sparkle
  distribution, fixing Remote Coding TLS identity storage failures caused by
  missing signing entitlements.
- Improve the error guidance for Remote Coding Keychain entitlement failures.
- Add release signing checks and regression coverage for app entitlements.

## Version

- `1.3.27+40`
- Platforms: iOS, macOS
- Source: Git history after `1.3.26+38` through `8a42dc4ab`.
