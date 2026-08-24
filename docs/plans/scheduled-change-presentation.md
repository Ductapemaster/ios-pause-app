# Scheduled change presentation — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put every scheduled change on the row of the thing it changes, cancellable one app at a time, and lock a control while a change is pending on it.

**Architecture:** The model stops describing pending state four document-shaped ways and exposes two per-row lookups instead. The rules list gains a marker per row and loses its banner and its bespoke removal row. The rule editor gains a pending section carrying the cancel, and locks its controls while a change is scheduled. `ConfigurationSaveRouter` and `ConfigurationComparison` are not touched.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XcodeGen. iOS 26.5 deployment target.

**Spec:** `docs/design/scheduled-change-presentation.md` — read it before Task 1. The plan argues from it.

## Global Constraints

- **The router is untouched.** No changes to `Sources/Shared/ConfigurationSaveRouter.swift` or `Sources/Shared/ConfigurationComparison.swift`. Any task that seems to need one is a signal to stop and re-read the spec.
- **Marker symbols, exact:** `calendar.badge.clock` for a pending allowance loosening, `calendar.badge.minus` for a pending removal. Accent tint (`.tint`).
- **Button titles, exact:** `Cancel change` for an allowance loosening and for the pause duration; `Cancel removal` for a removal.
- **Test target routing:** `AppModel` tests → `Tests/PauseAppTests/`. Wording/pure-function tests → `Tests/PauseAppTests/ScheduledChangeWordingTests.swift` (the wording types live in the app target, not Shared). Router tests → `Tests/SharedTests/`.
- **Test naming:** `test` + a present-tense English sentence, CamelCased, articles kept. E.g. `testCancellingOneAppsChangeLeavesAnothersStanding`.
- **Test style:** no `setUp`/`tearDown` in the flow tests — each test makes a temp directory and cleans up with `defer`. Arrange / blank line / one act line / blank line / assertions.
- **Run the suite:** `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`. Narrow with `-only-testing:PauseAppTests/AppModelFlowTests`. Run `xcodegen generate` first only if `project.yml` changed or a file was added or deleted.
- **Baseline:** 328 tests green before Task 1.

## File structure

| File | Responsibility after this plan |
|---|---|
| `Sources/Pause/PendingChange.swift` | **New.** `PendingRuleChange`, `PendingSettingsChange`, and their symbol/title vocabulary. |
| `Sources/Pause/ScheduledChangeWording.swift` | **New.** `phrase` (moved) plus per-rule and per-settings description. |
| `Sources/Pause/ScheduledChangeNotice.swift` | **Deleted** at Task 6. Its `CalendarDay.date(in:)` extension moves to the wording file. |
| `Sources/Pause/AppModel.swift` | Two lookups and two cancels replace four accessors and one cancel. |
| `Sources/Pause/RulesView.swift` | Uniform rows with a marker; no banner, no removal row. |
| `Sources/Pause/RuleEditorView.swift` | Pending section, locked controls, own dismiss decision. |
| `Sources/Pause/AllowanceSection.swift` | Gains an enabled flag. |

---

### Task 1: The per-row pending lookups

**Files:**
- Create: `Sources/Pause/PendingChange.swift`
- Modify: `Sources/Pause/AppModel.swift` — add lookups after `ruleIDsPendingRemoval` (~:710-718)
- Test: `Tests/PauseAppTests/AppModelFlowTests.swift`

**Interfaces:**
- Consumes: `ConfigurationFile.pending`, `AppModel.configuration`, `AppModel.configurationFile`.
- Produces: `PendingRuleChange`, `PendingSettingsChange`, `AppModel.pendingChange(forRuleID:) -> PendingRuleChange?`, `AppModel.pendingSettingsChange() -> PendingSettingsChange?`.

- [ ] **Step 1: Create the types**

Create `Sources/Pause/PendingChange.swift`:

```swift
import PauseCore
import SwiftUI

/// What is scheduled for one app, and the day it starts.
///
/// Only a loosening is ever scheduled, so there are two kinds: the app leaves
/// Pause, or its allowance rises. Adding an app is a tightening and applies at
/// once, so it never appears here.
struct PendingRuleChange: Equatable {
    enum Kind: Equatable {
        case removal
        case allowance(sessionsPerDay: Int?, sessionLengthMinutes: Int?)
    }

    let kind: Kind
    let startDay: CalendarDay
}

extension PendingRuleChange.Kind {
    /// Leaving Pause is not the same event as a longer session, and the list is
    /// what gets scanned to see what is about to happen.
    var symbolName: String {
        switch self {
        case .removal: "calendar.badge.minus"
        case .allowance: "calendar.badge.clock"
        }
    }

    /// The symbol carries no text, so it needs one for VoiceOver.
    var accessibilityLabel: String {
        switch self {
        case .removal: "Being removed"
        case .allowance: "Allowance changing"
        }
    }

    var cancelTitle: String {
        switch self {
        case .removal: "Cancel removal"
        case .allowance: "Cancel change"
        }
    }
}

/// A scheduled change to the global settings. Only a shorter pause loosens, so
/// that is the only thing this can carry.
struct PendingSettingsChange: Equatable {
    let pauseSeconds: Int
    let startDay: CalendarDay
}
```

