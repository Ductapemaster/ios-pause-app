# Pause

Pause is a personal iOS app that interrupts reflexive entry into selected apps with a deliberate pause and a daily session allowance.

**Target:** The deployment minimum is iOS 26.5, qualified on an iPhone 16 Pro running iOS 26.6. iOS 27 will require a separate qualification after its release and matching Xcode toolchain are available; support is not yet promised.

**Setup:** Copy `Local.xcconfig.example` to `Local.xcconfig`, set `DEVELOPMENT_TEAM`, run `xcodegen generate`, and open `Pause.xcodeproj`.

**App icon:** Generated, not hand-drawn — `python3 Tools/make_app_icon.py` re-renders `Sources/Pause/Assets.xcassets/AppIcon.appiconset/AppIcon.png` from the constants at the top of the script. Requires Pillow.

**Test:** `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

**Docs:** [Start here](docs/README.md) — the model and the why. [Product requirements](docs/product-requirements.md) · [Architecture](docs/design/pause-app.md) · [Roadmap](docs/ROADMAP.md) · [Resume pointer](docs/status.md)
