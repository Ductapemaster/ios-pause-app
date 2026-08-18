# Phase 1 Core Action Loop Implementation Plan

> **Execution:** Follow this plan task by task. Use test-driven development for business logic and run each listed verification before committing. Stop at a device gate when its pass condition is not met; do not work around a failed Screen Time behavior by broadening the product.

**Goal:** Ship the smallest complete Pause loop on iPhone: select any eligible apps, configure per-app allowances, keep them shielded, require a foreground pause, grant a timed session, return automatically when a public route is available, and restore the shield when the session expires.

**Architecture:** A SwiftUI app owns configuration and the foreground interaction. A pure `PauseCore` module owns decisions and state transitions without reading the clock or storage. Shared integration code owns App Group persistence and grant ordering and is compiled into the app and extensions that need it. Three Screen Time extensions display the shield, record entry intent, and restore expired sessions. Shared App Group storage is split into configuration, one runtime file per rule, and a narrow shield-intent handoff.

**Tech stack:** Swift 6, SwiftUI, FamilyControls, ManagedSettings, ManagedSettingsUI, DeviceActivity, XCTest, XcodeGen 2.46, Xcode 26.6, iOS 26.5+

**Approved design:** [`docs/design/pause-app.md`](../design/pause-app.md)

**Product requirements:** [`docs/product-requirements.md`](../product-requirements.md)

## Scope guardrails

Phase 1 includes only the core action loop:

- Screen Time authorization.
- Apple’s `FamilyActivityPicker`, with multiple selected applications.
- One rule per selected application.
- Per-app sessions per day and session length.
- One global pause duration.
- A midnight local-time logical-day reset.
- Shields applied by default.
- Foreground-only pause with interruption cancellation.
- Timed session grants and automatic shield restoration.
- Automatic return for Instagram when its public URL route succeeds.
- Manual return instructions for apps without a supported route.
- Visible repair behavior for state that cannot be read safely.

The following are not part of this plan:

- Custom reset times or weekday/weekend reset schedules.
- Time windows.
- Behavior history, analytics, streaks, reports, or a Device Activity report extension.
- Notifications as an expiry mechanism.
- A hand-maintained catalog of installed apps.
- Private app-launch APIs, token introspection, or heuristics that infer app identity from opaque token bytes.
- Compatibility scaffolding for storage formats that never shipped.

## Reuse boundary

The previous repository is evidence and a source of narrow implementation patterns, not a migration source. Consult these files while implementing the matching task:

- `~/Workspaces/ios-pause-app-claude/project.yml`
- `~/Workspaces/ios-pause-app-claude/Sources/Shared/SharedStore.swift`
- `~/Workspaces/ios-pause-app-claude/Sources/ShieldActionExtension/ShieldActionExtension.swift`
- `~/Workspaces/ios-pause-app-claude/Sources/ShieldConfigExtension/ShieldConfigExtension.swift`
- `~/Workspaces/ios-pause-app-claude/Sources/MonitorExtension/MonitorExtension.swift`
- `~/Workspaces/ios-pause-app-claude/Sources/PauseCore/`
- `~/Workspaces/ios-pause-app-claude/Tests/PauseCoreTests/`

Reuse or adapt only:

- XcodeGen target, entitlement, App Group, and extension wiring.
- Apple-token persistence through `Codable`.
- `.openParentalControlsApp` plus the measured App Group shield-intent handoff.
- Pure allowance and session-state concepts whose behavior still matches this design.
- Device Activity expiry scheduling, including the short-session warning technique.
- Tests that assert current Phase 1 behavior.

Do not copy the old source tree. In particular, do not bring over spike screens or logs, notifications, the usage report extension, old storage migrations, a required URL on every rule, token-description heuristics, or speculative budget and history models.

## Fixed identifiers and conventions

Use these values throughout the project:

```text
App Group:                group.com.koubalabs.pause
App bundle identifier:    com.koubalabs.pause
Monitor extension:        com.koubalabs.pause.monitor
Shield config extension:  com.koubalabs.pause.shieldconfig
Shield action extension:  com.koubalabs.pause.shieldaction
Deployment target:        iOS 26.5
Session activity prefix:  session.
Configuration file:       configuration.json
Runtime directory:        runtime/
Shield intent defaults:   shield-intent-v1
```

The XcodeGen `project.yml` is the source of truth for the generated Xcode project. Commit `project.yml`; ignore `Pause.xcodeproj` and local signing configuration.

## Task 1: Scaffold the four targets and test harness

**Files:**

- Create: `.gitignore`
- Create: `Local.xcconfig.example`
- Create: `project.yml`
- Create: `Config/Pause.entitlements`
- Create: `Config/MonitorExtension.entitlements`
- Create: `Config/ShieldConfigExtension.entitlements`
- Create: `Config/ShieldActionExtension.entitlements`
- Create: `Sources/Pause/PauseApp.swift`
- Create: `Sources/PauseCore/PauseCore.swift`
- Create: `Sources/PauseCore/SessionActivityName.swift`
- Create: `Sources/Shared/SharedIdentifiers.swift`
- Create: `Sources/MonitorExtension/MonitorExtension.swift`
- Create: `Sources/ShieldConfigExtension/ShieldConfigExtension.swift`
- Create: `Sources/ShieldActionExtension/ShieldActionExtension.swift`
- Create: `Tests/PauseCoreTests/SmokeTests.swift`
- Create: `Tests/SharedTests/SmokeTests.swift`

