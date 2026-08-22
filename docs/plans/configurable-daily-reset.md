# Configurable Daily Reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the daily reset a configurable time on a fifteen-minute grid, applying to all seven days, defaulting to midnight.

**Architecture:** A new `GlobalSettings.resetMinuteOfDay` feeds `LogicalDay`, which answers which allowance day an instant belongs to by finding the most recent reset at or before it. `ConfigurationFile.inForce(at:)` resolves the day from its own effective settings so no other component handles a reset minute. `DailyResetScheduler` registers the repeating wake-up at the configured time.

**Tech Stack:** Swift 6, Xcode 26.6, XcodeGen, XCTest, SwiftUI, Apple DeviceActivity / ManagedSettings / FamilyControls.

**Spec:** [`docs/design/configurable-daily-reset.md`](../design/configurable-daily-reset.md)

## Global Constraints

**Deliberately not built.** A reset-time change applies immediately, so nothing here teaches `ConfigurationComparison` to judge one. Leave `isLoosening(from:to:)` for `GlobalSettings` comparing `pauseSeconds` alone. A reset change reaches the pending document only when it travels with a deferred pause-duration edit, which is the known limit the spec accepts, not a case to special-case.

- Deployment target iOS 26.5 or later; iPhone only. Xcode 26.6, Swift 6.
- Public APIs only. No private framework calls.
- The reset is stored as a minute of the day, `0...1439`, and must be a multiple of `15`. Ninety-six valid positions, `00:00` through `23:45`.
- The default is `0` (midnight), which reproduces current behaviour exactly.
- Settings written by the current build carry no reset minute; decoding supplies `0`.
- `CalendarDay` and every per-app runtime record keep their existing shape. No migration.
- Regenerate the project with `xcodegen generate` after adding any file.
- Full suite: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

---

### Task 1: Store the reset minute

**Files:**
- Modify: `Sources/PauseCore/GlobalSettings.swift`
- Test: `Tests/PauseCoreTests/GlobalSettingsTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `GlobalSettings.resetMinuteOfDay: Int`; `GlobalSettings.init(pauseSeconds: Int, resetMinuteOfDay: Int = 0) throws`; `GlobalSettingsError.invalidResetMinuteOfDay`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/PauseCoreTests/GlobalSettingsTests.swift`:

```swift
import PauseCore
import XCTest

final class GlobalSettingsTests: XCTestCase {
    func testResetMinuteDefaultsToMidnight() throws {
        let settings = try GlobalSettings(pauseSeconds: 10)

        XCTAssertEqual(settings.resetMinuteOfDay, 0)
    }

    func testResetMinuteAcceptsEveryQuarterHourPosition() throws {
        for minute in stride(from: 0, through: 1425, by: 15) {
            let settings = try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: minute)
            XCTAssertEqual(settings.resetMinuteOfDay, minute)
        }
    }

    func testResetMinuteRejectsAPositionOffTheQuarterHourGrid() {
        XCTAssertThrowsError(try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: 7)) { error in
            XCTAssertEqual(error as? GlobalSettingsError, .invalidResetMinuteOfDay)
        }
    }

    func testResetMinuteRejectsAPositionOutsideTheDay() {
        XCTAssertThrowsError(try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: 1440)) { error in
            XCTAssertEqual(error as? GlobalSettingsError, .invalidResetMinuteOfDay)
        }
        XCTAssertThrowsError(try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: -15)) { error in
            XCTAssertEqual(error as? GlobalSettingsError, .invalidResetMinuteOfDay)
        }
    }

    /// Settings written by the current build carry no reset minute. Decoding one
    /// must read back as midnight rather than failing, which is the whole of the
    /// compatibility story for this change.
    func testDecodingSettingsWrittenBeforeTheResetExistedReadsAsMidnight() throws {
        let legacy = Data("{\"pauseSeconds\":10}".utf8)

        let settings = try JSONDecoder().decode(GlobalSettings.self, from: legacy)

        XCTAssertEqual(settings.pauseSeconds, 10)
        XCTAssertEqual(settings.resetMinuteOfDay, 0)
    }

    func testEncodedSettingsRoundTrip() throws {
        let settings = try GlobalSettings(pauseSeconds: 30, resetMinuteOfDay: 375)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseCoreTests/GlobalSettingsTests`
Expected: FAIL — `resetMinuteOfDay` and `invalidResetMinuteOfDay` do not exist.

