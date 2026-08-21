# Deferred rule changes implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An edit that loosens a rule takes effect at the start of the next logical day; an edit that tightens applies immediately.

**Architecture:** `configuration.json` gains a wrapper holding an effective document and an optional pending one with a start day. Readers never promote the pending document; they select whichever applies on the logical day they are asked about, so no reader needs write access — which matters because the shield configuration extension has none. A repeating daily Device Activity gives the monitor a callback at the reset, where the consequences of a change taking effect are applied.

**Tech Stack:** Swift 6, iOS 26.5 minimum, XcodeGen, XCTest. FamilyControls, ManagedSettings, ManagedSettingsUI, DeviceActivity.

**Spec:** `docs/design/deferred-rule-changes.md`

## Global Constraints

- Run `xcodegen generate` after adding or removing any source file, before building.
- Test command: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- `Sources/Shared` compiles into the app and all three extensions. Any signature change there is a four-target change; check every call site before changing one.
- Nothing on the shield configuration extension's read path may write, create a file, or take `AppGroupFileLock`. See `docs/research/shield-repair-variant.md`.
- Every reader takes the in-force document, never `effective` directly.
- The logical day comes from `LogicalDay`, never from `CalendarDay(date:calendar:)` called inline. Phase 2 changes the reset time in one place.
- Commit after every task. Never commit to a default branch.

---

### Task 1: The logical day seam

**Files:**
- Create: `Sources/PauseCore/LogicalDay.swift`
- Test: `Tests/PauseCoreTests/LogicalDayTests.swift`

**Interfaces:**
- Produces: `LogicalDay.containing(_ date: Date, calendar: Calendar) -> CalendarDay`, `LogicalDay.next(after date: Date, calendar: Calendar) -> CalendarDay`

- [ ] **Step 1: Write the failing test**

```swift
import PauseCore
import XCTest

final class LogicalDayTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testTheLogicalDayContainingAnInstantIsItsCivilDate() {
        let now = date(year: 2026, month: 8, day: 20, hour: 23)
        XCTAssertEqual(
            LogicalDay.containing(now, calendar: calendar),
            CalendarDay(date: now, calendar: calendar)
        )
    }

    func testTheNextLogicalDayFollowsTheOneContainingTheInstant() {
        let now = date(year: 2026, month: 8, day: 20, hour: 23)
        let expected = CalendarDay(
            date: date(year: 2026, month: 8, day: 21),
            calendar: calendar
        )
        XCTAssertEqual(LogicalDay.next(after: now, calendar: calendar), expected)
    }

    func testTheNextLogicalDayCrossesAMonthBoundary() {
        let now = date(year: 2026, month: 8, day: 31, hour: 12)
        let expected = CalendarDay(
            date: date(year: 2026, month: 9, day: 1),
            calendar: calendar
        )
        XCTAssertEqual(LogicalDay.next(after: now, calendar: calendar), expected)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command. Expected: compile failure, `cannot find 'LogicalDay' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// The single place that decides which logical day an instant belongs to.
///
/// Phase 1 resets at midnight, so a logical day is a civil date. Phase 2 makes
/// the reset time configurable per weekday, and changes it here rather than at
/// every call site. Session counting and deferred rule changes both ask this
/// type, which is what keeps a rule change and the allowance reset it arrives
/// with on the same instant.
public enum LogicalDay {
    public static func containing(_ date: Date, calendar: Calendar = .current) -> CalendarDay {
        CalendarDay(date: date, calendar: calendar)
    }

    public static func next(after date: Date, calendar: Calendar = .current) -> CalendarDay {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return containing(tomorrow, calendar: calendar)
    }
}
```

- [ ] **Step 4: Regenerate and run the tests**

```bash
xcodegen generate
```
Then the test command. Expected: PASS, no other suite affected.

- [ ] **Step 5: Commit**

```bash
git add Sources/PauseCore/LogicalDay.swift Tests/PauseCoreTests/LogicalDayTests.swift
git commit -m "feat: name the logical day an instant belongs to"
```

---

### Task 2: The configuration file and its in-force selection

**Files:**
- Create: `Sources/Shared/ConfigurationFile.swift`
- Test: `Tests/SharedTests/ConfigurationFileTests.swift`

**Interfaces:**
- Consumes: `LogicalDay` from Task 1.
- Produces: `PendingConfiguration(document:startDay:)` with `.document` and `.startDay`; `ConfigurationFile(effective:pending:)` with `.effective`, `.pending`, and `func inForce(on logicalDay: CalendarDay) -> ConfigurationDocument`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import ManagedSettings
import PauseCore
import XCTest

final class ConfigurationFileTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testTheEffectiveDocumentAppliesWhenNothingIsPending() throws {
        let file = ConfigurationFile(effective: try document(sessionsPerDay: 3), pending: nil)

        XCTAssertEqual(file.inForce(on: day(2026, 8, 20)).rules[0].sessionsPerDay, 3)
    }

    func testTheEffectiveDocumentAppliesBeforeTheStartDay() throws {
        let file = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(
                document: try document(sessionsPerDay: 5),
                startDay: day(2026, 8, 21)
            )
        )

        XCTAssertEqual(file.inForce(on: day(2026, 8, 20)).rules[0].sessionsPerDay, 3)
    }

    func testThePendingDocumentAppliesOnItsStartDay() throws {
        let file = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(
                document: try document(sessionsPerDay: 5),
                startDay: day(2026, 8, 21)
            )
        )

        XCTAssertEqual(file.inForce(on: day(2026, 8, 21)).rules[0].sessionsPerDay, 5)
    }

    func testThePendingDocumentStillAppliesAfterItsStartDay() throws {
        let file = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(
                document: try document(sessionsPerDay: 5),
                startDay: day(2026, 8, 21)
            )
        )

        XCTAssertEqual(file.inForce(on: day(2026, 9, 1)).rules[0].sessionsPerDay, 5)
    }

    // MARK: - Helpers

    private let ruleID = UUID()

    private func document(sessionsPerDay: Int) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: sessionsPerDay, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: try token(seed: "a"), launchRoute: nil)]
        )
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> CalendarDay {
        CalendarDay(
            date: calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!,
            calendar: calendar
        )
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command. Expected: compile failure, `cannot find 'ConfigurationFile' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import PauseCore

