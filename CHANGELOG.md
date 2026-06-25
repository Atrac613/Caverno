# Changelog

All notable changes to Caverno will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.3.9] - 2026-06-25

### Fixed
- macOS: Fix `NSRunningApplication` crash when app is not in Dock (use `NSWorkspace.shared.runningApplications` instead)