- [ ] **Step 3: Write the implementation**

Replace the contents of `Sources/PauseCore/GlobalSettings.swift`:

```swift
import Foundation

public enum GlobalSettingsError: Error, Equatable, Sendable {
    case invalidPauseSeconds
    case invalidResetMinuteOfDay
}

public struct GlobalSettings: Codable, Equatable, Sendable {
    /// The reset is chosen from ninety-six positions rather than 1,440: a
    /// quarter-hour is fine enough for a boundary nobody watches land, and it
    /// keeps the picker to a readable length.
    public static let resetMinuteStep = 15

    public var pauseSeconds: Int
    /// Minutes after local midnight at which the day's session counts renew.
    public var resetMinuteOfDay: Int

    public init(pauseSeconds: Int, resetMinuteOfDay: Int = 0) throws {
        guard pauseSeconds >= 1 else {
            throw GlobalSettingsError.invalidPauseSeconds
        }
        guard (0..<(24 * 60)).contains(resetMinuteOfDay),
              resetMinuteOfDay % Self.resetMinuteStep == 0 else {
            throw GlobalSettingsError.invalidResetMinuteOfDay
        }
        self.pauseSeconds = pauseSeconds
        self.resetMinuteOfDay = resetMinuteOfDay
    }

    /// Settings saved before the reset was configurable carry no reset minute.
    /// Reading one as midnight is what lets an existing install upgrade without
    /// a migration or a behaviour change.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            pauseSeconds: container.decode(Int.self, forKey: .pauseSeconds),
            resetMinuteOfDay: container.decodeIfPresent(Int.self, forKey: .resetMinuteOfDay) ?? 0
        )
    }

    public static let phaseOneDefault = try! GlobalSettings(pauseSeconds: 10)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseCoreTests/GlobalSettingsTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Run the full suite**

Run the full suite command from Global Constraints.
Expected: PASS. `GlobalSettings` gained a defaulted parameter, so existing call sites still compile.

- [ ] **Step 6: Commit**

```bash
git add Sources/PauseCore/GlobalSettings.swift Tests/PauseCoreTests/GlobalSettingsTests.swift
git commit -m "feat: store the daily reset as a quarter-hour position"
```

---

### Task 2: Resolve the allowance day from the reset

**Files:**
- Modify: `Sources/PauseCore/LogicalDay.swift`
- Test: `Tests/PauseCoreTests/LogicalDayTests.swift`

**Interfaces:**
- Consumes: `GlobalSettings.resetMinuteOfDay` (Task 1) — callers pass the `Int`, not the settings.
- Produces: `LogicalDay.containing(_ date: Date, resetMinuteOfDay: Int, calendar: Calendar) -> CalendarDay` and `LogicalDay.next(after date: Date, resetMinuteOfDay: Int, calendar: Calendar) -> CalendarDay`. **Both parameters are required — no defaults.** The compiler then names every call site that must be considered, rather than letting one silently keep midnight.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/PauseCoreTests/LogicalDayTests.swift`:

```swift
    /// A fixed calendar so these read the same wherever they run.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func instant(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")!
        return formatter.date(from: iso)!
    }

    func testBeforeTheResetTheInstantBelongsToYesterday() {
        let day = LogicalDay.containing(
            instant("2026-03-10T05:59:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2026-03-09T12:00:00Z"), calendar: utc))
    }

    func testAtTheResetTheInstantBelongsToToday() {
        let day = LogicalDay.containing(
            instant("2026-03-10T06:00:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2026-03-10T12:00:00Z"), calendar: utc))
    }

    func testAfterTheResetTheInstantBelongsToToday() {
        let day = LogicalDay.containing(
            instant("2026-03-10T23:59:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2026-03-10T12:00:00Z"), calendar: utc))
    }

    func testMidnightResetMatchesTheCivilDate() {
        let day = LogicalDay.containing(
            instant("2026-03-10T00:00:00Z"),
            resetMinuteOfDay: 0,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2026-03-10T12:00:00Z"), calendar: utc))
    }

    func testCrossingAMonthBoundaryBackwards() {
        let day = LogicalDay.containing(
            instant("2026-04-01T05:00:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2026-03-31T12:00:00Z"), calendar: utc))
    }

    func testCrossingAYearBoundaryBackwards() {
        let day = LogicalDay.containing(
            instant("2026-01-01T05:00:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2025-12-31T12:00:00Z"), calendar: utc))
    }

    func testCrossingALeapDayBackwards() {
        let day = LogicalDay.containing(
            instant("2028-03-01T05:00:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2028-02-29T12:00:00Z"), calendar: utc))
    }

    func testNextIsTheDayAfterTheOneContainingTheInstant() {
        let day = LogicalDay.next(
            after: instant("2026-03-10T05:00:00Z"),
            resetMinuteOfDay: 6 * 60,
            calendar: utc
        )

        XCTAssertEqual(day, CalendarDay(date: instant("2026-03-10T12:00:00Z"), calendar: utc))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseCoreTests/LogicalDayTests`