/// A saved edit that has not reached its start day yet.
public struct PendingConfiguration: Codable, Equatable {
    public var document: ConfigurationDocument
    public var startDay: CalendarDay

    public init(document: ConfigurationDocument, startDay: CalendarDay) {
        self.document = document
        self.startDay = startDay
    }
}

/// What `configuration.json` holds: the rules in force now, and optionally a
/// scheduled replacement.
///
/// The pending document is selected at read time rather than promoted when its
/// start day arrives. Promotion would need a write, and the shield
/// configuration extension cannot write, so a shield rendering after the reset
/// would have no way to reach a configuration that had just taken effect.
public struct ConfigurationFile: Codable, Equatable {
    public var effective: ConfigurationDocument
    public var pending: PendingConfiguration?

    public init(effective: ConfigurationDocument, pending: PendingConfiguration? = nil) {
        self.effective = effective
        self.pending = pending
    }

    public func inForce(on logicalDay: CalendarDay) -> ConfigurationDocument {
        guard let pending, pending.startDay <= logicalDay else {
            return effective
        }
        return pending.document
    }
}
```

- [ ] **Step 4: Regenerate and run the tests**

```bash
xcodegen generate
```
Then the test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/ConfigurationFile.swift Tests/SharedTests/ConfigurationFileTests.swift
git commit -m "feat: hold a scheduled configuration beside the effective one"
```

---

### Task 3: Deciding whether an edit loosens

**Files:**
- Create: `Sources/Shared/ConfigurationComparison.swift`
- Test: `Tests/SharedTests/ConfigurationComparisonTests.swift`

**Interfaces:**
- Produces: `ConfigurationComparison.isLoosening(from: ConfigurationDocument, to: ConfigurationDocument) -> Bool`

Rules are paired by `AppRule.id`, targets by `RuleTarget.ruleID`. An edit loosens if any of these hold: a paired rule's `sessionsPerDay` rises; a paired rule's `sessionLengthMinutes` rises; a target present in `from` is absent in `to`; a paired target's `applicationToken` changes; `settings.pauseSeconds` falls.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import ManagedSettings
import PauseCore
import XCTest

final class ConfigurationComparisonTests: XCTestCase {
    private let ruleID = UUID()
    private let otherRuleID = UUID()

    func testRaisingTheDailyAllowanceLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try document(sessionsPerDay: 3),
            to: try document(sessionsPerDay: 5)
        ))
    }

    func testLoweringTheDailyAllowanceDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try document(sessionsPerDay: 5),
            to: try document(sessionsPerDay: 3)
        ))
    }

    func testLengtheningASessionLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try document(sessionLengthMinutes: 5),
            to: try document(sessionLengthMinutes: 10)
        ))
    }

    func testShorteningASessionDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try document(sessionLengthMinutes: 10),
            to: try document(sessionLengthMinutes: 5)
        ))
    }

    func testShorteningThePauseLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try document(pauseSeconds: 10),
            to: try document(pauseSeconds: 5)
        ))
    }

    func testLengtheningThePauseDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try document(pauseSeconds: 5),
            to: try document(pauseSeconds: 10)
        ))
    }

    func testRemovingATargetLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try twoRuleDocument(),
            to: try document(sessionsPerDay: 3)
        ))
    }

    func testAddingATargetDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try document(sessionsPerDay: 3),
            to: try twoRuleDocument()
        ))
    }

    func testPointingARuleAtAnotherApplicationLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try document(sessionsPerDay: 3, seed: "instagram"),
            to: try document(sessionsPerDay: 3, seed: "threads")
        ))
    }

    func testAnUnchangedDocumentDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try document(sessionsPerDay: 3),
            to: try document(sessionsPerDay: 3)
        ))
    }

    func testAnEditThatBothLoosensAndTightensLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try document(sessionsPerDay: 3, sessionLengthMinutes: 10),
            to: try document(sessionsPerDay: 5, sessionLengthMinutes: 5)
        ))
    }

    // MARK: - Helpers

    private func document(
        sessionsPerDay: Int = 3,
        sessionLengthMinutes: Int = 5,
        pauseSeconds: Int = 10,
        seed: String = "instagram"
    ) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: GlobalSettings(pauseSeconds: pauseSeconds),
            rules: [AppRule(id: ruleID, sessionsPerDay: sessionsPerDay, sessionLengthMinutes: sessionLengthMinutes)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: try token(seed: seed), launchRoute: nil)]
        )
    }

    private func twoRuleDocument() throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [
                AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5),
                AppRule(id: otherRuleID, sessionsPerDay: 3, sessionLengthMinutes: 5),
            ],
            targets: [
                RuleTarget(ruleID: ruleID, applicationToken: try token(seed: "instagram"), launchRoute: nil),
                RuleTarget(ruleID: otherRuleID, applicationToken: try token(seed: "threads"), launchRoute: nil),
            ]
        )
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command. Expected: compile failure, `cannot find 'ConfigurationComparison' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import PauseCore

/// Judges whether one configuration permits more app use than another.
///
/// The edit is judged whole: any loosening anywhere defers the entire edit.
/// Applying part of an edit now and part tomorrow would mean storing a
/// difference rather than a document, which is not worth the precision.
public enum ConfigurationComparison {
    public static func isLoosening(
        from before: ConfigurationDocument,
        to after: ConfigurationDocument
    ) -> Bool {
        if after.settings.pauseSeconds < before.settings.pauseSeconds {
            return true
        }

        let afterRules = Dictionary(uniqueKeysWithValues: after.rules.map { ($0.id, $0) })
        for rule in before.rules {
            guard let updated = afterRules[rule.id] else { continue }
            if updated.sessionsPerDay > rule.sessionsPerDay { return true }
            if updated.sessionLengthMinutes > rule.sessionLengthMinutes { return true }
        }

        let afterTargets = Dictionary(uniqueKeysWithValues: after.targets.map { ($0.ruleID, $0) })
        for target in before.targets {
            // A target that disappears, and one re-pointed at another
            // application, both drop coverage of the app it named.
            guard let updated = afterTargets[target.ruleID] else { return true }
            if updated.applicationToken != target.applicationToken { return true }
        }

        return false
    }
}
```