### 1.1 Write the project contract

Create `SharedIdentifiers` before target wiring so every target uses one identifier source:

```swift
import Foundation

public enum SharedIdentifiers {
    public static let appGroup = "group.com.koubalabs.pause"
    public static let shieldIntentKey = "shield-intent-v1"
}
```

Put `SharedIdentifiers.swift` in the `Shared` source set compiled into the app and all three extensions. Keep the activity-name contract in `PauseCore` so its parsing is unit tested:

```swift
import Foundation

public enum SessionActivityName {
    public static let prefix = "session."

    public static func sessionActivityName(for ruleID: UUID) -> String {
        prefix + ruleID.uuidString.lowercased()
    }

    public static func ruleID(fromSessionActivityName name: String) -> UUID? {
        guard name.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(prefix.count)))
    }
}
```

### 1.2 Add the smoke test first

Write `SmokeTests.testCoreModuleLoads` and confirm generation fails because no project exists:

```swift
import XCTest
@testable import PauseCore

final class SmokeTests: XCTestCase {
    func testCoreModuleLoads() {
        XCTAssertEqual(PauseCore.version, 1)
    }
}
```

Add a second smoke test under `Tests/SharedTests` that asserts `SharedIdentifiers.appGroup`. This test target compiles `Sources/Shared` directly and depends on `PauseCore`; production targets continue using the old repository's proven pattern of compiling the same shared source set into each process.

Run:

```bash
xcodegen generate
```

Expected before `project.yml` exists: failure reporting that no project spec is available.

### 1.3 Add the minimum target implementations

Implement `PauseCore.version` and a `PauseApp` scene that renders `Text("Pause")`. Give each extension the correct principal class and the minimum compilable override:

- `DeviceActivityMonitor` subclass for the monitor.
- `ShieldConfigurationDataSource` subclass for shield rendering.
- `ShieldActionDelegate` subclass for shield actions.

Do not add product behavior in this task.

### 1.4 Define the XcodeGen project

Adapt only the target wiring from the old `project.yml`. Define:

- `PauseCore`: static-library target with `Sources/PauseCore` only.
- `Pause`: iOS application target with `Sources/Pause`, `Sources/Shared`, and a dependency on `PauseCore`.
- `MonitorExtension`: app-extension target with `Sources/MonitorExtension`, `Sources/Shared`, `PauseCore`, FamilyControls, ManagedSettings, and DeviceActivity.
- `ShieldConfigExtension`: app-extension target with `Sources/ShieldConfigExtension`, `Sources/Shared`, `PauseCore`, ManagedSettings, and ManagedSettingsUI.
- `ShieldActionExtension`: app-extension target with `Sources/ShieldActionExtension`, `Sources/Shared`, `PauseCore`, ManagedSettings, and FamilyControls.
- `PauseCoreTests`: unit-test target with `Tests/PauseCoreTests` and a dependency on `PauseCore`.
- `PauseSharedTests`: unit-test target with `Tests/SharedTests`, `Sources/Shared`, and a dependency on `PauseCore`.
- `PauseUnitTests`: shared scheme that runs both unit-test targets.

Embed all three extensions in `Pause`. Set Swift 6 and iOS 26.5 for every target. Point signing settings at an ignored `Local.xcconfig`; document only `DEVELOPMENT_TEAM = YOUR_TEAM_ID` in `Local.xcconfig.example`.

Each entitlement file must contain the App Group. The app and all Screen Time extensions must also contain the Family Controls entitlement where Apple requires it. Preserve the exact capability shape proven by the old repository rather than inventing another target arrangement.

### 1.5 Generate and verify

Run:

```bash
xcodegen generate
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Expected: the smoke test passes and the app plus all embedded extensions compile.

### 1.6 Commit

```bash
git add .gitignore Local.xcconfig.example project.yml Config Sources Tests
git commit -m "build: scaffold Pause app and Screen Time extensions"
```

## Task 2: Implement the rule and runtime domain

**Files:**

- Create: `Sources/PauseCore/CalendarDay.swift`
- Create: `Sources/PauseCore/AppRule.swift`
- Create: `Sources/PauseCore/GlobalSettings.swift`
- Create: `Sources/PauseCore/RuleRuntime.swift`
- Create: `Sources/PauseCore/SessionDecision.swift`
- Create: `Sources/PauseCore/RulesEngine.swift`
- Create: `Tests/PauseCoreTests/RulesEngineTests.swift`
- Create: `Tests/PauseCoreTests/RuleRuntimeTests.swift`

### 2.1 Write failing decision tests

Cover these cases with fixed dates and a fixed Gregorian calendar:

- A fresh rule allows session 1 of its configured daily allowance.
- The last remaining session is allowed.
- A rule at its daily limit is refused.
- A rule with an unexpired open session is refused.
- An expired open session does not consume an additional allowance.
- A runtime from yesterday resets its count before the decision.
- Two rule IDs maintain independent counts.
- Invalid values are rejected at model initialization: `sessionsPerDay < 1`, `sessionLengthMinutes < 1`, and `pauseSeconds < 1`.

Use semantic assertions rather than snapshots. The central test should read:

```swift
func testRefusesWhenDailyAllowanceIsExhausted() throws {
    let rule = try AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)
    let runtime = RuleRuntime(logicalDay: today, sessionsStarted: 3)

    XCTAssertEqual(
        RulesEngine.decision(rule: rule, runtime: runtime, today: today, now: now),
        .refused(.dailyAllowanceExhausted(limit: 3))
    )
}
```

Run the `PauseCore` tests and confirm they fail because these types do not exist.

### 2.2 Implement the domain types

Use these public shapes:

```swift
public struct CalendarDay: Codable, Equatable, Comparable, Sendable {
    public let era: Int
    public let year: Int
    public let month: Int
    public let day: Int