- [ ] **Step 2: Write the failing tests**

Add to `Tests/PauseAppTests/AppModelFlowTests.swift`, before the `// MARK: - Helpers`-style helper block at `:813`:

```swift
    func testARuleWithAScheduledLooseningReportsItsPendingChange() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updateRule(id: ruleID, sessionsPerDay: 5, sessionLengthMinutes: 5, now: now)

        XCTAssertEqual(
            model.pendingChange(forRuleID: ruleID),
            PendingRuleChange(
                kind: .allowance(sessionsPerDay: 5, sessionLengthMinutes: nil),
                startDay: LogicalDay.next(after: now, resetMinuteOfDay: 0, calendar: .current)
            )
        )
    }

    func testARuleBeingRemovedReportsARemovalRatherThanAnAllowanceChange() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.removeRule(id: ruleID, now: now)

        XCTAssertEqual(model.pendingChange(forRuleID: ruleID)?.kind, .removal)
    }

    func testARuleWithNothingScheduledReportsNoPendingChange() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updateRule(id: ruleID, sessionsPerDay: 2, sessionLengthMinutes: 5, now: now)

        XCTAssertNil(model.pendingChange(forRuleID: ruleID))
    }

    // NOTE: this one calls `cancelScheduledSettingsChange`, which Task 2 adds.
    // Write it here but expect it to stay red until Task 2 lands.
    func testAShorterPauseIsReportedAsAPendingSettingsChangeAndALongerOneIsNot() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updatePauseSeconds(5, now: now)

        XCTAssertEqual(model.pendingSettingsChange()?.pauseSeconds, 5)

        model.cancelScheduledSettingsChange(now: now)
        try model.updatePauseSeconds(30, now: now)

        XCTAssertNil(model.pendingSettingsChange())
    }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseAppTests/AppModelFlowTests`

Expected: compile failure — `value of type 'AppModel' has no member 'pendingChange'`.

- [ ] **Step 4: Implement the lookups**

In `Sources/Pause/AppModel.swift`, add after `ruleIDsPendingRemoval` (~:718). Leave the existing accessors alone for now; Task 6 deletes them.

```swift
    /// What is scheduled for one app, or nothing.
    ///
    /// The start day is the one already stamped on the model, not one resolved
    /// from the clock here: it was placed against the reset of the file that
    /// holds it, and re-deriving it against `Date()` would answer a different
    /// question — and answer it wrongly for any caller working at a fixed
    /// instant. It is also `nil` once the change has landed, which is exactly
    /// when there is nothing left to report.
    func pendingChange(forRuleID ruleID: UUID) -> PendingRuleChange? {
        guard let pending = configurationFile?.pending,
              let startDay = pendingChangeStartDay else { return nil }

        let scheduled = pending.document
        guard let before = configuration.rules.first(where: { $0.id == ruleID }) else { return nil }

        guard let after = scheduled.rules.first(where: { $0.id == ruleID }) else {
            return PendingRuleChange(kind: .removal, startDay: startDay)
        }

        let sessionsPerDay = after.sessionsPerDay == before.sessionsPerDay
            ? nil
            : after.sessionsPerDay
        let sessionLengthMinutes = after.sessionLengthMinutes == before.sessionLengthMinutes
            ? nil
            : after.sessionLengthMinutes
        guard sessionsPerDay != nil || sessionLengthMinutes != nil else { return nil }

        return PendingRuleChange(
            kind: .allowance(
                sessionsPerDay: sessionsPerDay,
                sessionLengthMinutes: sessionLengthMinutes
            ),
            startDay: startDay
        )
    }

    /// A scheduled change to the global settings, or nothing. Only a shorter
    /// pause is ever scheduled; the day reset applies on save.
    func pendingSettingsChange() -> PendingSettingsChange? {
        guard let pending = configurationFile?.pending,
              let startDay = pendingChangeStartDay else { return nil }
        let scheduled = pending.document.settings
        guard scheduled.pauseSeconds != configuration.settings.pauseSeconds else { return nil }
        return PendingSettingsChange(pauseSeconds: scheduled.pauseSeconds, startDay: startDay)
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseAppTests/AppModelFlowTests`