Expected: FAIL — no overload takes `resetMinuteOfDay`.

- [ ] **Step 3: Write the implementation**

Replace the body of `Sources/PauseCore/LogicalDay.swift`:

```swift
import Foundation

/// The single place that decides which allowance day an instant belongs to.
///
/// An allowance day begins at the configured reset and runs twenty-four hours,
/// and is named for the civil date it begins on. Session counting and deferred
/// rule changes both ask this type, which is what keeps a rule change and the
/// allowance reset it arrives with on the same instant.
public enum LogicalDay {
    public static func containing(
        _ date: Date,
        resetMinuteOfDay: Int,
        calendar: Calendar
    ) -> CalendarDay {
        // Shifting the instant back by the reset offset turns "which period is
        // this in" into "what civil date is this", which the calendar answers
        // across month, year and leap boundaries without special cases.
        let shifted = date.addingTimeInterval(-Double(resetMinuteOfDay) * 60)
        return CalendarDay(date: shifted, calendar: calendar)
    }

    public static func next(
        after date: Date,
        resetMinuteOfDay: Int,
        calendar: Calendar
    ) -> CalendarDay {
        let shifted = date.addingTimeInterval(-Double(resetMinuteOfDay) * 60)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: shifted) ?? shifted
        return CalendarDay(date: tomorrow, calendar: calendar)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseCoreTests/LogicalDayTests`
Expected: PASS. The build of other targets will still fail — Task 3 fixes those call sites.

- [ ] **Step 5: Commit**

```bash
git add Sources/PauseCore/LogicalDay.swift Tests/PauseCoreTests/LogicalDayTests.swift
git commit -m "feat: resolve the allowance day from the configured reset"
```

---

### Task 3: Resolve the day inside ConfigurationFile

**Files:**
- Modify: `Sources/Shared/ConfigurationFile.swift`
- Modify: `Sources/Shared/ConfigurationSaveRouter.swift:19,69`
- Modify: `Sources/Shared/SessionReconciliationService.swift:63,122,145`
- Modify: `Sources/Shared/ShieldStateReader.swift:43`
- Modify: `Sources/ShieldActionExtension/ShieldActionExtension.swift:40`
- Modify: `Sources/Pause/AppModel.swift:183,442,564,868,879,889`
- Modify: `Sources/Pause/ScheduledChangeNotice.swift:37`
- Test: `Tests/SharedTests/ConfigurationFileTests.swift`