    public init(date: Date, calendar: Calendar)
}

public struct AppRule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var sessionsPerDay: Int
    public var sessionLengthMinutes: Int

    public init(id: UUID = UUID(), sessionsPerDay: Int, sessionLengthMinutes: Int) throws
}

public struct GlobalSettings: Codable, Equatable, Sendable {
    public var pauseSeconds: Int
    public init(pauseSeconds: Int) throws
    public static let phaseOneDefault = try! GlobalSettings(pauseSeconds: 10)
}

public enum OpenSessionState: String, Codable, Equatable, Sendable {
    case provisional
    case active
}

public struct OpenSession: Codable, Equatable, Sendable {
    public let activityName: String
    public let expiresAt: Date
    public var state: OpenSessionState
}

public struct RuleRuntime: Codable, Equatable, Sendable {
    public var logicalDay: CalendarDay
    public var sessionsStarted: Int
    public var openSession: OpenSession?

    public mutating func rollOver(to day: CalendarDay)
    public mutating func reserve(activityName: String, expiresAt: Date) throws
    public mutating func activateReservedSession() throws
    public mutating func rollBackReservedSession() throws
    public mutating func clearExpiredSession(at now: Date)
}

public enum RefusalReason: Equatable, Sendable {
    case dailyAllowanceExhausted(limit: Int)
    case sessionAlreadyOpen(until: Date)
}

public enum SessionDecision: Equatable, Sendable {
    case allowed(sessionNumber: Int, lengthMinutes: Int)
    case refused(RefusalReason)
}
```

`rollOver(to:)` resets `sessionsStarted` when the day changes. It must not erase an unexpired open session: a session that crosses midnight remains open until its recorded expiry, while the new day begins with zero sessions started.

`reserve` increments `sessionsStarted` and writes a provisional session in one in-memory mutation. `rollBackReservedSession` clears that session and decrements the count once. It must reject rollback of an active session.

`RulesEngine.decision` works on a local copy of runtime, applies rollover and expiry cleanup, and returns a decision without mutating persisted state.

### 2.3 Pass and inspect the tests

Run:

```bash
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseCoreTests/RulesEngineTests -only-testing:PauseCoreTests/RuleRuntimeTests
```

Expected: all domain tests pass.

### 2.4 Commit

```bash
git add Sources/PauseCore Tests/PauseCoreTests
git commit -m "feat: define app rules and session runtime"
```

## Task 3: Build split, atomic App Group storage

**Files:**

- Create: `Sources/Shared/AtomicJSONFile.swift`
- Create: `Sources/Shared/RuntimeRepository.swift`
- Create: `Sources/Shared/LaunchRoute.swift`
- Create: `Sources/Shared/ConfigurationDocument.swift`
- Create: `Sources/Shared/ConfigurationStore.swift`
- Create: `Sources/Shared/AppGroupContainer.swift`
- Create: `Sources/Shared/ShieldIntentStore.swift`
- Create: `Tests/SharedTests/AtomicJSONFileTests.swift`
- Create: `Tests/SharedTests/RuntimeRepositoryTests.swift`

### 3.1 Write failing persistence tests

Use a fresh directory under `FileManager.default.temporaryDirectory` per test and remove only that exact directory in `tearDown`.

Test:

- Atomic JSON writes round-trip a configuration value.
- Replacing a value leaves a decodable complete file.
- A missing file returns `nil` rather than creating defaults silently.
- Invalid JSON throws `PersistenceError.corruptFile(URL)`.
- Runtime files are stored separately by rule ID.
- Deleting one runtime does not affect another.
- `update(ruleID:_:)` persists the entire mutation or leaves the previous value.
- The activity-name parser accepts only the fixed `session.<uuid>` form.

Run the focused tests and confirm they fail because the storage types do not exist.

### 3.2 Implement platform-neutral atomic files

Use `Data.write(to:options: .atomic)` behind this API:

```swift
public struct AtomicJSONFile<Value: Codable & Sendable>: Sendable {
    public let url: URL
    public func load() throws -> Value?
    public func save(_ value: Value) throws
    public func delete() throws
}

public enum PersistenceError: Error, Equatable {
    case corruptFile(URL)
    case missingAppGroupContainer
    case missingRuntime(UUID)
}