- [ ] **Step 4: Run the tests**

Run the test command. Expected: PASS, all eleven cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/ConfigurationComparison.swift Tests/SharedTests/ConfigurationComparisonTests.swift
git commit -m "feat: judge whether an edit permits more app use"
```

---

### Task 4: Persisting the file, and reading an older one

**Files:**
- Modify: `Sources/Shared/ConfigurationStore.swift`
- Test: `Tests/SharedTests/ConfigurationStoreFileTests.swift` (create)

**Interfaces:**
- Consumes: `ConfigurationFile` from Task 2.
- Produces: `ConfigurationStore.loadFile() throws -> ConfigurationFile?`, `ConfigurationStore.loadFileWithoutLocking() throws -> ConfigurationFile?`, `ConfigurationStore.save(file: ConfigurationFile) throws`.

The existing `load()`, `loadWithoutLocking()` and `save(_:)` stay and keep their `ConfigurationDocument` signatures for now; later tasks migrate their callers, and Task 12 removes them. `load()` returns the effective document during that window, which is unchanged behaviour while nothing writes a pending document yet.

Both documents in the file are validated on save. A pending document is held to the same rules as an effective one so an invalid document cannot wait in storage and take effect unwatched.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import ManagedSettings
import PauseCore
import XCTest

final class ConfigurationStoreFileTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let ruleID = UUID()

    func testAFileSurvivesASaveAndLoad() throws {
        let directoryURL = try temporaryDirectory()
        let store = ConfigurationStore(directoryURL: directoryURL)
        let file = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(
                document: try document(sessionsPerDay: 5),
                startDay: day(2026, 8, 21)
            )
        )

        try store.save(file: file)

        XCTAssertEqual(try store.loadFile(), file)
    }

    func testABareDocumentFromAnOlderBuildLoadsAsTheEffectiveOne() throws {
        let directoryURL = try temporaryDirectory()
        let legacy = try document(sessionsPerDay: 3)
        try AtomicJSONFile<ConfigurationDocument>(
            url: directoryURL.appendingPathComponent(SharedIdentifiers.configurationFilename)
        ).save(legacy)

        let loaded = try ConfigurationStore(directoryURL: directoryURL).loadFile()

        XCTAssertEqual(loaded, ConfigurationFile(effective: legacy, pending: nil))
    }

    func testAnInvalidPendingDocumentIsRefusedOnSave() throws {
        let directoryURL = try temporaryDirectory()
        let orphanedTarget = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: try token(seed: "a"), launchRoute: nil)]
        )
        let file = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(document: orphanedTarget, startDay: day(2026, 8, 21))
        )

        XCTAssertThrowsError(try ConfigurationStore(directoryURL: directoryURL).save(file: file))
    }

    func testTheLockFreeReadReturnsTheSameFile() throws {
        let directoryURL = try temporaryDirectory()
        let store = ConfigurationStore(directoryURL: directoryURL)
        let file = ConfigurationFile(effective: try document(sessionsPerDay: 3), pending: nil)
        try store.save(file: file)

        XCTAssertEqual(try store.loadFileWithoutLocking(), file)
    }

    // MARK: - Helpers

    private func document(sessionsPerDay: Int) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: sessionsPerDay, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: try token(seed: "a"), launchRoute: nil)]
        )
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> CalendarDay {
        CalendarDay(
            date: calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!,
            calendar: calendar
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-config-file-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command. Expected: compile failure, `value of type 'ConfigurationStore' has no member 'loadFile'`.

- [ ] **Step 3: Write the implementation**

Replace the body of `Sources/Shared/ConfigurationStore.swift` with this, keeping the two initialisers exactly as they are:

```swift
import Foundation

public struct ConfigurationStore {
    private let file: AtomicJSONFile<ConfigurationFile>
    private let legacyFile: AtomicJSONFile<ConfigurationDocument>
    private let stateLock: AppGroupFileLock

    public init(directoryURL: URL) {
        let url = directoryURL.appendingPathComponent(SharedIdentifiers.configurationFilename)
        file = AtomicJSONFile(url: url)
        legacyFile = AtomicJSONFile(url: url)
        stateLock = AppGroupFileLock(directoryURL: directoryURL)
    }