**Interfaces:**
- Consumes: `LogicalDay.containing(_:resetMinuteOfDay:calendar:)` (Task 2).
- Produces: `ConfigurationFile.inForce(at instant: Date, calendar: Calendar = .current) -> ConfigurationDocument` and `ConfigurationFile.logicalDay(at instant: Date, calendar: Calendar = .current) -> CalendarDay`. The existing `inForce(on:)` stays for callers that already hold a day.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/SharedTests/ConfigurationFileTests.swift`:

```swift
    /// The reset time lives in the configuration and choosing the configuration
    /// needs the day, so the effective document's reset is what defines the day.
    /// A pending document's own reset must not reach back and move the boundary
    /// that decides whether it is in force yet.
    func testTheEffectiveResetDefinesTheDayThatSelectsThePending() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")!
        let instant = formatter.date(from: "2026-03-10T05:00:00Z")!

        let effective = try ConfigurationDocument(
            settings: try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: 6 * 60),
            rules: [],
            targets: []
        )
        let scheduled = try ConfigurationDocument(
            settings: try GlobalSettings(pauseSeconds: 20, resetMinuteOfDay: 0),
            rules: [],
            targets: []
        )
        let file = ConfigurationFile(
            effective: effective,
            pending: PendingConfiguration(
                document: scheduled,
                startDay: CalendarDay(
                    date: formatter.date(from: "2026-03-10T12:00:00Z")!,
                    calendar: utc
                )
            )
        )

        // 05:00 with a 06:00 reset is still 2026-03-09, so a change starting on
        // 2026-03-10 has not arrived.
        XCTAssertEqual(file.inForce(at: instant, calendar: utc), effective)
        XCTAssertEqual(
            file.logicalDay(at: instant, calendar: utc),
            CalendarDay(date: formatter.date(from: "2026-03-09T12:00:00Z")!, calendar: utc)
        )
    }

    func testThePendingArrivesOnceTheEffectiveResetHasPassed() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")!

        let effective = try ConfigurationDocument(
            settings: try GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: 6 * 60),
            rules: [],
            targets: []
        )
        let scheduled = try ConfigurationDocument(
            settings: try GlobalSettings(pauseSeconds: 20, resetMinuteOfDay: 6 * 60),
            rules: [],
            targets: []
        )
        let file = ConfigurationFile(
            effective: effective,
            pending: PendingConfiguration(
                document: scheduled,
                startDay: CalendarDay(
                    date: formatter.date(from: "2026-03-10T12:00:00Z")!,
                    calendar: utc
                )
            )
        )

        let afterReset = formatter.date(from: "2026-03-10T06:00:00Z")!
        XCTAssertEqual(file.inForce(at: afterReset, calendar: utc), scheduled)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseSharedTests/ConfigurationFileTests`
Expected: FAIL — `inForce(at:calendar:)` and `logicalDay(at:calendar:)` do not exist.

- [ ] **Step 3: Add the instant-taking form**

Append to `ConfigurationFile` in `Sources/Shared/ConfigurationFile.swift`:

```swift
    /// The allowance day this instant falls in, resolved from the reset time in
    /// the effective document.
    ///
    /// The effective document is the right source and not merely a convenient
    /// one: a reset change applies immediately, so the effective document always
    /// carries the current reset; and in the one case where a reset change is
    /// deferred, the old reset is exactly what should still govern until the
    /// scheduled change lands.
    public func logicalDay(at instant: Date, calendar: Calendar = .current) -> CalendarDay {
        LogicalDay.containing(
            instant,
            resetMinuteOfDay: effective.settings.resetMinuteOfDay,
            calendar: calendar
        )
    }

    public func inForce(at instant: Date, calendar: Calendar = .current) -> ConfigurationDocument {
        inForce(on: logicalDay(at: instant, calendar: calendar))
    }
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseSharedTests/ConfigurationFileTests`
Expected: PASS.

- [ ] **Step 5: Migrate every call site the compiler names**

Build and let the compiler enumerate the breakages from Task 2's required parameters:

Run: `xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`

Apply this mapping. Every one of these already has the `ConfigurationFile` in hand at the point of the call:

- `file.inForce(on: LogicalDay.containing(now))` → `file.inForce(at: now)` (this covers `AppModel.swift:183,564,868,889`, `SessionReconciliationService.swift:63`, and `ShieldActionExtension.swift:40`)
- `file.inForce(on: LogicalDay.containing(now, calendar: calendar))` → `file.inForce(at: now, calendar: calendar)`
- `SessionReconciliationService.swift:145` — `logicalDay: LogicalDay.containing(now, calendar: calendar)` → `logicalDay: file.logicalDay(at: now, calendar: calendar)`
- `AppModel.swift:442` — `let today = LogicalDay.containing(now)` → `let today = logicalDay(at: now)`, using a new private helper added beside it, so no call site inside `AppModel` spells out the fallback:

```swift
    /// The allowance day, resolved from the file when there is one. The fallback
    /// covers only the window before a file has been loaded, where the in-force
    /// document is the sole source of settings.
    private func logicalDay(at now: Date) -> CalendarDay {
        configurationFile?.logicalDay(at: now)
            ?? LogicalDay.containing(
                now,
                resetMinuteOfDay: configuration.settings.resetMinuteOfDay,
                calendar: .current
            )
    }