public final class RuntimeRepository: @unchecked Sendable {
    public init(directoryURL: URL)
    public func load(ruleID: UUID) throws -> RuleRuntime?
    public func save(_ runtime: RuleRuntime, ruleID: UUID) throws
    public func delete(ruleID: UUID) throws
    public func update(
        ruleID: UUID,
        _ mutation: (inout RuleRuntime) throws -> Void
    ) throws -> RuleRuntime
}
```

Serialize repository updates within each process with a private lock. Atomic replacement prevents partial files but is not a cross-process transaction. Product behavior prevents a second grant while a session is open: the app creates and grants, the monitor clears expiry, and shield extensions never write runtime. Every app and monitor write must load the latest file again while performing its mutation, and later callbacks remain idempotent so a repeated reconciliation repairs a stale result.

### 3.3 Implement configuration and target storage

The shared platform layer may import `FamilyControls` and `ManagedSettings`. Use Apple’s codable token directly:

```swift
import FamilyControls
import ManagedSettings
import PauseCore

public enum LaunchRoute: String, Codable, Equatable, Sendable {
    case instagram
}

public struct RuleTarget: Codable, Equatable, Identifiable {
    public var id: UUID { ruleID }
    public var ruleID: UUID
    public var applicationToken: ApplicationToken
    public var launchRoute: LaunchRoute?
}

public struct ConfigurationDocument: Codable, Equatable {
    public var settings: GlobalSettings
    public var rules: [AppRule]
    public var targets: [RuleTarget]
}
```

Require exactly one target per rule ID and exactly one rule per target ID when saving configuration. A mismatch is a visible configuration error, not a reason to discard either collection.

`ConfigurationStore` reads `configuration.json` from the App Group container and is writable only through app code. A missing file means a first launch. A corrupt file is an error and must not be replaced with an empty configuration.

Detect the Instagram route only from public metadata exposed by `ManagedSettings.Application`. Use the `FamilyActivitySelection.applications` set returned alongside the selected tokens; do not decode the token to discover identity:

```swift
public extension LaunchRoute {
    static func detected(for application: ManagedSettings.Application) -> LaunchRoute? {
        if application.bundleIdentifier == "com.burbn.instagram" ||
            application.localizedDisplayName == "Instagram" {
            return .instagram
        }
        return nil
    }
}
```

Do not persist Apple’s localized label or icon. Render them from the current token so the UI uses Apple’s current system identity.

### 3.4 Implement the shield-intent handoff

Use the measured App Group `UserDefaults` route only for this small record:

```swift
public struct ShieldIntent: Codable, Equatable {
    public let applicationToken: ApplicationToken
    public let createdAt: Date
}

public struct ShieldIntentStore {
    public func write(_ intent: ShieldIntent) throws
    public func consume() throws -> ShieldIntent?
}
```

`write` encodes a single JSON `Data` value under `shield-intent-v1`. `consume` decodes and removes it. Decoding failure removes the invalid value and throws so the app can remain blocked and show repair rather than repeatedly routing into a bad intent.

### 3.5 Verify

Run:

```bash
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseSharedTests/AtomicJSONFileTests -only-testing:PauseSharedTests/RuntimeRepositoryTests
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Expected: persistence tests pass and every target can import the shared storage code.

### 3.6 Commit

```bash
git add Sources/Shared Tests/SharedTests
git commit -m "feat: persist configuration and per-app runtime"
```

## Task 4: Add authorization, multi-app selection, and rule editing

**Files:**

- Create: `Sources/PauseCore/SelectionChange.swift`
- Create: `Tests/PauseCoreTests/SelectionChangeTests.swift`
- Create: `Sources/Pause/AppModel.swift`
- Create: `Sources/Pause/AuthorizationView.swift`
- Create: `Sources/Pause/RulesView.swift`
- Create: `Sources/Pause/RuleEditorView.swift`
- Create: `Sources/Pause/AppTokenLabel.swift`
- Modify: `Sources/Pause/PauseApp.swift`

### 4.1 Test selection reconciliation first

Keep Apple token handling in the app layer, but test the ID-level reconciliation policy in `PauseCore`:

```swift
public struct SelectionChange<ID: Hashable & Sendable>: Equatable, Sendable {
    public let added: Set<ID>
    public let retained: Set<ID>
    public let removed: Set<ID>
}

public func selectionChange<ID: Hashable & Sendable>(
    existing: Set<ID>,
    selected: Set<ID>
) -> SelectionChange<ID>
```

Write tests for add, retain, remove, and an unchanged selection. Confirm failure, then implement set subtraction and intersection.

### 4.2 Implement the app model

`AppModel` is `@MainActor` and owns:

```swift
@Published private(set) var authorizationStatus: AuthorizationStatus
@Published private(set) var configuration: ConfigurationDocument
@Published var pickerSelection: FamilyActivitySelection
@Published var presentedError: AppError?

func requestAuthorization() async
func applyPickerSelection() throws
func updateRule(id: UUID, sessionsPerDay: Int, sessionLengthMinutes: Int) throws
func updatePauseSeconds(_ seconds: Int) throws
func removeRule(id: UUID) throws
```

