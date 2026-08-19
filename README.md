# Pause

Pause is a personal iOS app that interrupts reflexive entry into selected apps with a deliberate pause and a daily session allowance.

**Target:** The deployment minimum is iOS 26.5. Qualification is pending on the iPhone 16 running its exact installed iOS 26.x version. iOS 27 will require a separate future qualification after its release and matching Xcode toolchain are available; support is not yet promised.

**Setup:** Copy `Local.xcconfig.example` to `Local.xcconfig`, set `DEVELOPMENT_TEAM`, run `xcodegen generate`, and open `Pause.xcodeproj`.

**Test:** `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

**Docs:** [Product requirements](docs/product-requirements.md) · [Approved design](docs/design/pause-app.md) · [Phase 1 plan](docs/plans/phase-1-core-action-loop.md) · [Device acceptance](docs/testing/phase-1-device-acceptance.md)