```
- `AppModel.swift:879` — inside `scheduledStartDay(in:now:)`, which already takes the file: `startDay > LogicalDay.containing(now)` → `startDay > file.logicalDay(at: now)`
- `ConfigurationSaveRouter.swift:19` — `existing.inForce(on: LogicalDay.containing(now, calendar: calendar))` → `existing.inForce(at: now, calendar: calendar)`
- `ConfigurationSaveRouter.swift:69` — `startDay: LogicalDay.next(after: now, calendar: calendar)` → `startDay: LogicalDay.next(after: now, resetMinuteOfDay: existing.effective.settings.resetMinuteOfDay, calendar: calendar)`
- `ScheduledChangeNotice.swift:37` — `if day == LogicalDay.next(after: now)`. This is wording only ("tomorrow" vs a date), and the notice does not hold a file. Thread the reset minute in: change the enclosing function to take `resetMinuteOfDay: Int` and pass `model.configuration.settings.resetMinuteOfDay` from its caller in `RulesView`.

For tests that call `LogicalDay.next(after: now)` (`AppModelFlowTests.swift` and others the compiler names), pass `resetMinuteOfDay: 0, calendar: .current` — those fixtures all use the midnight default.

- [ ] **Step 6: Run the full suite and the build**

Run the full suite command, then:
`xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
Expected: all tests PASS, BUILD SUCCEEDED, no Swift warnings.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: resolve the allowance day inside ConfigurationFile"
```

---

### Task 4: Settle the wrapping schedule, then register at the reset

**Files:**
- Modify: `Sources/Shared/DailyResetScheduler.swift`
- Modify: `Sources/Pause/AppModel.swift:925`
- Modify: `docs/research/screen-time-platform-evidence.md`
- Test: `Tests/SharedTests/DailyResetSchedulerTests.swift` (create)

**Interfaces:**
- Consumes: `GlobalSettings.resetMinuteOfDay` (Task 1).
- Produces: `DailyResetScheduler.register(resetMinuteOfDay: Int) throws`.

- [ ] **Step 1: Answer the wrap question before building on it**

A reset anywhere but midnight makes the repeating interval cross midnight, and whether iOS honours that is unmeasured. `DeviceActivitySchedule.nextInterval` resolves on the schedule value with no authorization, no registration and no device, so this is a simulator question.

Add this temporary test to `Tests/SharedTests/DailyResetSchedulerTests.swift`, run it, and read the output:

```swift
import DeviceActivity
import Foundation
import XCTest

final class DailyResetSchedulerTests: XCTestCase {
    func testProbeWhatAWrappingScheduleResolvesTo() {
        let wrapping = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 6, minute: 0),
            intervalEnd: DateComponents(hour: 5, minute: 59),
            repeats: true
        )
        print("WRAPPING nextInterval: \(String(describing: wrapping.nextInterval))")

        let sameDay = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        print("SAME-DAY nextInterval: \(String(describing: sameDay.nextInterval))")
    }
}
```

Run: `xcodegen generate && xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseSharedTests/DailyResetSchedulerTests`

Read the printed intervals. **If the wrapping schedule resolves to a roughly 24-hour `DateInterval` beginning at 06:00, use it in Step 3.** If it resolves to `nil`, to an inverted interval, or to a span far from 24 hours, use the fallback in Step 3 instead. Record the reading either way in Step 5.

- [ ] **Step 2: Replace the probe with a real test**

Delete the probe test and write:

```swift
import DeviceActivity
import Foundation
import XCTest

final class DailyResetSchedulerTests: XCTestCase {
    func testTheScheduleBeginsAtTheConfiguredReset() throws {
        var registered: DeviceActivitySchedule?
        let scheduler = DailyResetScheduler(startMonitoring: { _, schedule in
            registered = schedule
        })

        try scheduler.register(resetMinuteOfDay: 6 * 60 + 30)

        XCTAssertEqual(registered?.intervalStart.hour, 6)
        XCTAssertEqual(registered?.intervalStart.minute, 30)
        XCTAssertTrue(registered?.repeats == true)
    }

    func testMidnightRegistersTheScheduleItAlwaysDid() throws {
        var registered: DeviceActivitySchedule?
        let scheduler = DailyResetScheduler(startMonitoring: { _, schedule in
            registered = schedule
        })

        try scheduler.register(resetMinuteOfDay: 0)

        XCTAssertEqual(registered?.intervalStart.hour, 0)
        XCTAssertEqual(registered?.intervalStart.minute, 0)
    }