On first launch, use these editable defaults:

```text
sessions per day:       3
session length:         5 minutes
pause duration:         10 seconds
logical-day reset:      local midnight
```

`applyPickerSelection` must:

1. Compare selected application tokens with current targets.
2. Preserve existing rule IDs and settings for retained tokens.
3. Create one default rule for each added token.
4. Create that rule's runtime for the current local day with zero sessions started.
5. Detect the optional public launch route from Apple application metadata.
6. Remove deselected rules and their runtime files. Task 5 extends this same removal method to clear shields and monitoring once those mechanisms exist.
7. Persist the resulting configuration atomically.

Do not accept category or web-domain selections in Phase 1. The picker UI can display Apple’s full picker, but save only `applicationTokens`. Explain this next to the picker in plain language.

### 4.3 Build the first-launch and rule screens

The root flow has three states:

- Authorization required: explain why Screen Time permission is needed and show one request button.
- No selected apps: show the app picker call to action.
- Configured: show the rule list, global pause setting, and an edit-apps action.

Render each app with Apple’s `Label(token)` or the equivalent `FamilyControls` label view. The editor exposes integer controls with these Phase 1 ranges:

```text
sessions per day:       1...20
session length:         1...120 minutes
pause duration:         1...120 seconds
```

These ranges are product validation, not a history or budget feature.

### 4.4 Verify compilation and simulator behavior

Run:

```bash
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseCoreTests/SelectionChangeTests
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Also launch the simulator build and verify that the authorization-required shell and navigation render without crashing. The system picker itself remains a signed-device acceptance item.

### 4.5 Commit

```bash
git add Sources/Pause Sources/PauseCore Tests/PauseCoreTests
git commit -m "feat: select apps and edit pause rules"
```

## Task 5: Apply shields and route shield actions into Pause

**Files:**

- Create: `Sources/Shared/ShieldReconciler.swift`
- Create: `Sources/Shared/RuleLookup.swift`
- Modify: `Sources/Pause/AppModel.swift`
- Modify: `Sources/ShieldConfigExtension/ShieldConfigExtension.swift`
- Modify: `Sources/ShieldActionExtension/ShieldActionExtension.swift`

### 5.1 Implement one shield reconciliation path

All shield changes must flow through:

```swift
public struct ShieldReconciler {
    public func reconcile(
        configuration: ConfigurationDocument,
        runtimeRepository: RuntimeRepository,
        now: Date
    ) throws

    public func unshield(ruleID: UUID, configuration: ConfigurationDocument) throws
}
```

`reconcile` shields every configured application except a target with an unexpired provisional or active session. It first clears any expired open session it reads, saves that runtime, then applies the final token set in one `ManagedSettingsStore.shield.applications` assignment.

If a runtime file is corrupt or unreadable, include that target in the shield set and return a typed error after applying the safe set. This gives the main app enough information to display repair while keeping the affected app blocked.

Call `reconcile`:

- After configuration load.
- After picker changes.
- When the app becomes active.
- After rule edits that do not affect an existing open session.

`removeRule` must stop the rule’s monitoring activity, remove its runtime file, remove its token from the shield set, and then remove configuration. If cleanup fails, retain the rule and show the error; do not leave an unmanageable shield behind.

### 5.2 Implement the shield appearance

The shield configuration extension must:

- Read the token supplied by the shield callback.
- Match it to exactly one `RuleTarget` in configuration.
- Read the matching runtime.
- Apply local-midnight rollover and expiry cleanup in memory.
- Render Apple’s current `application.localizedDisplayName`.
- Render `Next session: N of M` when another session is available.
- Render `No sessions left today` when exhausted.
- Show one primary button: `Pause to open` when allowed, `Done for today` when refused.

If configuration, token lookup, or runtime decoding fails, render `Open Pause to repair this app` and keep the action blocked.

Leave `ShieldConfiguration.icon` unset. The public shield callback exposes the localized application name, but not a supported application-icon value that can be copied into the custom shield. The main app and picker still render Apple’s token-backed label and icon.

Do not write runtime from the shield configuration extension.

### 5.3 Implement shield action routing

For the primary shield action:

1. Recompute the decision from the current configuration and runtime.
2. If refused or unreadable, return `.none` without writing an intent.
3. If allowed, write `ShieldIntent(applicationToken: token, createdAt: Date())`.
4. Return `.openParentalControlsApp`.

For secondary and submenu actions, return `.none` and do not write state.

This is the measured route that opened Pause in 0.5–0.6 seconds in the previous device spike. Do not add notification or custom-URL fallback behavior.

### 5.4 Signed-device gate: picker and shield entry

Install the signed Debug build on the iPhone 16 running iOS 26.5 or later and verify:

1. Authorization can be granted.
2. The picker allows selecting Instagram plus at least one other installed app in one save.
3. Both appear in Pause with Apple’s system labels.
4. Both are shielded after configuration.
5. Each shield displays its independent next-session count.
6. Pressing Instagram’s shield button opens Pause and the consumed intent identifies Instagram.
7. Pressing the other app’s shield button opens Pause and identifies that app.

Pass condition: all seven behaviors work on-device. If Apple’s picker cannot persist one of the selected installed apps, record the exact app and stop to determine whether Apple classified it as ineligible; do not replace the picker with a custom catalog.

### 5.5 Verify and commit

Run the full unit suite and unsigned generic build again, then commit:

```bash
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git add Sources
git commit -m "feat: shield configured apps and capture open intent"
```

## Task 6: Implement the foreground-only pause

**Files:**

- Create: `Sources/PauseCore/PauseCountdown.swift`
- Create: `Tests/PauseCoreTests/PauseCountdownTests.swift`
- Create: `Sources/Pause/PauseView.swift`
- Create: `Sources/Pause/RepairView.swift`
- Modify: `Sources/Pause/AppModel.swift`
- Modify: `Sources/Pause/PauseApp.swift`

### 6.1 Write failing countdown tests

Test a value object rather than timers:

```swift
public struct PauseCountdown: Equatable, Sendable {
    public let ruleID: UUID
    public let startedAt: Date
    public let endsAt: Date

