# Scratchpad — All Open Issues + Deployment Scripts

## Objective
Address all 4 open GitHub issues and create deployment scripts for App Store Connect.

## Issues Analyzed
1. **#1 AppConfig not honored** — ViewModel didn't react to UserDefaults changes after init. Fixed by adding NotificationCenter observation and `reloadManagedSettingsIfNeeded()`. Also fixed `retryTimeout` edge case (`== 0` → `> 0`).
2. **#2 Retry logic** — Was basic timer-only checking `currentItem == nil`. Enhanced with AVPlayer KVO status observation, `retryCount` tracking, `maxRetries` support, and proper observer teardown.
3. **#3 Fullscreen on launch** — `scheduleAutoPlayPresentation()` was fragile with race conditions. Rewrote with bounded retry (3 attempts, 1s delay).
4. **#4 Multiple streams** — Preset system already existed. Enhanced display with `displayName(for:)` and labeled preset entries.

## Deployment Scripts Created
- build.sh, run.sh, test.sh, archive.sh, upload.sh, deploy.sh, version-bump.sh
- All zsh-compatible, colorful output, --dry-run support, interactive prompts

## Verification
- Swift typecheck passed (only pre-existing deprecation warning in OnChangeOld.swift)
- All scripts verified via --dry-run
- 7 new test functions added
- PR #6 created and pushed

## Note
- xcodebuild has IDESimulatorFoundation plugin loading issue on this machine (Xcode 26.4)
- Code compiles via `xcrun swiftc -typecheck` against tvOS SDK
- Full test execution requires simulator plugin fix (`xcodebuild -runFirstLaunch`)