    func testTheRegisteredActivityIsTheDailyResetByName() throws {
        var name: DeviceActivityName?
        let scheduler = DailyResetScheduler(startMonitoring: { activityName, _ in
            name = activityName
        })

        try scheduler.register(resetMinuteOfDay: 0)

        XCTAssertEqual(name?.rawValue, DailyResetActivityName.value)
    }
}
```

- [ ] **Step 3: Write the implementation**

Replace `register()` in `Sources/Shared/DailyResetScheduler.swift`:

```swift
    public func register(resetMinuteOfDay: Int) throws {
        let start = DateComponents(
            hour: resetMinuteOfDay / 60,
            minute: resetMinuteOfDay % 60
        )
        let endMinute = (resetMinuteOfDay + 24 * 60 - 1) % (24 * 60)
        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: DateComponents(hour: endMinute / 60, minute: endMinute % 60),
            repeats: true
        )
        try startMonitoring(DeviceActivityName(DailyResetActivityName.value), schedule)
    }
```

**Fallback if Step 1 showed the wrap is not honoured:** keep `intervalEnd` at `DateComponents(hour: 23, minute: 59)` regardless of the reset, so the schedule never crosses midnight. The callback then arrives at the reset on days when the reset has not yet passed, and reconciliation on app open covers the rest — the same repair path a switched-off phone already relies on. Note the choice in the code with a comment naming the reading from Step 1.

- [ ] **Step 4: Update the caller and run**

`Sources/Pause/AppModel.swift:925` becomes:

```swift
            try DailyResetScheduler(center: activityCenter).register(
                resetMinuteOfDay: configuration.settings.resetMinuteOfDay
            )
```

Run the full suite. Expected: PASS.

- [ ] **Step 5: Record the reading**

Add a short subsection to `docs/research/screen-time-platform-evidence.md` under the schedule findings, stating what a wrapping `intervalStart`/`intervalEnd` pair resolved to, measured in the simulator on the date you ran it, and which branch of Step 3 was taken. This closes the note's existing open question about multi-day schedules for the wrapping case.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: wake at the configured reset rather than midnight"
```

---

### Task 5: Choose the reset time

**Files:**
- Modify: `Sources/Pause/AppModel.swift:540-556`
- Modify: `Sources/Pause/RulesView.swift:85-94`
- Test: `Tests/PauseAppTests/AppModelFlowTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces: `AppModel.setResetMinuteOfDay(_ minute: Int, now: Date) throws`; `AppModelError.invalidResetMinuteOfDay`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/PauseAppTests/AppModelFlowTests.swift`:

```swift
    func testSettingTheResetTimePersistsItAndKeepsThePauseDuration() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let model = makeModel(directory: directory, probe: FlowProbe(status: .approved), hasProtectedState: false)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        model.sceneDidBecomeActive(now: now)
        let pauseBefore = model.configuration.settings.pauseSeconds

        try model.setResetMinuteOfDay(6 * 60, now: now)

        XCTAssertEqual(model.configuration.settings.resetMinuteOfDay, 6 * 60)
        XCTAssertEqual(model.configuration.settings.pauseSeconds, pauseBefore)
    }

    /// The pause-duration setter rebuilds the whole settings value, so a reset
    /// time already chosen must survive an unrelated edit to the countdown.
    func testEditingThePauseDurationKeepsTheResetTime() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let model = makeModel(directory: directory, probe: FlowProbe(status: .approved), hasProtectedState: false)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        model.sceneDidBecomeActive(now: now)
        try model.setResetMinuteOfDay(9 * 60 + 45, now: now)

        try model.updatePauseSeconds(30, now: now)

        XCTAssertEqual(model.configuration.settings.resetMinuteOfDay, 9 * 60 + 45)
        XCTAssertEqual(model.configuration.settings.pauseSeconds, 30)
    }

    func testAResetTimeOffTheQuarterHourGridIsRefused() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEmptyConfiguration(to: directory)
        let model = makeModel(directory: directory, probe: FlowProbe(status: .approved), hasProtectedState: false)
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        model.sceneDidBecomeActive(now: now)

        XCTAssertThrowsError(try model.setResetMinuteOfDay(7, now: now)) { error in
            XCTAssertEqual(error as? AppModelError, .invalidResetMinuteOfDay)
        }
    }
```

The existing pause-duration setter is `updatePauseSeconds(_:now:)`; the second test above calls it under that name.

- [ ] **Step 2: Run to verify they fail**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseAppTests/AppModelFlowTests`
Expected: FAIL — `setResetMinuteOfDay` does not exist.

- [ ] **Step 3: Fix the settings-clobbering bug and add the setter**

In `Sources/Pause/AppModel.swift`, the existing pause-duration setter builds a fresh `GlobalSettings` and so would discard the reset time. Change that line to carry it:

```swift
        nextConfiguration.settings = try GlobalSettings(
            pauseSeconds: seconds,
            resetMinuteOfDay: configuration.settings.resetMinuteOfDay
        )