    public init(ruleID: UUID, seconds: Int, now: Date) throws
    public func remainingSeconds(at now: Date) -> Int
    public func isComplete(at now: Date) -> Bool
}
```

Cover:

- The full configured duration remains at creation.
- Remaining time rounds up so the UI never shows zero before completion.
- Completion occurs only at or after `endsAt`.
- A nonpositive duration is rejected.
- Creating a new countdown after abandonment starts from the full duration.

Confirm failure, implement the value object, and pass the focused tests.

### 6.2 Consume intent and choose the safe route

When Pause becomes active:

1. Consume at most one shield intent.
2. Reject an intent older than 30 seconds as stale.
3. Match its token to a configured target.
4. Load or initialize that rule’s runtime for the current local day.
5. Recompute the decision.
6. Route allowed entry to `PauseView` with a new `PauseCountdown`.
7. Route refusal to a clear refusal view.
8. Route missing configuration, token mismatch, or corrupt runtime to `RepairView` while retaining the shield.

There is no generic app-open route into the pause screen in Phase 1. Opening Pause normally shows configuration; only a recent shield intent starts the action loop.

### 6.3 Build the foreground countdown UI

`PauseView` displays:

- Apple’s app label.
- `Session N of M`.
- The session length that will be granted.
- A large integer countdown.
- A short statement that leaving Pause cancels this attempt.
- A disabled `Use session` button until the countdown completes.

Drive display updates with a scene-local timer, but calculate remaining time from `Date`, never from the number of timer ticks.

On any `scenePhase` transition away from `.active` before the grant starts:

- Discard the countdown.
- Consume no allowance.
- Write no runtime.
- Leave the target shielded.
- Return to configuration when Pause next becomes active.

Once the grant transaction starts, scene inactivity does not roll it back; Task 7 owns that transaction’s failure rules.

### 6.4 Verify

Run:

```bash
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseCoreTests/PauseCountdownTests
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

On-device, start the pause three times and interrupt it by Home, lock, and opening Control Center long enough to make the scene inactive. Confirm each attempt restarts at the full duration and the displayed allowance remains unchanged.

### 6.5 Commit

```bash
git add Sources/Pause Sources/PauseCore Tests/PauseCoreTests
git commit -m "feat: require an uninterrupted foreground pause"
```

## Task 7: Make session grants transactional and return when supported

**Files:**

- Create: `Sources/Shared/SessionGrantCoordinator.swift`
- Create: `Tests/SharedTests/SessionGrantCoordinatorTests.swift`
- Create: `Sources/Shared/DeviceActivitySessionScheduler.swift`
- Create: `Sources/Pause/AppLaunchRouter.swift`
- Create: `Sources/Pause/ManualReturnView.swift`
- Modify: `Sources/Pause/AppModel.swift`
- Modify: `Sources/Pause/PauseView.swift`

### 7.1 Define dependency boundaries and write failing transaction tests

Keep Screen Time frameworks outside the coordinator itself. The shared integration source imports `PauseCore` and uses these protocols:

```swift
public protocol SessionScheduling: Sendable {
    func register(ruleID: UUID, startsAt: Date, expiresAt: Date) throws -> String
    func stop(activityName: String) throws
}

public protocol RuntimePersisting: Sendable {
    func reserve(ruleID: UUID, activityName: String, expiresAt: Date) throws
    func activate(ruleID: UUID) throws
    func rollBack(ruleID: UUID) throws
}

public protocol ShieldControlling: Sendable {
    func unshield(ruleID: UUID) throws
    func reconcile() throws
}

public protocol TargetLaunching: Sendable {
    func hasAutomaticRoute(ruleID: UUID) -> Bool
    func open(ruleID: UUID) async -> Bool
}

public enum GrantResult: Equatable, Sendable {
    case openedAutomatically(expiresAt: Date)
    case readyForManualReturn(expiresAt: Date)
}
```

Write ordered fakes and cover:

- Scheduler registration occurs before runtime reservation and unshielding.
- A scheduling failure leaves runtime and shield untouched.
- A reservation failure stops the schedule and leaves the shield intact.
- An unshield failure rolls back runtime, stops the schedule, and reconciles the shield.
- A route success activates the provisional session.
- An explicit route failure rolls back runtime, stops monitoring, and re-shields.
- No automatic route activates the session and returns manual instructions.
- An activation persistence failure after successful launch leaves the provisional session in place; it is charged and recovered as active later.