    public init(appGroupContainer: AppGroupContainer = AppGroupContainer()) throws {
        self.init(directoryURL: try appGroupContainer.directoryURL())
    }

    public func loadFile() throws -> ConfigurationFile? {
        try stateLock.withLock { try loadFileUnlocked() }
    }

    /// Reads without taking the state lock. See `RuntimeRepository.loadWithoutLocking`.
    public func loadFileWithoutLocking() throws -> ConfigurationFile? {
        try loadFileUnlocked()
    }

    public func save(file document: ConfigurationFile) throws {
        try stateLock.withLock {
            try document.effective.validate()
            try document.pending?.document.validate()
            try file.save(document)
        }
    }

    public func load() throws -> ConfigurationDocument? {
        try loadFile()?.effective
    }

    public func loadWithoutLocking() throws -> ConfigurationDocument? {
        try loadFileWithoutLocking()?.effective
    }

    public func save(_ document: ConfigurationDocument) throws {
        let existing = try loadFile()
        try save(file: ConfigurationFile(effective: document, pending: existing?.pending))
    }

    private func loadFileUnlocked() throws -> ConfigurationFile? {
        // A build before deferred changes wrote a bare document. The two shapes
        // are distinguishable by decoding, so no version field is needed.
        if let loaded = try? file.load(), let loaded {
            try loaded.effective.validate()
            try loaded.pending?.document.validate()
            return loaded
        }
        guard let legacy = try legacyFile.load() else { return nil }
        try legacy.validate()
        return ConfigurationFile(effective: legacy, pending: nil)
    }
}
```

Note the parameter label: `save(file:)` takes `file document:` because the stored property is already named `file`.

- [ ] **Step 4: Run the tests**

Run the test command. Expected: PASS, including every existing `ConfigurationStore` test in `Tests/SharedTests/AtomicJSONFileTests.swift`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/ConfigurationStore.swift Tests/SharedTests/ConfigurationStoreFileTests.swift
git commit -m "feat: persist a configuration file that can hold a scheduled change"
```

---

### Task 5: The shield reads what is in force

**Files:**
- Modify: `Sources/Shared/ShieldStateReader.swift`
- Test: `Tests/SharedTests/ShieldStateReaderTests.swift:1-120` (extend)

**Interfaces:**
- Consumes: `ConfigurationStore.loadFileWithoutLocking()` from Task 4, `LogicalDay` from Task 1.
- Produces: unchanged public signature — `ShieldStateReader.presentation(for:now:calendar:)`.

- [ ] **Step 1: Write the failing test**

Add to `ShieldStateReaderTests`, and add `import` lines for anything not already imported:

```swift
    func testThePendingConfigurationAppliesOnceItsStartDayArrives() throws {
        let now = date(year: 2026, month: 8, day: 21, hour: 9)
        let ruleID = UUID()
        let token = try token(seed: "instagram")
        let directoryURL = try temporaryDirectory()

        let effective = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: 2, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: token, launchRoute: nil)]
        )
        let scheduled = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: 6, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: token, launchRoute: nil)]
        )
        try AtomicJSONFile<ConfigurationFile>(
            url: directoryURL.appendingPathComponent(SharedIdentifiers.configurationFilename)
        ).save(
            ConfigurationFile(
                effective: effective,
                pending: PendingConfiguration(
                    document: scheduled,
                    startDay: LogicalDay.containing(now, calendar: calendar)
                )
            )
        )
        try AtomicJSONFile<RuleRuntime>(
            url: directoryURL.appendingPathComponent("runtime-\(ruleID.uuidString.lowercased()).json")
        ).save(
            RuleRuntime(
                logicalDay: LogicalDay.containing(now, calendar: calendar),
                sessionsStarted: 1,
                openSession: nil
            )
        )

        let presentation = try ShieldStateReader(directoryURL: directoryURL)
            .presentation(for: token, now: now, calendar: calendar)

        XCTAssertEqual(presentation.subtitle, "5 sessions left today")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command. Expected: FAIL — the reader still reads `effective`, so the subtitle is `"1 session left today"`.

- [ ] **Step 3: Write the implementation**

In `ShieldStateReader.presentation(for:now:calendar:)`, replace the configuration load:

```swift
        guard let file = try configurationStore.loadFileWithoutLocking() else {
            throw RuleLookupError.targetNotFound
        }
        let configuration = file.inForce(on: LogicalDay.containing(now, calendar: calendar))
```

Leave the rest of the method as it is. Add `import PauseCore` if it is not already present.

- [ ] **Step 4: Run the tests**

Run the test command. Expected: PASS, including the existing lock-file assertion — the file read still takes no lock.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/ShieldStateReader.swift Tests/SharedTests/ShieldStateReaderTests.swift
git commit -m "feat: show the shield the rules in force today"
```

---

### Task 6: The shield's tap grants against what is in force

**Files:**
- Modify: `Sources/ShieldActionExtension/ShieldActionExtension.swift:20-32`

**Interfaces:**
- Consumes: `ConfigurationStore.loadFile()` from Task 4, `LogicalDay` from Task 1.

This extension runs under the `plugin` sandbox profile and may take the lock, so it keeps `loadFile()` rather than the lock-free read. It is not in a test target; its behaviour is covered by `ConfigurationFile` and `RuleLookup` tests, and by the acceptance matrix on device.

- [ ] **Step 1: Change the configuration load**

Inside the `stateLock.withLock` block, replace:

```swift
                guard let configuration = try ConfigurationStore(directoryURL: directoryURL).load() else {
                    return false
                }
```

with:

```swift
                guard let file = try ConfigurationStore(directoryURL: directoryURL).loadFileUnlockedForCaller() else {
                    return false
                }
                let configuration = file.inForce(on: LogicalDay.containing(now))
```

This needs a lock-free read from inside a held lock, because `withLock` is re-entrant but the read must not re-enter for its own reasons. Add to `ConfigurationStore`:

```swift
    /// Reads for a caller that already holds the state lock.
    public func loadFileUnlockedForCaller() throws -> ConfigurationFile? {
        try loadFileWithoutLocking()
    }
```

- [ ] **Step 2: Build the extension**

```bash
xcodegen generate
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the tests**

Run the test command. Expected: PASS, unchanged count.

- [ ] **Step 4: Commit**

```bash
git add Sources/ShieldActionExtension/ShieldActionExtension.swift Sources/Shared/ConfigurationStore.swift
git commit -m "feat: grant a session against the rules in force today"
```

---

### Task 7: The reconcilers work from what is in force

**Files:**
- Modify: `Sources/Shared/SessionReconciliationService.swift:6,33`
- Modify: `Sources/Pause/AppModel.swift` — every `configurationStore.load()` call site
- Test: `Tests/SharedTests/SessionReconciliationServiceTests.swift` (extend)

**Interfaces:**
- Consumes: `ConfigurationStore.loadFile()`, `ConfigurationFile.inForce(on:)`, `LogicalDay`.

`ShieldReconciler` takes a `ConfigurationDocument` as a parameter rather than loading one, so it needs no change — its callers must pass the in-force document, which is what this task does.

- [ ] **Step 1: Write the failing test**

```swift
    func testReconciliationUsesThePendingConfigurationOnceItsStartDayArrives() throws {
        // Build a store whose pending document removes the only rule, with a
        // start day of today, then reconcile and assert the shield set is empty.
        // Follow the arrangement already used by the tests in this file for
        // constructing a service over a temporary directory.
    }
```

Write this test concretely by copying the arrangement from the nearest existing test in that file — the point is that a reconcile run on or after the start day applies the pending document.

- [ ] **Step 2: Run the test to verify it fails**

Run the test command. Expected: FAIL — reconciliation still reads `effective`.

- [ ] **Step 3: Write the implementation**

In `SessionReconciliationService`, wherever the configuration is loaded, load the file and select:

```swift
        guard let file = try configurationStore.loadFile() else { return }
        let configuration = file.inForce(on: LogicalDay.containing(now))
```

In `AppModel`, replace every `try configurationStore.load()` with the file equivalent, holding the loaded `ConfigurationFile` in a new private property `configurationFile` and deriving `configuration` from it:

```swift
    private var configurationFile: ConfigurationFile?

    private func loadInForceConfiguration(now: Date = Date()) throws -> ConfigurationDocument {
        guard let file = try configurationStore?.loadFile() else {
            throw AppModelError.storageUnavailable
        }
        configurationFile = file
        return file.inForce(on: LogicalDay.containing(now))
    }
```

Assign `configuration` from `loadInForceConfiguration()` at initialisation and wherever it is reloaded. The published `configuration` property is what the screens render, so this is the single point that makes them show what applies today.

- [ ] **Step 4: Run the tests**

Run the test command. Expected: PASS across all suites, including `PauseAppTests`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/SessionReconciliationService.swift Sources/Pause/AppModel.swift Tests/SharedTests/SessionReconciliationServiceTests.swift
git commit -m "feat: reconcile against the rules in force today"
```

---

### Task 8: Routing an edit to now or to tomorrow

**Files:**
- Create: `Sources/Shared/ConfigurationSaveRouter.swift`
- Test: `Tests/SharedTests/ConfigurationSaveRouterTests.swift`

**Interfaces:**
- Consumes: `ConfigurationFile`, `ConfigurationComparison`, `LogicalDay`.
- Produces: `ConfigurationSaveRouter.route(candidate: ConfigurationDocument, into existing: ConfigurationFile, now: Date, calendar: Calendar) -> ConfigurationFile`

Keeping the decision in a pure function means the routing is tested without a store, a lock, or a device.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import ManagedSettings
import PauseCore
import XCTest

final class ConfigurationSaveRouterTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let ruleID = UUID()

    func testATighteningEditAppliesImmediately() throws {
        let existing = ConfigurationFile(effective: try document(sessionsPerDay: 5), pending: nil)
        let candidate = try document(sessionsPerDay: 3)

        let result = ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.effective, candidate)
        XCTAssertNil(result.pending)
    }

    func testALooseningEditIsScheduledForTheNextLogicalDay() throws {
        let existing = ConfigurationFile(effective: try document(sessionsPerDay: 3), pending: nil)
        let candidate = try document(sessionsPerDay: 5)

        let result = ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.effective, existing.effective)
        XCTAssertEqual(result.pending?.document, candidate)
        XCTAssertEqual(result.pending?.startDay, LogicalDay.next(after: now(), calendar: calendar))
    }

    func testATighteningEditClearsAScheduledChange() throws {
        let existing = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(
                document: try document(sessionsPerDay: 5),
                startDay: LogicalDay.next(after: now(), calendar: calendar)
            )
        )
        let candidate = try document(sessionsPerDay: 2)

        let result = ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.effective, candidate)
        XCTAssertNil(result.pending)
    }

    func testASecondLooseningEditReplacesTheFirstRatherThanQueueing() throws {
        let existing = ConfigurationFile(
            effective: try document(sessionsPerDay: 3),
            pending: PendingConfiguration(
                document: try document(sessionsPerDay: 5),
                startDay: LogicalDay.next(after: now(), calendar: calendar)
            )
        )
        let candidate = try document(sessionsPerDay: 8)

        let result = ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.pending?.document, candidate)
        XCTAssertEqual(result.effective, existing.effective)
    }

    // MARK: - Helpers

    private func now() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 9))!
    }

    private func document(sessionsPerDay: Int) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: sessionsPerDay, sessionLengthMinutes: 5)],
            targets: [RuleTarget(ruleID: ruleID, applicationToken: try token(seed: "a"), launchRoute: nil)]
        )
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command. Expected: compile failure, `cannot find 'ConfigurationSaveRouter' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import PauseCore

/// Decides whether a saved edit takes effect now or at the next reset.
public enum ConfigurationSaveRouter {
    public static func route(
        candidate: ConfigurationDocument,
        into existing: ConfigurationFile,
        now: Date,
        calendar: Calendar = .current
    ) -> ConfigurationFile {
        let inForce = existing.inForce(on: LogicalDay.containing(now, calendar: calendar))
        guard ConfigurationComparison.isLoosening(from: inForce, to: candidate) else {
            // Tightening always wins, so a scheduled loosening cannot survive a
            // later decision to be stricter.
            return ConfigurationFile(effective: candidate, pending: nil)
        }
        return ConfigurationFile(
            effective: inForce,
            pending: PendingConfiguration(
                document: candidate,
                startDay: LogicalDay.next(after: now, calendar: calendar)
            )
        )
    }
}
```

Note `effective: inForce` rather than `existing.effective`: once a pending change has started, it is what applies, so scheduling a further change must not resurrect the document it superseded.

- [ ] **Step 4: Run the tests**

Run the test command. Expected: PASS, all four cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/ConfigurationSaveRouter.swift Tests/SharedTests/ConfigurationSaveRouterTests.swift
git commit -m "feat: send a loosening edit to the next reset"
```

---

### Task 9: The app saves through the router, and can cancel

**Files:**
- Modify: `Sources/Pause/AppModel.swift:496,528,580` — the three save paths
- Test: `Tests/PauseAppTests/AppModelFlowTests.swift` (extend)

**Interfaces:**
- Consumes: `ConfigurationSaveRouter.route(candidate:into:now:calendar:)`.
- Produces: `AppModel.pendingChangeStartDay: CalendarDay?` (published), `AppModel.cancelScheduledChange()`.

- [ ] **Step 1: Write the failing test**

```swift
    func testRaisingAnAllowanceLeavesTodaysRuleInPlace() throws {
        // Arrange an AppModel over a temporary directory with one rule at 3
        // sessions, following the arrangement used by the existing tests in
        // this file. Save an edit raising it to 5.
        // Assert: model.configuration.rules[0].sessionsPerDay == 3
        //         model.pendingChangeStartDay != nil
    }

    func testLoweringAnAllowanceAppliesAtOnceAndClearsASchedule() throws {
        // Arrange as above, save a raise to 5, then save a lower to 2.
        // Assert: model.configuration.rules[0].sessionsPerDay == 2
        //         model.pendingChangeStartDay == nil
    }

    func testCancellingAScheduledChangeLeavesTodaysRuleInForce() throws {
        // Arrange as above, save a raise to 5, then call cancelScheduledChange().
        // Assert: model.configuration.rules[0].sessionsPerDay == 3
        //         model.pendingChangeStartDay == nil
    }
```

Write each of these concretely using the `AppModel` construction already used in this file — the assertions above are the contract.

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command. Expected: FAIL — `pendingChangeStartDay` does not exist, and a raise currently applies at once.

- [ ] **Step 3: Write the implementation**

Add to `AppModel`:

```swift
    @Published private(set) var pendingChangeStartDay: CalendarDay?

    /// Writes an edited document through the router, so a loosening edit is
    /// scheduled rather than applied.
    private func persist(_ candidate: ConfigurationDocument, now: Date = Date()) throws {
        guard let configurationStore else { throw AppModelError.storageUnavailable }
        let existing = try configurationStore.loadFile()
            ?? ConfigurationFile(effective: candidate, pending: nil)
        let routed = ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now
        )
        try configurationStore.save(file: routed)
        configurationFile = routed
        configuration = routed.inForce(on: LogicalDay.containing(now))
        pendingChangeStartDay = routed.pending?.startDay
    }

    func cancelScheduledChange(now: Date = Date()) {
        guard let configurationStore, let file = configurationFile, file.pending != nil else { return }
        // Cancelling a loosening leaves the stricter rule standing, which is a
        // tightening, so it applies at once.
        let kept = file.inForce(on: LogicalDay.containing(now))
        do {
            let cleared = ConfigurationFile(effective: kept, pending: nil)
            try configurationStore.save(file: cleared)
            configurationFile = cleared
            configuration = kept
            pendingChangeStartDay = nil
        } catch {
            presentedError = AppError(title: "Couldn't cancel the change", error: error)
        }
    }