```

Add `case invalidResetMinuteOfDay` to `AppModelError`, and the setter beside the pause-duration one:

```swift
    func setResetMinuteOfDay(_ minute: Int, now: Date = Date()) throws {
        // Mirrors updatePauseSeconds: the same mutation gate runs first, so a
        // save that the coordinator is not ready for is refused the same way.
        try requireConfigurationMutation(.globalSettingsEdit)
        guard (0..<(24 * 60)).contains(minute),
              minute % GlobalSettings.resetMinuteStep == 0 else {
            throw AppModelError.invalidResetMinuteOfDay
        }
        guard configurationStore != nil else {
            throw AppModelError.storageUnavailable
        }

        var nextConfiguration = configuration
        nextConfiguration.settings = try GlobalSettings(
            pauseSeconds: configuration.settings.pauseSeconds,
            resetMinuteOfDay: minute
        )
        do {
            try persist(nextConfiguration, now: now)
        } catch {
            activationCoordinator.configurationSaveCompleted(successfully: false)
            throw error
        }
    }
```

- [ ] **Step 4: Add the picker**

SwiftUI's `DatePicker` exposes no minute-interval setting, so this is a plain `Picker` over the ninety-six valid positions. Add to the settings `Section` in `Sources/Pause/RulesView.swift`, below the pause-duration `Stepper`:

```swift
                Picker(selection: resetMinuteOfDay) {
                    ForEach(Array(stride(from: 0, through: 1425, by: 15)), id: \.self) { minute in
                        Text(Self.resetLabel(for: minute)).tag(minute)
                    }
                } label: {
                    Text("Day reset")
                }
```

And beside the existing `pauseSeconds` binding:

```swift
    private var resetMinuteOfDay: Binding<Int> {
        Binding(
            get: { model.configuration.settings.resetMinuteOfDay },
            set: { minute in
                do {
                    try model.setResetMinuteOfDay(minute)
                } catch {
                    model.presentedError = AppError(title: "Couldn't save", error: error)
                }
            }
        )
    }

    private static func resetLabel(for minute: Int) -> String {
        var components = DateComponents()
        components.hour = minute / 60
        components.minute = minute % 60
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
```

Match the error-handling shape to whatever the existing `pauseSeconds` binding does — copy its `catch` verbatim rather than the sketch above if it differs.

Update the section `footer` to mention both settings:

```swift
                Text("The pause shown before every allowed session, and the time each day's sessions renew.")
```

- [ ] **Step 5: Run the full suite and the build**

Run the full suite, then the generic-device build. Expected: all PASS, BUILD SUCCEEDED, no Swift warnings.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: choose the daily reset time in settings"
```

---

### Task 6: Close it out

**Files:**
- Modify: `docs/status.md`
- Modify: `docs/ROADMAP.md`
- Modify: `docs/README.md`

- [ ] **Step 1: Verify the whole change**

```bash
xcodegen generate
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git status --short
```

Record the passing test count.

- [ ] **Step 2: Update the status block**

Rewrite `## Status — resume here` in `docs/status.md` to state that the configurable reset is built, that the device check below has not run, and that blocking periods are the remaining half of the Phase 2 gate. Keep it to the block's four parts — state, next step, blockers, read first.

- [ ] **Step 3: Update docs/README.md**

The model section says the allowance renews "at the start of the next logical day". Extend it to say the reset is a setting on a fifteen-minute grid applying to all seven days, defaulting to midnight. Add the immediate-application consequence to the "what it knowingly does not do" list, in one line, pointing at the design.

- [ ] **Step 4: Note the device check on the roadmap**

Add to `docs/ROADMAP.md` under Deferred: the reset change is unverified on the phone, and the check is to move the reset and confirm the session count renews at the new time rather than at midnight.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "docs: record the configurable reset and what the device still owes"
```

---

## Device check

Not a task — it needs a signed build on the phone and cannot run in the simulator.

Move the reset to a quarter-hour a few minutes ahead, spend a session so the count is non-zero, and wait for the reset to pass. Confirm the count renews at the new time rather than at midnight, and that the shield reflects the renewed allowance. Record the result in the status block.