Confirm the tests fail before implementing the coordinator.

### 7.2 Implement the coordinator in the approved order

`SessionGrantCoordinator.grant` receives the selected rule, `now`, and injected dependencies. It calculates `expiresAt = now + sessionLengthMinutes * 60` and performs:

1. Register expiry monitoring.
2. Reserve allowance and persist a provisional session.
3. Remove only the selected token from the shield.
4. If no automatic route exists, activate and return `.readyForManualReturn`.
5. If a route exists, attempt it.
6. On success, activate and return `.openedAutomatically`.
7. On explicit failure, roll back, stop monitoring, reconcile the shield, and throw a visible error.

Never unshield before both scheduling and provisional persistence succeed.

### 7.3 Implement Device Activity scheduling

`DeviceActivitySessionScheduler` maps a rule ID to `DeviceActivityName("session.<uuid>")` and creates one schedule:

- For `sessionLengthMinutes >= 15`: an interval ending at the exact recorded `expiresAt`; expiry is handled by `intervalDidEnd`.
- For `sessionLengthMinutes < 15`: a 15-minute interval with `warningTime = 15 - sessionLengthMinutes` minutes; expiry is handled by `intervalWillEndWarning`.

Include seconds in the absolute start and end `DateComponents` so the requested expiry represents the recorded wall-clock duration. Before unshielding, validate that `DeviceActivitySchedule.nextInterval` resolves an end or warning time within five seconds of the stored `expiresAt`. If it does not, throw `SessionSchedulingError.unrepresentableExpiry`; keep the app blocked and do not charge the session.

This validation is the guard against silently turning a fixed session into a minute-rounded session.

### 7.4 Implement automatic and manual return

`AppLaunchRouter` supports exactly one route:

```swift
case .instagram:
    return await UIApplication.shared.open(URL(string: "instagram://")!)
```

Declare the Instagram query scheme in the app’s generated `Info.plist` only if `canOpenURL` is used. Prefer calling `open` and using its completion result so the explicit success/failure drives the transaction.

For targets without a route, show `ManualReturnView` only after the session is active and the shield is removed. It displays Apple’s app label and: `Your session is ready. Return to the app from the Home Screen or App Switcher.`

Do not add a per-app URL text field or guess schemes for other apps.

### 7.5 Verify transaction logic

Run:

```bash
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseSharedTests/SessionGrantCoordinatorTests
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Expected: every ordering and rollback test passes.

### 7.6 Signed-device gate: grant and return

On the iPhone 16:

1. Start an Instagram pause and complete it.
2. Confirm Instagram opens automatically.
3. Return to Pause and confirm exactly one Instagram session was charged.
4. Start a pause for an app without a registered route.
5. Confirm the manual-return screen appears only after the shield is removed.
6. Return to that app manually and confirm it opens.
7. Configure a deliberately unavailable Instagram route in a Debug-only injected test double, complete the pause, and confirm the session rolls back and Instagram is re-shielded.

Pass condition: both return modes work, and explicit launch failure charges nothing.

### 7.7 Commit

```bash
git add Sources/Pause Sources/Shared Tests/SharedTests
git commit -m "feat: grant timed sessions and return to supported apps"
```

## Task 8: Restore shields at expiry and recover interrupted grants

**Files:**

- Create: `Sources/PauseCore/SessionReconciliation.swift`
- Create: `Tests/PauseCoreTests/SessionReconciliationTests.swift`
- Modify: `Sources/MonitorExtension/MonitorExtension.swift`
- Modify: `Sources/Shared/ShieldReconciler.swift`
- Modify: `Sources/Pause/AppModel.swift`

### 8.1 Write failing reconciliation tests

Define the pure decision:

```swift
public enum SessionReconciliation: Equatable, Sendable {
    case keepOpen
    case activateProvisional
    case expire
    case noSession
}

public func reconciliation(for runtime: RuleRuntime, now: Date) -> SessionReconciliation
```

Test:

- An unexpired active session stays open.
- An unexpired provisional session becomes active during recovery.
- An expired active session expires.
- An expired provisional session expires but remains charged.
- No open session requires no runtime change.

The provisional recovery policy is intentional: once unshielding may have occurred, a crash cannot safely prove the target never opened.

### 8.2 Implement monitor callbacks as idempotent reconciliation

For both `intervalDidEnd` and `intervalWillEndWarning`:

1. Parse the rule ID from the activity name.
2. Load configuration and find the rule.
3. Load its runtime.
4. Compare `Date()` with the stored `expiresAt`; never trust the callback name alone.
5. If not yet expired, leave runtime and shield unchanged.
6. If expired, clear `openSession`, persist runtime, and apply shields from the full configuration/runtime set.
7. Stop the named monitoring activity after the warning callback when possible.

Also call the same reconciliation when the main app becomes active. That makes delayed daemon callbacks recover safely without changing the source of truth.

All callback paths must be idempotent: a duplicate callback after runtime is cleared leaves the target shielded and does not alter the session count.

### 8.3 Add visible repair and restart recovery

On app activation:

- Convert an unexpired provisional session to active and persist it.
- Clear expired sessions and restore their shields.
- Keep any target with unreadable runtime shielded.
- Show the affected app in `RepairView` with one action: `Reset this app’s runtime`.

The repair action may delete only that rule’s runtime file and recreate it for the current day with zero sessions. It must not alter other rules or configuration. Explain that this can reset today’s count for the affected app; require explicit confirmation.

Do not build a general migration or diagnostics subsystem.

### 8.4 Verify automated behavior

Run:

```bash
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseCoreTests/SessionReconciliationTests
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Expected: full suite passes and all targets build.