Expected: PASS, no regressions in the file.

- [ ] **Step 6: Commit**

```bash
git add Sources/Pause/PendingChange.swift Sources/Pause/AppModel.swift Tests/PauseAppTests/AppModelFlowTests.swift
git commit -m "Ask the model what is scheduled for one app"
```

---

### Task 2: Cancelling one app's change

**Files:**
- Modify: `Sources/Pause/AppModel.swift` — beside `cancelScheduledChange(now:)` (~:644-662)
- Test: `Tests/PauseAppTests/AppModelFlowTests.swift`

**Interfaces:**
- Consumes: `PendingRuleChange` from Task 1; `ConfigurationComparison.units(of:)`.
- Produces: `AppModel.cancelScheduledChange(ruleID:now:)`, `AppModel.cancelScheduledSettingsChange(now:)`.

**Note on collapsing.** Whether the rebuilt document equals the in-force one must be judged by *units*, not by `ConfigurationDocument` equality: restoring a removed app appends it, so two documents with identical content can differ in array order. Compare `ConfigurationComparison.units(of:)` dictionaries plus `settings`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/PauseAppTests/AppModelFlowTests.swift`. Note `seedTwoRules` is a new helper added in Step 3.

```swift
    func testCancellingOneAppsChangeLeavesAnothersStanding() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secondRuleID = try seedTwoRules(in: directory)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        try model.updateRule(id: ruleID, sessionsPerDay: 6, sessionLengthMinutes: 5, now: now)
        try model.updateRule(id: secondRuleID, sessionsPerDay: 7, sessionLengthMinutes: 5, now: now)

        model.cancelScheduledChange(ruleID: ruleID, now: now)

        XCTAssertNil(model.pendingChange(forRuleID: ruleID))
        XCTAssertEqual(
            model.pendingChange(forRuleID: secondRuleID)?.kind,
            .allowance(sessionsPerDay: 7, sessionLengthMinutes: nil)
        )
    }

    func testCancellingTheOnlyPendingChangeLeavesNothingScheduled() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        try model.updateRule(id: ruleID, sessionsPerDay: 6, sessionLengthMinutes: 5, now: now)

        model.cancelScheduledChange(ruleID: ruleID, now: now)

        XCTAssertNil(model.configurationFile?.pending)
        XCTAssertNil(model.pendingChangeStartDay)
    }

    func testCancellingARemovalRestoresTheAppAndKeepsItsChargedSessions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        try RuntimeRepository(directoryURL: directory).save(
            RuleRuntime(
                logicalDay: LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: .current),
                sessionsStarted: 2
            ),
            ruleID: ruleID
        )
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        try model.removeRule(id: ruleID, now: now)

        model.cancelScheduledChange(ruleID: ruleID, now: now)

        XCTAssertNil(model.configurationFile?.pending)
        XCTAssertEqual(model.configuration.rules.map(\.id), [ruleID])
        XCTAssertEqual(model.sessionsUsedByRule[ruleID], 2)
    }

    func testCancellingAPendingPauseLeavesAnAppsChangeStanding() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        try model.updateRule(id: ruleID, sessionsPerDay: 6, sessionLengthMinutes: 5, now: now)
        try model.updatePauseSeconds(5, now: now)

        model.cancelScheduledSettingsChange(now: now)

        XCTAssertNil(model.pendingSettingsChange())
        XCTAssertEqual(
            model.pendingChange(forRuleID: ruleID)?.kind,
            .allowance(sessionsPerDay: 6, sessionLengthMinutes: nil)
        )
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseAppTests/AppModelFlowTests`

Expected: compile failure — no `cancelScheduledChange(ruleID:now:)`, no `seedTwoRules`.

- [ ] **Step 3: Add the two-rule fixture**

In `Tests/PauseAppTests/AppModelFlowTests.swift`, beside `seedOneRule` (~:843):

```swift
    /// Two covered apps, so a change to one can be told from a change to the
    /// other. Returns the second rule's id; the first is `ruleID`.
    @discardableResult
    private func seedTwoRules(in directory: URL) throws -> UUID {
        let secondRuleID = UUID(uuidString: "9c2f4a71-5d38-4e6b-9f10-2b7c8e4a1d55")!
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: try ConfigurationDocument(
                    settings: .phaseOneDefault,
                    rules: [
                        try AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5),
                        try AppRule(id: secondRuleID, sessionsPerDay: 3, sessionLengthMinutes: 5),
                    ],
                    targets: [
                        RuleTarget(
                            ruleID: ruleID,
                            applicationToken: try token(seed: "instagram"),
                            launchRoute: nil
                        ),
                        RuleTarget(
                            ruleID: secondRuleID,
                            applicationToken: try token(seed: "threads"),
                            launchRoute: nil
                        ),
                    ]
                ),
                pending: nil
            )
        )
        let runtimes = RuntimeRepository(directoryURL: directory)
        let today = LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: .current)
        try runtimes.save(RuleRuntime(logicalDay: today, sessionsStarted: 0), ruleID: ruleID)
        try runtimes.save(RuleRuntime(logicalDay: today, sessionsStarted: 0), ruleID: secondRuleID)
        return secondRuleID
    }
