# Caverno v1.3.29

> Release date: 2026-09-09

## Summary

This release improves Remote Coding approval delivery and operational logging
across iOS and macOS.

## Features

- Deliver blocked Remote Coding turns to entitled paired devices.
- Let users answer pushed Remote Coding approvals after reconnecting.
- Add logging settings for controlling and deleting local log files.
- Add a composer preference for model thinking depth.

## Fixes

- Route pushed approval actions from iOS into Dart and launch the app in the
  foreground when an approval needs an answer.
- Wait for pushed approvals to return before completing the corresponding
  response and withdraw approvals no longer held by the desktop.
- Write and export app logs on iOS and Android.
- Resolve notification relay configuration from build defines and prevent
  releases with App Check attestation disabled.
- Propagate build defines consistently to iOS and macOS release builds.

## Version

- `1.3.29+42`
- Platforms: iOS, macOS
- Source: Git history after `1.3.28+41` through `1021760fa`.