### 8.5 Signed-device expiry gate

Use the product UI; do not run a separate spike target.

**Three-minute case:**

1. Configure one app for a 3-minute session.
2. Record the stored `expiresAt` shown in a Debug-only diagnostics row.
3. Complete the pause and keep the granted app foregrounded.
4. Confirm it becomes shielded within five seconds after `expiresAt`.

**Sixteen-minute case:**

1. Configure the same app for a 16-minute session.
2. Repeat the test through `intervalDidEnd`.
3. Confirm it becomes shielded within five seconds after `expiresAt`.

**Delayed callback case:**

1. End a granted app before expiry and prevent normal interaction until after expiry.
2. Open Pause after expiry.
3. Confirm app activation reconciliation restores the shield immediately.

Acceptance:

- Up to 5 seconds late: pass.
- More than 5 but no more than 30 seconds late: record the actual delay and investigate before release.
- More than 30 seconds late, or no restoration: Phase 1 is blocked. Do not add notifications or tracking as a workaround without revisiting the approved design.

Remove the Debug-only diagnostics row after recording the device results; the stored expiry is not a product-facing history feature.

### 8.6 Commit

```bash
git add Sources Tests/PauseCoreTests
git commit -m "feat: restore shields when sessions expire"
```

## Task 9: Close the Phase 1 acceptance matrix

**Files:**

- Create: `docs/testing/phase-1-device-acceptance.md`
- Modify: `docs/status.md`
- Modify: `README.md`

### 9.1 Write the acceptance record before the final run

Create a compact record with these columns:

```text
Requirement | Test setup | Expected | Observed | Pass/Fail
```

Include every behavior below. The observed column must contain device/OS/build and concrete results, not `works`.

### 9.2 Run the complete product matrix on iPhone 16

Verify:

- Fresh install and Screen Time authorization.
- Multiple application selection through Apple’s picker.
- Independent rule editing for Instagram and another installed app.
- Shields applied after setup and after subsequent app activation.
- Correct next-session count on each shield.
- Foreground pause completes at the configured duration.
- Home, lock, and scene interruption abandon the pause without charge.
- Instagram automatic return.
- Manual return for an app without a supported route.
- Session wall-clock time continues while the target is backgrounded.
- Three-minute and sixteen-minute expiry restoration.
- Daily counts reset at local midnight.
- A session crossing midnight remains open to its expiry while the new day count resets.
- Exhausted allowance refuses another session.
- Removing a rule stops its activity, removes runtime, and unshields the app.
- Editing a rule does not alter the currently active session.
- Corrupting one Debug runtime fixture keeps only that app blocked and offers explicit repair.
- Denied authorization creates no rules.
- Scheduling failure and explicit route failure keep or restore the shield and charge nothing.

### 9.3 Run final automated verification

Regenerate the project from its committed source of truth, then run the complete automated checks:

```bash
xcodegen generate
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git status --short
```

Validate that `git status --short` lists only the intended documentation edits before committing.

### 9.4 Update the project entry points

`README.md` should contain only:

- One-sentence product purpose.
- Current supported device/OS target.
- Setup: copy `Local.xcconfig.example` to `Local.xcconfig`, set the team, run `xcodegen generate`, and open `Pause.xcodeproj`.
- Test command.
- Links to the PRD, approved design, this plan, and device acceptance record.

Update `docs/status.md` to state:

- Phase 1 implementation state.
- Last automated test/build result.
- Last device matrix result.
- The next roadmap item is Phase 2 time-based rules, not history.
- Any failed acceptance item as a blocker with its concrete observation.

### 9.5 Commit

```bash
git add README.md docs/status.md docs/testing/phase-1-device-acceptance.md
git commit -m "docs: record Phase 1 acceptance"
```

## Phase 1 completion gate

Phase 1 is complete only when:

- Both unit-test targets pass from a newly generated project.
- The app and all three extensions compile for generic iOS.
- The signed build passes every device-matrix item on the iPhone 16.
- Both short and standard sessions restore their shields no more than five seconds after stored expiry.
- Instagram automatic return works through the public route.
- At least one other selected app completes the manual-return path.
- All failure paths fail blocked and do not consume allowance unless unshielding may already have occurred.
- No deferred Phase 2 or history code has been added.

After this gate, checkpoint the project before beginning Phase 2. Update the compatibility baseline for iOS 27 only after iOS 27 and its matching Xcode toolchain are available; do not pre-build version-specific branches.