```

Route the three existing save paths through `persist(_:)` in place of their direct `configurationStore.save(_:)` calls. Set `pendingChangeStartDay` from the loaded file at initialisation too, so a scheduled change survives a relaunch on screen.

- [ ] **Step 4: Run the tests**

Run the test command. Expected: PASS across all suites.

- [ ] **Step 5: Commit**

```bash
git add Sources/Pause/AppModel.swift Tests/PauseAppTests/AppModelFlowTests.swift
git commit -m "feat: schedule a loosening edit and allow cancelling it"
```

---

### Task 10: A deferred removal keeps its session data

**Files:**
- Modify: `Sources/Pause/AppModel.swift:560-590` — the removal path
- Test: `Tests/PauseAppTests/AppModelFlowTests.swift` (extend)

**Interfaces:**
- Consumes: `ConfigurationSaveRouter`, `ConfigurationComparison`.

Removing an app is always a loosening, so it always defers. `RuleRemovalCoordinator` stages and deletes the rule's runtime file, which must not happen while the rule is still in force — an app that is shielded with no session data resolves as damage. A deferred removal writes only the pending document.

- [ ] **Step 1: Write the failing test**

```swift
    func testRemovingAnAppLeavesItsRuntimeUntilTheChangeTakesEffect() throws {
        // Arrange an AppModel over a temporary directory with one configured
        // rule and a runtime file present. Remove the app.
        // Assert: the runtime file still exists at
        //         directoryURL/runtime-<ruleID>.json
        //         model.configuration.targets is unchanged (still in force)
        //         model.pendingChangeStartDay != nil
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command. Expected: FAIL — the runtime file has been deleted.

- [ ] **Step 3: Write the implementation**

In the removal path, build the candidate document with the target and rule removed, then call `persist(_:)` and return. Do not call `ruleRemovalCoordinator.remove(...)`, do not stage or delete runtimes, do not unshield, and do not stop monitoring: the rule is still in force until the reset, so all of that state must stay. Task 11 does that work when the removal actually lands.

Keep `RuleRemovalCoordinator` and its tests. Task 11 calls it.

- [ ] **Step 4: Run the tests**

Run the test command. Expected: PASS. `RuleRemovalCoordinatorTests` should be untouched.

- [ ] **Step 5: Commit**

```bash
git add Sources/Pause/AppModel.swift Tests/PauseAppTests/AppModelFlowTests.swift
git commit -m "feat: keep a removed app's session data until the removal lands"
```

---

### Task 11: A callback at the reset

**Files:**
- Modify: `Sources/Shared/SessionMonitorCallbackHandler.swift:9-27`
- Modify: `Sources/MonitorExtension/MonitorExtension.swift:6`
- Create: `Sources/Shared/DailyResetScheduler.swift`
- Modify: `Sources/Pause/AppModel.swift` — register the daily activity on activation
- Test: `Tests/SharedTests/SessionMonitorCallbackHandlerTests.swift` (extend)

**Interfaces:**
- Produces: `DailyResetActivityName.value` (`"daily-reset"`), `DailyResetScheduler.register()`, `SessionMonitorCallbackHandler.intervalDidStart(activityName:now:)`.

- [ ] **Step 1: Write the failing test**

```swift
    func testAnActivityNameThatIsNotASessionStillReconciles() {
        var triggers: [SessionReconciliationTrigger] = []
        let handler = SessionMonitorCallbackHandler { trigger, _ in triggers.append(trigger) }

        handler.intervalDidStart(activityName: DailyResetActivityName.value, now: Date())

        XCTAssertEqual(triggers.count, 1)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command. Expected: compile failure, no `intervalDidStart` on the handler.

- [ ] **Step 3: Write the implementation**

Add to `Sources/Shared/SessionMonitorCallbackHandler.swift`:

```swift
public enum DailyResetActivityName {
    public static let value = "daily-reset"
}
```

and to `SessionMonitorCallbackHandler`:

```swift
    /// The daily reset carries no rule of its own. Every callback is a prompt to
    /// reconcile rather than proof that a particular boundary passed, so a name
    /// this type does not recognise reconciles rather than being discarded.
    public func intervalDidStart(activityName: String, now: Date) {
        reconcile(.appActivation, now)
    }
```

Use whichever `SessionReconciliationTrigger` case represents a full reconcile with no specific rule; if the existing enum has no such case, add one named `.dailyReset` and handle it in `SessionReconciliationService` exactly as an app activation is handled.

Create `Sources/Shared/DailyResetScheduler.swift`:

```swift
import DeviceActivity
import Foundation

/// Registers one repeating daily activity whose interval begins at the reset,
/// so the monitor gets a callback when a logical day turns over.
public struct DailyResetScheduler {
    private let startMonitoring: (DeviceActivityName, DeviceActivitySchedule) throws -> Void

    public init(center: DeviceActivityCenter = DeviceActivityCenter()) {
        startMonitoring = { name, schedule in
            try center.startMonitoring(name, during: schedule)
        }
    }

    init(startMonitoring: @escaping (DeviceActivityName, DeviceActivitySchedule) throws -> Void) {
        self.startMonitoring = startMonitoring
    }

    public func register() throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        try startMonitoring(DeviceActivityName(DailyResetActivityName.value), schedule)
    }
}
```

In `MonitorExtension`, implement the currently empty override:

```swift
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        handle(activityName: activity.rawValue, warning: false, didStart: true)
    }
```

and extend `handle` to call `runner.intervalDidStart(activityName:now:)` when `didStart` is true, adding that method to `SessionMonitorReconciliationRunner` alongside its existing two, following the same shape.

Register the activity from `AppModel` on activation, once authorization is granted, alongside the existing reconciliation. Registering repeatedly with the same name replaces the schedule rather than accumulating.

- [ ] **Step 4: Run the tests**

Run the test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/SessionMonitorCallbackHandler.swift Sources/Shared/DailyResetScheduler.swift Sources/MonitorExtension/MonitorExtension.swift Sources/Pause/AppModel.swift Tests/SharedTests/SessionMonitorCallbackHandlerTests.swift
git commit -m "feat: wake the monitor when a logical day begins"
```