```

- [ ] **Step 4: Implement the two cancels**

In `Sources/Pause/AppModel.swift`, after `cancelScheduledChange(now:)` (~:662):

```swift
    /// Drops what is scheduled for one app, leaving every other app's scheduled
    /// change exactly as it was.
    ///
    /// The unit to revert to is always still there: the in-force document keeps
    /// the full unit for any app whose change is only pending, and nothing is
    /// purged until its own reset lands.
    func cancelScheduledChange(ruleID: UUID, now: Date = Date()) {
        guard let file = configurationFile, let pending = file.pending else { return }
        let inForce = file.inForce(at: now)

        var document = pending.document
        document.rules.removeAll { $0.id == ruleID }
        document.targets.removeAll { $0.ruleID == ruleID }
        if let rule = inForce.rules.first(where: { $0.id == ruleID }) {
            document.rules.append(rule)
            if let target = inForce.targets.first(where: { $0.ruleID == ruleID }) {
                document.targets.append(target)
            }
        }

        writeScheduled(document, keeping: inForce, startDay: pending.startDay, now: now)
    }

    /// Drops a scheduled pause duration, leaving every app's scheduled change
    /// alone. Settings are one unit with no rule id, so they cancel by their own
    /// door rather than through a key invented to make the cases look alike.
    func cancelScheduledSettingsChange(now: Date = Date()) {
        guard let file = configurationFile, let pending = file.pending else { return }
        let inForce = file.inForce(at: now)

        var document = pending.document
        document.settings = inForce.settings

        writeScheduled(document, keeping: inForce, startDay: pending.startDay, now: now)
    }

    /// Saves a rebuilt scheduled document, collapsing it away when it no longer
    /// differs from what is in force.
    ///
    /// The comparison is by unit rather than by document: restoring a removed
    /// app appends it, so two documents with identical content can differ in the
    /// order of their arrays.
    private func writeScheduled(
        _ document: ConfigurationDocument,
        keeping inForce: ConfigurationDocument,
        startDay: CalendarDay,
        now: Date
    ) {
        guard let configurationStore else { return }
        let isUnchanged = ConfigurationComparison.units(of: document)
            == ConfigurationComparison.units(of: inForce)
            && document.settings == inForce.settings

        let next = ConfigurationFile(
            effective: inForce,
            pending: isUnchanged
                ? nil
                : PendingConfiguration(document: document, startDay: startDay)
        )
        do {
            try configurationStore.save(file: next)
            configurationFile = next
            configuration = next.inForce(at: now)
            pendingChangeStartDay = Self.scheduledStartDay(in: next, now: now)
            refreshUsage(now: now)
        } catch {
            presentedError = AppError(title: "Couldn't cancel the change", error: error)
        }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseAppTests/AppModelFlowTests`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Pause/AppModel.swift Tests/PauseAppTests/AppModelFlowTests.swift
git commit -m "Cancel one app's scheduled change without touching another's"
```

---

### Task 3: The wording, per app

**Files:**
- Create: `Sources/Pause/ScheduledChangeWording.swift`
- Modify: `Sources/Pause/ScheduledChangeNotice.swift` — remove the moved members
- Test: `Tests/PauseAppTests/ScheduledChangeWordingTests.swift`

**Interfaces:**
- Consumes: `PendingRuleChange`, `PendingSettingsChange`.
- Produces: `ScheduledChangeWording.phrase(for:in:now:)`, `ScheduledChangeWording.description(of:in:now:)`, `ScheduledChangeWording.settingsDescription(of:in:now:)`.

**Note.** `ScheduledChangeSentence` is not ported. It exists because `Label(token)` renders a view rather than a string, so a sentence about an app had to be a token plus a predicate assembled by the view. A per-app screen already shows the app, so its sentence has no subject and is plain `Text`.

- [ ] **Step 1: Write the failing tests**

Replace the contents of `Tests/PauseAppTests/ScheduledChangeWordingTests.swift` with the cases below. Every existing test in that file exercises `sentence(for:starting:)` or `changes(from:to:)`, both of which this task deletes.

```swift
import Foundation
import ManagedSettings
import PauseCore
import XCTest
@testable import Pause

final class ScheduledChangeWordingTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testAChangeStartingTheNextAllowanceDayReadsAsTomorrow() throws {
        let file = try fileWithReset(minuteOfDay: 0)

        XCTAssertEqual(
            ScheduledChangeWording.phrase(
                for: file.nextLogicalDay(after: now, calendar: calendar),
                in: file,
                now: now
            ),
            "tomorrow"
        )
    }

    func testARaisedSessionCountIsNamedWithoutTheLengthThatDidNotMove() throws {
        let file = try fileWithReset(minuteOfDay: 0)
        let change = PendingRuleChange(
            kind: .allowance(sessionsPerDay: 4, sessionLengthMinutes: nil),
            startDay: file.nextLogicalDay(after: now, calendar: calendar)
        )

        XCTAssertEqual(
            ScheduledChangeWording.description(of: change, in: file, now: now),
            "Changes to 4 sessions tomorrow."
        )
    }

    func testBothAllowanceFieldsMovingAreNamedTogether() throws {
        let file = try fileWithReset(minuteOfDay: 0)
        let change = PendingRuleChange(
            kind: .allowance(sessionsPerDay: 1, sessionLengthMinutes: 16),
            startDay: file.nextLogicalDay(after: now, calendar: calendar)
        )

        XCTAssertEqual(
            ScheduledChangeWording.description(of: change, in: file, now: now),
            "Changes to 1 session of 16 minutes tomorrow."
        )
    }

    func testARemovalSaysTheAppIsShieldedUntilItGoes() throws {
        let file = try fileWithReset(minuteOfDay: 0)
        let change = PendingRuleChange(
            kind: .removal,
            startDay: file.nextLogicalDay(after: now, calendar: calendar)
        )

        XCTAssertEqual(
            ScheduledChangeWording.description(of: change, in: file, now: now),
            "Leaves Pause tomorrow. Until then it is shielded as normal."
        )
    }

    func testAShorterPauseIsNamedInSeconds() throws {
        let file = try fileWithReset(minuteOfDay: 0)
        let change = PendingSettingsChange(
            pauseSeconds: 1,
            startDay: file.nextLogicalDay(after: now, calendar: calendar)
        )

        XCTAssertEqual(
            ScheduledChangeWording.settingsDescription(of: change, in: file, now: now),
            "The pause changes to 1 second tomorrow."
        )
    }

    // MARK: - Helpers

    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func fileWithReset(minuteOfDay: Int) throws -> ConfigurationFile {
        ConfigurationFile(
            effective: try ConfigurationDocument(
                settings: GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: minuteOfDay),
                rules: [],
                targets: []
            ),
            pending: nil
        )
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseAppTests/ScheduledChangeWordingTests`

Expected: compile failure — no `description(of:in:now:)`.

- [ ] **Step 3: Create the wording file**

Create `Sources/Pause/ScheduledChangeWording.swift`:

```swift
import PauseCore
import SwiftUI

/// What a scheduled change is and when it starts, in the words the rules list
/// and the editor share.
enum ScheduledChangeWording {
    /// "tomorrow" for the ordinary case. Pause not being opened for a day leaves
    /// a start day that is neither tomorrow nor arrived, which reads as a date
    /// instead — formatted through `Date.formatted`, so the device locale
    /// decides the order of the fields.
    ///
    /// The file answers what tomorrow is, rather than a reset minute picked out
    /// here: the day being named was stamped by the file's own reset, so only
    /// that reset can say whether it is the next one.
    static func phrase(for day: CalendarDay, in file: ConfigurationFile, now: Date = Date()) -> String {
        if day == file.nextLogicalDay(after: now) {
            return "tomorrow"
        }
        guard let date = day.date(in: .current) else { return "at the next reset" }
        return "on \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// One app's scheduled change, for the section under its controls. The
    /// screen already names the app, so the sentence has no subject.
    static func description(
        of change: PendingRuleChange,
        in file: ConfigurationFile,
        now: Date = Date()
    ) -> String {
        let when = phrase(for: change.startDay, in: file, now: now)
        switch change.kind {
        case .removal:
            return "Leaves Pause \(when). Until then it is shielded as normal."
        case let .allowance(sessionsPerDay, sessionLengthMinutes):
            return "Changes to \(allowance(sessionsPerDay, sessionLengthMinutes)) \(when)."
        }
    }

    static func settingsDescription(
        of change: PendingSettingsChange,
        in file: ConfigurationFile,
        now: Date = Date()
    ) -> String {
        "The pause changes to \(count(change.pauseSeconds, "second")) "
            + "\(phrase(for: change.startDay, in: file, now: now))."
    }

    /// The allowance names only the field that moved, so a session count that
    /// did not change is not read back as though it had.
    private static func allowance(_ sessionsPerDay: Int?, _ sessionLengthMinutes: Int?) -> String {
        switch (sessionsPerDay, sessionLengthMinutes) {
        case let (sessions?, minutes?):
            "\(count(sessions, "session")) of \(count(minutes, "minute"))"
        case let (sessions?, nil):
            count(sessions, "session")
        case let (nil, minutes?):
            "\(minutes)-minute sessions"
        case (nil, nil):
            "a new allowance"
        }
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}

extension CalendarDay {
    /// The day as a date, for formatting. A `CalendarDay` carries the fields a
    /// calendar needs to name the day and nothing else, so this can fail on a
    /// calendar that cannot form them.
    func date(in calendar: Calendar) -> Date? {
        calendar.date(
            from: DateComponents(era: era, year: year, month: month, day: day)
        )
    }
}
```

- [ ] **Step 4: Remove the moved members from the old file**

In `Sources/Pause/ScheduledChangeNotice.swift`, delete the `ScheduledChangeWording` enum (`:29-159`) and the `extension CalendarDay` (`:204-213`). Leave `ScheduledChange`, `ScheduledChangeSentence` and `ScheduledChangeNotice` in place — Task 6 deletes the whole file once nothing uses it.

The notice still calls `ScheduledChangeWording.sentence(...)`, which no longer exists, so temporarily replace its `sentence` body (`:183-201`) with:

```swift
    @ViewBuilder
    private var sentence: some View {
        Text("A change to your rules starts \(startPhrase).")
    }
```

and delete `ScheduledChangeSentence` (`:18-27`) along with it. This view is deleted in Task 6; this keeps the tree compiling in between.

- [ ] **Step 5: Run the whole suite**

Run: `xcodegen generate && xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Expected: `** TEST SUCCEEDED **`. Test count drops by ~10 as the sentence-collapsing tests go.

- [ ] **Step 6: Commit**

```bash
git add Sources/Pause/ScheduledChangeWording.swift Sources/Pause/ScheduledChangeNotice.swift Tests/PauseAppTests/ScheduledChangeWordingTests.swift
git commit -m "Say what one app's scheduled change is, without a subject"
```

---

### Task 4: The rules list

**Files:**
- Modify: `Sources/Pause/RulesView.swift` — body (`:56-117`), delete `pendingRemovalRow` (`:119-142`) and `removalPhrase` (`:144-148`)

**Interfaces:**
- Consumes: `AppModel.pendingChange(forRuleID:)`, `AppModel.pendingSettingsChange()`, `PendingRuleChange.Kind.symbolName`, `.accessibilityLabel`, `ScheduledChangeWording.settingsDescription`, `AppModel.cancelScheduledSettingsChange(now:)`.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Replace the Apps section**

In `Sources/Pause/RulesView.swift`, delete the banner section (`:58-62`) entirely, and replace the Apps section (`:64-88`) with:

```swift
            Section("Apps") {
                ForEach(model.configuration.rules) { rule in
                    if let target = model.configuration.targets.first(where: { $0.ruleID == rule.id }) {
                        NavigationLink {
                            RuleEditorView(
                                model: model,
                                rule: rule,
                                applicationToken: target.applicationToken
                            )
                        } label: {
                            HStack {
                                AppTokenLabel(applicationToken: target.applicationToken)

                                if let kind = model.pendingChange(forRuleID: rule.id)?.kind {
                                    Image(systemName: kind.symbolName)
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel(kind.accessibilityLabel)
                                }

                                Spacer()
                                Text(usageText(for: rule))
                                    .font(.system(.body, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
```

An app on its way out is now a link like any other, and keeps its count: it is still in force, still shielded, and still spending sessions until the reset.

- [ ] **Step 2: Lock the pause duration and give it a cancel**

Replace the settings section (`:90-107`) with:

```swift
            Section {
                Stepper(value: pauseSeconds, in: 1...120) {
                    LabeledContent("Pause duration") {
                        Text("\(model.configuration.settings.pauseSeconds) sec")
                            .font(.system(.body, design: .rounded).monospacedDigit())
                    }
                }
                .disabled(model.pendingSettingsChange() != nil)

                Picker(selection: resetMinuteOfDay) {
                    ForEach(Array(stride(from: 0, through: 1425, by: 15)), id: \.self) { minute in
                        Text(Self.resetLabel(for: minute)).tag(minute)
                    }
                } label: {
                    Text("Day reset")
                }
            } footer: {
                if let change = model.pendingSettingsChange(), let file = model.configurationFile {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ScheduledChangeWording.settingsDescription(of: change, in: file))
                        Button("Cancel change") {
                            model.cancelScheduledSettingsChange()
                        }
                    }
                } else {
                    Text("The pause shown before every allowed session, and the time each day's sessions renew.")
                }
            }
```

The stepper commits on each nudge rather than behind a Save, so there is no save to block — locking the control is what the rule amounts to here. The day reset is never locked: a reset change is not tested for loosening, so it applies on save.

- [ ] **Step 3: Delete the removal row and its helper**

Delete `pendingRemovalRow` (`:119-142`) and `removalPhrase` (`:144-148`) from `Sources/Pause/RulesView.swift`.

- [ ] **Step 4: Build and run the suite**

Run: `xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' && xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Pause/RulesView.swift
git commit -m "Mark the row of the app a scheduled change belongs to"
```

---

### Task 5: The rule editor

**Files:**
- Modify: `Sources/Pause/RuleEditorView.swift` — whole body
- Modify: `Sources/Pause/AllowanceSection.swift` — add an enabled flag

**Interfaces:**
- Consumes: `AppModel.pendingChange(forRuleID:)`, `AppModel.cancelScheduledChange(ruleID:now:)`, `ScheduledChangeWording.description(of:in:now:)`, `PendingRuleChange.Kind.cancelTitle`.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Let the allowance controls be disabled**

In `Sources/Pause/AllowanceSection.swift`, add the property after `footer` (`:13`):

```swift
    var isEnabled = true
```

and apply it to the section body — change `Section {` at `:16` to keep its content and add the modifier to the whole section, immediately before the `} footer: {` closing at `:30`:

```swift
        } footer: {
            if let footer {
                Text(footer)
            }
        }
        .disabled(!isEnabled)
```

- [ ] **Step 2: Rewrite the editor**

Replace `Sources/Pause/RuleEditorView.swift` in full:

```swift
import ManagedSettings
import PauseCore
import SwiftUI

struct RuleEditorView: View {
    @ObservedObject var model: AppModel
    let applicationToken: ApplicationToken

    @Environment(\.dismiss) private var dismiss
    @State private var sessionsPerDay: Int
    @State private var sessionLengthMinutes: Int

    init(model: AppModel, rule: AppRule, applicationToken: ApplicationToken) {
        self.model = model
        self.applicationToken = applicationToken
        _sessionsPerDay = State(initialValue: rule.sessionsPerDay)
        _sessionLengthMinutes = State(initialValue: rule.sessionLengthMinutes)
        ruleID = rule.id
    }

    var body: some View {
        Form {
            Section {
                AppTokenLabel(applicationToken: applicationToken)
            }

            AllowanceSection(
                sessionsPerDay: $sessionsPerDay,
                sessionLengthMinutes: $sessionLengthMinutes,
                isEnabled: pendingChange == nil
            )

            if let change = pendingChange {
                Section {
                    if let file = model.configurationFile {
                        Text(ScheduledChangeWording.description(of: change, in: file))
                    }
                    Button(change.kind.cancelTitle) {
                        model.cancelScheduledChange(ruleID: ruleID)
                    }
                }
            }

            Section {
                Button("Remove app", role: .destructive) {
                    removeRule()
                }
                .disabled(pendingChange != nil)
            }
        }
        .navigationTitle("Allowance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(pendingChange != nil)
            }
        }
    }

    private let ruleID: UUID

    /// What is scheduled for this app, if anything. Everything the screen does
    /// differently under a pending change comes from this one lookup.
    private var pendingChange: PendingRuleChange? {
        model.pendingChange(forRuleID: ruleID)
    }

    private func save() {
        do {
            try model.updateRule(
                id: ruleID,
                sessionsPerDay: sessionsPerDay,
                sessionLengthMinutes: sessionLengthMinutes
            )
            // A save that waits stays on screen, so the wait is visible where it
            // was chosen, under the section that can cancel it. One that applied
            // at once is done.
            if pendingChange == nil {
                dismiss()
            }
        } catch {
            model.present(error)
        }
    }

    private func removeRule() {
        do {
            try model.removeRule(id: ruleID)
            dismiss()
        } catch {
            model.present(error, title: "Couldn't remove app")
        }
    }
}
```

Two things to note. The controls, Save, and Remove are all disabled together — a pending change must be cancelled before the app can be edited again, and an editor that cannot save cannot silently write over what is scheduled. And the dismiss decision now comes from this app's own pending state rather than from the document-scoped `lastSaveDeferredPart`.

- [ ] **Step 3: Build and run the suite**

Run: `xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' && xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Pause/RuleEditorView.swift Sources/Pause/AllowanceSection.swift
git commit -m "Lock an app's controls while a change is scheduled for it"
```

---

### Task 6: Delete what nothing uses

**Files:**
- Delete: `Sources/Pause/ScheduledChangeNotice.swift`
- Modify: `Sources/Pause/AppModel.swift` — remove `scheduledChanges`, `ruleIDsPendingRemoval`, `lastSaveDeferredPart`
- Modify: `Tests/PauseAppTests/AppModelFlowTests.swift` — the assertions that name them
- Modify: `docs/README.md`

- [ ] **Step 1: Confirm nothing references them**

Run:

```bash
grep -rn "ScheduledChangeNotice\|ScheduledChangeSentence\|scheduledChanges\|ruleIDsPendingRemoval\|lastSaveDeferredPart" Sources/ Tests/
```

Also check the document-wide cancel has no callers left:

```bash
grep -rn "cancelScheduledChange(" Sources/ Tests/ | grep -v "ruleID:"
```

Expected: for both greps, hits only in `AppModel.swift`, `ScheduledChangeNotice.swift`, and `AppModelFlowTests.swift`. Any hit in another view means an earlier task is incomplete — stop and finish it.

- [ ] **Step 2: Delete**

```bash
git rm Sources/Pause/ScheduledChangeNotice.swift
```

In `Sources/Pause/AppModel.swift` remove: the `lastSaveDeferredPart` property and its doc comment (`:99-102`), its computation in `persist` (`:958`), the `scheduledChanges` and `ruleIDsPendingRemoval` computed properties (`:702-718`), and the whole document-wide `cancelScheduledChange(now:)` (`:644-662`).

That last one is the fault this redesign exists to correct — one button dropping every app's scheduled change — so it goes rather than being left for something to call again. Its two callers, the banner and the removal row, are already deleted; `cancelScheduledChange(ruleID:)` and `cancelScheduledSettingsChange()` replace it.

- [ ] **Step 3: Update the tests that name them**

In `Tests/PauseAppTests/AppModelFlowTests.swift`, three assertions reference the deleted members:

- `:396` and `:555`, `:560` — `XCTAssert*(model.lastSaveDeferredPart)`. Replace each with the equivalent question asked of the rule: `XCTAssertNotNil(model.pendingChange(forRuleID: ruleID))` where the flag was expected true, `XCTAssertNil(...)` where false.
- `testDroppingAnAppFromThePickerKeepsItSelectedUntilTheRemovalLands` (`:336`) and `testTheRemovalTakesTheAppAndItsSelectionWhenItLands` (`:355`) — replace `XCTAssertEqual(model.ruleIDsPendingRemoval, [ruleID])` with `XCTAssertEqual(model.pendingChange(forRuleID: ruleID)?.kind, .removal)`, and `XCTAssertEqual(model.ruleIDsPendingRemoval, [])` with `XCTAssertNil(model.pendingChange(forRuleID: ruleID))`.

- [ ] **Step 4: Correct the overview**

In `docs/README.md`, the gap list bullet beginning **"A save states its opinion by rebuilding"** is now unreachable from the interface but still true of the router. Replace that bullet with:

```markdown
- **A save states its opinion by rebuilding.** Touched is inferred from the resulting document rather than declared by the screen, so a save that changes nothing reads as untouched and carries a scheduled change forward. Nothing in the interface can reach it: a pending change locks the controls of the thing it changes, so there is no save to make while one is standing. Closed by construction rather than fixed.
```

- [ ] **Step 5: Run the whole suite and build for device**

Run: `xcodegen generate && xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' && xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS'`

Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Delete the banner and the four ways of asking one question"
```

---

## Device checks owed after this plan

Neither is reachable by a unit test — `RulesView` and `RuleEditorView` have no snapshot harness, so the marker's presence is pinned on the model's per-rule lookup rather than on a rendered row. Add these to `docs/ROADMAP.md` under Deferred when the work lands:

- Both markers read correctly at a glance in a list of several apps, and the removal marker is tellable from the allowance one.
- An app with a pending change opens to locked controls and a section naming the change, and cancelling frees the controls at the values in force.
- Cancelling one app's change leaves another's marker standing — the fault that motivated the redesign, and the one thing that cannot be seen in a single-app test.
