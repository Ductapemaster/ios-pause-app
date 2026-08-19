# Pause

Pause is a personal iOS app that interrupts reflexive entry into selected apps with a deliberate pause and a daily session allowance.

**Target:** iPhone 16 running iOS 26.5 or later. iOS 27 qualification is intended after the release and matching Xcode toolchain are available; support has not been tested or promised.

**Setup:** Copy `Local.xcconfig.example` to `Local.xcconfig`, set `DEVELOPMENT_TEAM`, run `xcodegen generate`, and open `Pause.xcodeproj`.

**Test:** `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

**Docs:** [Product requirements](docs/product-requirements.md) · [Approved design](docs/design/pause-app.md) · [Phase 1 plan](docs/plans/phase-1-core-action-loop.md) · [Device acceptance](docs/testing/phase-1-device-acceptance.md)