---

### Task 12: The reset cleans up what a landed removal left behind

**Files:**
- Modify: `Sources/Shared/SessionReconciliationService.swift`
- Test: `Tests/SharedTests/SessionReconciliationServiceTests.swift` (extend)

**Interfaces:**
- Consumes: `ConfigurationFile.inForce(on:)`, `RuleRemovalCoordinator`.

Reconciliation already loads the in-force document (Task 7). It now also collapses a started pending document into `effective` and deletes runtime files for rules the in-force document no longer contains. Collapsing is what makes the cleanup safe: until it happens, the rule could still be resurrected by a cancel.

- [ ] **Step 1: Write the failing test**

```swift
    func testReconcilingAfterARemovalLandsDeletesItsRuntime() throws {
        // Arrange a store whose pending document removes the only rule, with a
        // start day of today, and whose runtime file exists.
        // Reconcile with now inside that day.
        // Assert: runtime-<ruleID>.json no longer exists
        //         the saved file's effective document has no target
        //         the saved file's pending is nil
    }

    func testReconcilingBeforeARemovalLandsKeepsItsRuntime() throws {
        // Same arrangement with a start day of tomorrow.
        // Assert: runtime-<ruleID>.json still exists and pending is unchanged.
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command. Expected: FAIL — the runtime file is still present after the removal lands.

- [ ] **Step 3: Write the implementation**

In the reconcile path, after computing the in-force document:

```swift
        let today = LogicalDay.containing(now)
        if let pending = file.pending, pending.startDay <= today {
            let removedRuleIDs = Set(file.effective.targets.map(\.ruleID))
                .subtracting(pending.document.targets.map(\.ruleID))
            try configurationStore.save(
                file: ConfigurationFile(effective: pending.document, pending: nil)
            )
            for ruleID in removedRuleIDs {
                try? runtimeRepository.delete(ruleID: ruleID)
                stopMonitoring([ruleID])
            }
        }
```

Then continue with the existing reconciliation, which applies the shield set from the in-force document and so releases the removed application.

- [ ] **Step 4: Run the tests**

Run the test command. Expected: PASS across all suites.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/SessionReconciliationService.swift Tests/SharedTests/SessionReconciliationServiceTests.swift
git commit -m "feat: finish a removal when it takes effect"
```

---

### Task 13: Showing a scheduled change

**Files:**
- Modify: `Sources/Pause/RulesView.swift`
- Modify: `Sources/Pause/RuleEditorView.swift`

**Interfaces:**
- Consumes: `AppModel.pendingChangeStartDay`, `AppModel.cancelScheduledChange()`.

The notice says a change is scheduled and when it takes effect. It does not restate what changed: the friction is the wait and the fact of having scheduled something, not a recitation of the fields.

- [ ] **Step 1: Add the notice to the rules list**

In `RulesView`, when `model.pendingChangeStartDay` is not nil, show a row above the list reading "A change to your rules starts tomorrow." with a "Cancel change" button calling `model.cancelScheduledChange()`. Render the day with `DateFormatter` in the device locale where the start day is not tomorrow, which happens if the app was not opened for a day.

- [ ] **Step 2: Add the confirmation to the editor**

In `RuleEditorView`, after a save that leaves `model.pendingChangeStartDay` non-nil, show the same sentence with the same cancel action, so the outcome is visible at the moment of saving rather than only on the list.

- [ ] **Step 3: Build and run the app**

```bash
xcodegen generate
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```
Expected: BUILD SUCCEEDED. Then run the tests; expected PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/Pause/RulesView.swift Sources/Pause/RuleEditorView.swift
git commit -m "feat: show that a change is waiting and offer to cancel it"
```

---

### Task 14: Remove the document-level store API

**Files:**
- Modify: `Sources/Shared/ConfigurationStore.swift`

**Interfaces:**
- Removes: `ConfigurationStore.load()`, `loadWithoutLocking()`, `save(_:)`.

- [ ] **Step 1: Confirm nothing calls them**

```bash
grep -rn "configurationStore.load()\|configurationStore.save(\|\.loadWithoutLocking()" Sources/ Tests/
```
Expected: no results outside `ConfigurationStore.swift` itself. If any remain, migrate them to the file API before continuing.

- [ ] **Step 2: Delete the three methods and the `legacyFile` property's document-level uses**

Keep `legacyFile` — the migration path still needs it.

- [ ] **Step 3: Build and test**

```bash
xcodegen generate
```
Then the test command and the generic device build. Expected: both succeed.

- [ ] **Step 4: Commit**

```bash
git add Sources/Shared/ConfigurationStore.swift
git commit -m "refactor: leave one way to read the configuration"
```

---

## Device verification

None of this is proven by the simulator. After Task 13, install a signed build and check on the phone:

- Raising an allowance leaves today's shield count unchanged, and the notice appears.
- Lowering an allowance changes the shield count at once and clears the notice.
- Cancelling a scheduled change clears the notice and leaves today's rule.
- Removing an app leaves it shielded and counting until the next day, then releases it without opening Pause.

The last one is the only row that needs a reset to pass through, so it needs an overnight wait or a deliberate device-clock change — noting that changing the clock is exactly the case the spec records as undefended, so it demonstrates the mechanism rather than the guarantee.
