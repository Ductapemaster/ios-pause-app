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
- Locate every edit by the symbol this plan names — a function, property, or type — never by line number. Each task shifts the lines under the ones after it.
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
- Consumes: `ConfigurationDocument`, and `CalendarDay`, which is already `Comparable` — the start-day comparison needs nothing new. This task stands on its own; no earlier task feeds it.
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

- [ ] **Step 4: Regenerate and run the tests**

```bash
xcodegen generate
```
Then the test command. Expected: PASS, all eleven cases.

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

The existing `load()`, `loadWithoutLocking()` and `save(_:)` stay and keep their `ConfigurationDocument` signatures for now; later tasks migrate their callers, and Task 14 removes them. `load()` returns the effective document during that window, which is unchanged behaviour while nothing writes a pending document yet.

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

    func testACorruptFileInTheCurrentShapeIsReportedAsCorrupt() throws {
        let directoryURL = try temporaryDirectory()
        let url = directoryURL.appendingPathComponent(SharedIdentifiers.configurationFilename)
        try Data(#"{"effective": {"rules": 7}}"#.utf8).write(to: url)

        XCTAssertThrowsError(try ConfigurationStore(directoryURL: directoryURL).loadFile()) { error in
            XCTAssertEqual(error as? PersistenceError, .corruptFile(url))
        }
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
        guard try carriesTheWrapper() else {
            guard let legacy = try legacyFile.load() else { return nil }
            try legacy.validate()
            return ConfigurationFile(effective: legacy, pending: nil)
        }
        guard let loaded = try file.load() else { return nil }
        try loaded.effective.validate()
        try loaded.pending?.document.validate()
        return loaded
    }

    /// Which of the two shapes the file holds. A build before deferred changes
    /// wrote a bare document, and this one writes a wrapper with an `effective`
    /// key, so no version field is needed.
    ///
    /// The choice is made on the key rather than on a failed decode. Falling
    /// back whenever the wrapper fails to decode would leave a damaged wrapper
    /// to be diagnosed by a legacy read of the same bytes, so what surfaces is
    /// whatever the older shape made of them. A file carrying `effective` is
    /// read as one, and its damage is reported as its own.
    private func carriesTheWrapper() throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.url.path) else { return false }
        let data = try Data(contentsOf: file.url)
        guard let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // Not a JSON object at all. Decoding the current shape reports it as
            // corrupt, which is what it is.
            return true
        }
        return fields.keys.contains("effective")
    }
}
```

Note the parameter label: `save(file:)` takes `file document:` because the stored property is already named `file`.

- [ ] **Step 4: Regenerate and run the tests**

```bash
xcodegen generate
```
Then the test command. Expected: PASS, including every existing `ConfigurationStore` test in `Tests/SharedTests/AtomicJSONFileTests.swift`, and `testFailedConfigurationCannotBePromotedByPickerSave` in `Tests/PauseAppTests/AppModelFlowTests.swift`, which requires a corrupt file to leave `configurationLoadState` at `.failed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/ConfigurationStore.swift Tests/SharedTests/ConfigurationStoreFileTests.swift
git commit -m "feat: persist a configuration file that can hold a scheduled change"
```

---

### Task 5: The shield reads what is in force

**Files:**
- Modify: `Sources/Shared/ShieldStateReader.swift`
- Test: `Tests/SharedTests/ShieldStateReaderTests.swift` (extend)

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
- Modify: `Sources/ShieldActionExtension/ShieldActionExtension.swift` — the `stateLock.withLock` block in `handle(action:for:completionHandler:)`

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
                guard let file = try ConfigurationStore(directoryURL: directoryURL).loadFile() else {
                    return false
                }
                let configuration = file.inForce(on: LogicalDay.containing(now))
```

`loadFile()` takes the state lock from inside the `withLock` block that already holds it. `AppGroupFileLock` is recursive — `AppGroupFileLockState.withLock` counts depth and takes `flock` once, at depth zero — so the nested acquisition costs a counter increment. `AppModel.commitRuleRemoval(...)` already nests a `ConfigurationStore` write the same way.

No new store method is needed.

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
git add Sources/ShieldActionExtension/ShieldActionExtension.swift
git commit -m "feat: grant a session against the rules in force today"
```

---

### Task 7: The reconcilers work from what is in force

**Files:**
- Modify: `Sources/Shared/SessionReconciliationService.swift` — the configuration loads in `reconcileUnlocked(now:trigger:)` and `resetRuntimeUnlocked(ruleID:now:calendar:)`
- Modify: `Sources/Pause/AppModel.swift` — every `configurationStore.load()` call site
- Test: `Tests/SharedTests/SessionReconciliationServiceTests.swift` (create)

**Interfaces:**
- Consumes: `ConfigurationStore.loadFile()`, `ConfigurationFile.inForce(on:)`, `LogicalDay`.
- Produces: the fixture for `SessionReconciliationService` over a temporary directory. Task 12 extends this file and inherits it, so the two tasks are coupled through it as well as through the service.

`ShieldReconciler` takes a `ConfigurationDocument` as a parameter rather than loading one, so it needs no change — its callers must pass the in-force document, which is what this task does.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import ManagedSettings
import PauseCore
import XCTest

@MainActor
final class SessionReconciliationServiceTests: XCTestCase {
    private let ruleID = UUID(uuidString: "6f1a0e1c-1f3e-4a2b-9c0d-2b7f5a8e4d31")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let calendar = Calendar.current

    func testReconciliationUsesThePendingConfigurationOnceItsStartDayArrives() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedRemovalPending(in: directory, startDay: LogicalDay.containing(now, calendar: calendar))
        var applied: Set<ApplicationToken>?

        _ = makeService(directory: directory, applyApplications: { applied = $0 })
            .reconcile(now: now, trigger: .appActivation)

        XCTAssertEqual(applied, [])
    }

    func testReconciliationKeepsTheEffectiveConfigurationBeforeTheStartDay() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedRemovalPending(in: directory, startDay: LogicalDay.next(after: now, calendar: calendar))
        var applied: Set<ApplicationToken>?

        _ = makeService(directory: directory, applyApplications: { applied = $0 })
            .reconcile(now: now, trigger: .appActivation)

        XCTAssertEqual(applied, [try token(seed: "instagram")])
    }

    // MARK: - Helpers

    /// One rule in force, and a pending document that removes it.
    private func seedRemovalPending(in directory: URL, startDay: CalendarDay) throws {
        let effective = try ConfigurationDocument(
            settings: .phaseOneDefault,
            rules: [AppRule(id: ruleID, sessionsPerDay: 3, sessionLengthMinutes: 5)],
            targets: [
                RuleTarget(
                    ruleID: ruleID,
                    applicationToken: try token(seed: "instagram"),
                    launchRoute: nil
                )
            ]
        )
        try ConfigurationStore(directoryURL: directory).save(
            file: ConfigurationFile(
                effective: effective,
                pending: PendingConfiguration(
                    document: try ConfigurationDocument(
                        settings: .phaseOneDefault,
                        rules: [],
                        targets: []
                    ),
                    startDay: startDay
                )
            )
        )
        try RuntimeRepository(directoryURL: directory).save(
            RuleRuntime(
                logicalDay: LogicalDay.containing(now, calendar: calendar),
                sessionsStarted: 0
            ),
            ruleID: ruleID
        )
    }

    /// The shield set is never written to disk and `ManagedSettingsStore` is out
    /// of reach in the simulator, so the injected apply closure is where a test
    /// reads what the reconcile decided.
    private func makeService(
        directory: URL,
        applyApplications: @escaping (Set<ApplicationToken>) -> Void
    ) -> SessionReconciliationService {
        SessionReconciliationService(
            directoryURL: directory,
            shieldReconciler: ShieldReconciler(
                currentApplications: { [] },
                applyApplications: applyApplications,
                failedGrantBlockIDs: { [] },
                stateLock: AppGroupFileLock(directoryURL: directory)
            ),
            stopMonitoring: { _ in }
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pause-reconciliation-service-tests-\(UUID().uuidString)", isDirectory: true)
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

`SessionReconciliationService.init(directoryURL:shieldReconciler:stopMonitoring:)` builds its store, repository and lock from the directory, so those are real files under a temporary directory; only the shield surface and the monitor stop are injected. `Tests/SharedTests/AppGroupFileLockTests.swift` uses the same arrangement. `SessionReconciliationCoordinatorTests` is no template — it drives the pure coordinator through injected closures and touches no disk. Task 12 extends this file and works in the fixture built here.

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

/// Decides whether a saved edit takes effect now or at the next reset. public enum ConfigurationSaveRouter {
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

- [ ] **Step 4: Regenerate and run the tests**

```bash
xcodegen generate
```
Then the test command. Expected: PASS, all four cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/ConfigurationSaveRouter.swift Tests/SharedTests/ConfigurationSaveRouterTests.swift
git commit -m "feat: send a loosening edit to the next reset"
```

---

### Task 9: The app saves through the router, and can cancel

**Files:**
- Modify: `Sources/Pause/AppModel.swift` — the four save paths
- Test: `Tests/PauseAppTests/AppModelFlowTests.swift` (extend)

**Interfaces:**
- Consumes: `ConfigurationSaveRouter.route(candidate:into:now:calendar:)`.
- Produces: `AppModel.pendingChangeStartDay: CalendarDay?` (published), `AppModel.cancelScheduledChange(now:)`, `AppModel.persist(_:now:)` — the one place a configuration reaches the store — and a `now: Date = Date()` parameter on all four public write methods.

`AppModel` writes configuration from four methods, and every one of them routes through `persist(_:now:)`:

- `applyPickerSelection(now:)` — the picker save. It has two exits: it writes directly when `removedRuleIDs` is empty, and goes through `commitRuleRemoval(...)` when it is not, so routing it means changing both.
- `updateRule(id:sessionsPerDay:sessionLengthMinutes:now:)` — the rule editor save.
- `updatePauseSeconds(_:now:)` — the countdown setting.
- `commitRuleRemoval(ruleIDs:nextConfiguration:configurationStore:runtimeRepository:now:)` — rule removal, reached from both `removeRule(id:now:)` and a picker save that drops an app. Its write sits inside `stateLock.withLock` alongside staged runtime removals. Task 10 changes what this path does.

`updatePauseSeconds(_:now:)` is the only path that can change `settings.pauseSeconds`, which is the field `ConfigurationComparison` treats as loosening when it falls. Left writing directly to the store, shortening the countdown would bypass the feature entirely.

The `now` parameters are what make a deferral testable. Every assertion here turns on the start day `LogicalDay.next(after:)` computes, and a save made at 23:59:59 lands on a different day from the one the test named. They also replace the two `Date()` calls these paths make internally: the logical day stamped on a new rule's runtime in `applyPickerSelection(now:)`, and the `restoreShields` reconcile inside `commitRuleRemoval(...)`. `sceneDidBecomeActive(now:)`, `requestSessionGrant(now:)` and `resetRuntime(ruleID:now:)` already take the clock this way, so no SwiftUI call site changes and no existing test moves.

- [ ] **Step 1: Write the failing test**

```swift
    func testRaisingAnAllowanceLeavesTodaysRuleInPlace() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updateRule(
            id: ruleID,
            sessionsPerDay: 5,
            sessionLengthMinutes: 5,
            now: now
        )

        XCTAssertEqual(model.configuration.rules[0].sessionsPerDay, 3)
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now))
    }

    func testLoweringAnAllowanceAppliesAtOnceAndClearsASchedule() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updateRule(id: ruleID, sessionsPerDay: 5, sessionLengthMinutes: 5, now: now)
        try model.updateRule(id: ruleID, sessionsPerDay: 2, sessionLengthMinutes: 5, now: now)

        XCTAssertEqual(model.configuration.rules[0].sessionsPerDay, 2)
        XCTAssertNil(model.pendingChangeStartDay)
    }

    func testCancellingAScheduledChangeLeavesTodaysRuleInForce() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updateRule(id: ruleID, sessionsPerDay: 5, sessionLengthMinutes: 5, now: now)
        model.cancelScheduledChange(now: now)

        XCTAssertEqual(model.configuration.rules[0].sessionsPerDay, 3)
        XCTAssertNil(model.pendingChangeStartDay)
        XCTAssertEqual(
            try ConfigurationStore(directoryURL: directory).loadFile()?.pending,
            nil
        )
    }

    func testShorteningThePauseWaitsWhileLengtheningItAppliesAtOnce() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )

        try model.updatePauseSeconds(5, now: now)

        XCTAssertEqual(model.configuration.settings.pauseSeconds, 10)
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now))

        try model.updatePauseSeconds(20, now: now)

        XCTAssertEqual(model.configuration.settings.pauseSeconds, 20)
        XCTAssertNil(model.pendingChangeStartDay)
    }
```

These need two stored properties and one helper on `AppModelFlowTests`, plus `import ManagedSettings` for `ApplicationToken`. The runtime file goes down with the rule so the shield reconcile that follows each save has something to read:

```swift
    private let ruleID = UUID(uuidString: "3f7c1d20-6b8a-4f19-8e42-0a5c9d1b7e63")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func seedOneRule(in directory: URL, sessionsPerDay: Int) throws {
        try ConfigurationStore(directoryURL: directory).save(
            ConfigurationDocument(
                settings: .phaseOneDefault,
                rules: [
                    AppRule(
                        id: ruleID,
                        sessionsPerDay: sessionsPerDay,
                        sessionLengthMinutes: 5
                    )
                ],
                targets: [
                    RuleTarget(
                        ruleID: ruleID,
                        applicationToken: try token(seed: "instagram"),
                        launchRoute: nil
                    )
                ]
            )
        )
        try RuntimeRepository(directoryURL: directory).save(
            RuleRuntime(logicalDay: LogicalDay.containing(now), sessionsStarted: 0),
            ruleID: ruleID
        )
    }

    private func token(seed: String) throws -> ApplicationToken {
        let data = Data(seed.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            ApplicationToken.self,
            from: Data("{\"data\":\"\(data)\"}".utf8)
        )
    }
```

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

Give each of the four write paths a `now: Date = Date()` parameter and thread it into `persist(_:now:)`, replacing their direct `configurationStore.save(_:)` calls: `applyPickerSelection(now:)` on both its exits, `updateRule(id:sessionsPerDay:sessionLengthMinutes:now:)`, `updatePauseSeconds(_:now:)`, and the `commitConfiguration` closure that `commitRuleRemoval(ruleIDs:nextConfiguration:configurationStore:runtimeRepository:now:)` hands `RuleRemovalCoordinator`. The same `now` replaces the `Date()` those paths call internally.

Set `pendingChangeStartDay` from the loaded file at initialisation too, so a scheduled change survives a relaunch on screen.

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
- Modify: `Sources/Pause/AppModel.swift` — `removeRule(id:now:)`, and the removal branch of `applyPickerSelection(now:)`
- Test: `Tests/PauseAppTests/AppModelFlowTests.swift` (extend)

**Interfaces:**
- Consumes: `ConfigurationSaveRouter`, `ConfigurationComparison`.

Removing an app is always a loosening, so it always defers. `RuleRemovalCoordinator` stages and deletes the rule's runtime file, which must not happen while the rule is still in force — an app that is shielded with no session data resolves as damage. A deferred removal writes only the pending document.

- [ ] **Step 1: Write the failing test**

```swift
    func testRemovingAnAppLeavesItsRuntimeUntilTheChangeTakesEffect() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let runtimeURL = directory.appendingPathComponent(
            "runtime-\(ruleID.uuidString.lowercased()).json"
        )
        let probe = FlowProbe(status: .approved)
        let model = makeModel(directory: directory, probe: probe, hasProtectedState: false)

        try model.removeRule(id: ruleID, now: now)

        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeURL.path))
        XCTAssertEqual(model.configuration.targets.count, 1)
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now))
        XCTAssertEqual(probe.cleanupCount, 0)
        XCTAssertEqual(probe.reconciliationCount, 0)
    }
```

The runtime file is the assertion that matters: `RuleRemovalCoordinator` stages and deletes it, so its presence is what says the coordinator never ran. `seedOneRule(in:sessionsPerDay:)` is the helper Task 9 adds.

- [ ] **Step 2: Run the test to verify it fails**

Run the test command. Expected: FAIL — the runtime file has been deleted.

- [ ] **Step 3: Write the implementation**

In both removal paths, build the candidate document with the target and rule removed, then call `persist(_:now:)` and return. Do not call `ruleRemovalCoordinator.remove(...)`, do not stage or delete runtimes, do not unshield, and do not stop monitoring: the rule is still in force until the reset, so all of that state must stay. The picker selection follows the in-force document, which still names the app, so the app stays selected too — Task 13 makes that the rule for every path.

The reset reconciliation releases the application once the removal is in force (Task 12), and the orphan cleanup that already runs on app activation deletes the runtime file the next time Pause opens.

Both paths now bypass `commitRuleRemoval(...)`, which leaves `RuleRemovalCoordinator` and the staged-removal methods on `RuntimeRepository` with no caller. They and their tests stay in the tree; retiring them is a decision separate from this build.

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
- Modify: `Sources/Shared/SessionMonitorCallbackHandler.swift` — `SessionMonitorCallbackHandler`, alongside `intervalDidEnd(activityName:now:)` and `intervalWillEndWarning(activityName:now:)`, and `SessionMonitorReconciliationRunner.handle(activityName:now:warning:)`
- Modify: `Sources/MonitorExtension/MonitorExtension.swift` — the empty `intervalDidStart(for:)` override, and `handle(activityName:warning:)`
- Modify: `Sources/Shared/SessionReconciliationCoordinator.swift` — `SessionReconciliationTrigger`
- Create: `Sources/Shared/DailyResetScheduler.swift`
- Modify: `Sources/Pause/AppModel.swift` — register the daily activity on activation
- Test: `Tests/SharedTests/SessionMonitorCallbackHandlerTests.swift` (extend)

**Interfaces:**
- Produces: `DailyResetActivityName.value` (`"daily-reset"`), `DailyResetScheduler.register()`, `SessionMonitorCallbackHandler.intervalDidStart(activityName:now:)`, `SessionReconciliationTrigger.dailyReset`.

A session grant registers a schedule whose interval already contains the moment of registration, and a schedule that is already under way fires `intervalDidStart` immediately — measured on device, recorded in `docs/research/screen-time-platform-evidence.md`. So this callback arrives on every grant as well as at the reset, and the handler has to tell them apart by name.

- [ ] **Step 1: Write the failing test**

```swift
    func testTheDailyResetReconciles() {
        var received: SessionReconciliationTrigger?
        let handler = SessionMonitorCallbackHandler { trigger, _ in received = trigger }

        handler.intervalDidStart(activityName: DailyResetActivityName.value, now: now)

        XCTAssertEqual(received, .dailyReset)
    }

    func testASessionIntervalStartingDoesNotReconcile() {
        var count = 0
        let handler = SessionMonitorCallbackHandler { _, _ in count += 1 }

        handler.intervalDidStart(
            activityName: SessionActivityName.sessionActivityName(for: ruleID),
            now: now
        )

        XCTAssertEqual(count, 0)
    }
```

`ruleID` and `now` are the stored properties `SessionMonitorCallbackHandlerTests` already declares.

- [ ] **Step 2: Run the test to verify it fails**

Run the test command. Expected: compile failure, no `intervalDidStart` on the handler.

- [ ] **Step 3: Write the implementation**

Add to `Sources/Shared/SessionMonitorCallbackHandler.swift`:

```swift
public enum DailyResetActivityName {
    public static let value = "daily-reset"
}
```

and to `SessionMonitorCallbackHandler`, guarding on the name exactly as `intervalDidEnd` and `intervalWillEndWarning` do:

```swift
    /// Only the daily reset is acted on here. A session's own interval begins at
    /// the instant it is granted, so this callback also arrives immediately on
    /// every grant, carrying that session's name — which makes the name, not the
    /// arrival, the thing worth reading.
    public func intervalDidStart(activityName: String, now: Date) {
        guard SessionActivityName.ruleID(fromSessionActivityName: activityName) == nil else {
            return
        }
        reconcile(.dailyReset, now)
    }
```

Add the case to `SessionReconciliationTrigger`, with `selectedRuleID` returning `nil`:

```swift
    case dailyReset
```

`.dailyReset` rather than `.appActivation`, for two reasons. `.appActivation` is the only trigger that promotes a provisional session to active, and a provisional session means the launch handoff has not been confirmed — a reset pass reusing it would spend a session on a launch that may never have happened. And device state is legible only through `sysdiagnose` and the unified log, so a trigger that says "app activated" when the reset fired corrupts the one debugging signal there is.

`SessionReconciliationTrigger` lives in `Sources/Shared`, so adding a case is a four-target change: the exhaustive switch in `selectedRuleID` stops compiling until the case is handled, and every other switch over the trigger needs checking.

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

This schedule repeats and spans 00:00 to 23:59, so it too is already under way whenever it is registered, and registering it fires `intervalDidStart` at once. Two things follow: the reset reconciliation runs on ordinary app activations as well as at midnight, so it has to be idempotent, and the callback is not evidence that a logical day turned over. Nothing here treats it as evidence — it reconciles against whatever `inForce(on:)` returns for the moment it runs, which is correct on both.

- [ ] **Step 4: Run the tests**

Run the test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/SessionMonitorCallbackHandler.swift Sources/Shared/SessionReconciliationCoordinator.swift Sources/Shared/DailyResetScheduler.swift Sources/MonitorExtension/MonitorExtension.swift Sources/Pause/AppModel.swift Tests/SharedTests/SessionMonitorCallbackHandlerTests.swift
git commit -m "feat: wake the monitor when a logical day begins"
```

---

### Task 12: The reset releases what a landed removal no longer covers

**Files:**
- Modify: `Sources/Shared/SessionReconciliationCoordinator.swift` — the `shouldApplyShields` decision
- Test: `Tests/SharedTests/SessionReconciliationServiceTests.swift` (extend — Task 7 creates it)

**Interfaces:**
- Consumes: `SessionReconciliationTrigger.dailyReset` from Task 11, and the temporary-directory fixture Task 7 builds in the test file this task extends.

A reconcile pass applies the shield set only when `shouldApplyShields` holds: the trigger is `.appActivation`, or a per-rule callback found something it could stop, or the pass raised an issue. A reset that lands a removal satisfies none of them. The rules the pass iterates come from the in-force document, so when the removal takes the last rule with it there is nothing to iterate, `selectedCallbackCanStop` stays false, and the shield set is never written — leaving the released application shielded until Pause is next opened.

Adding `.dailyReset` to that condition is the whole change: the reset is a whole-configuration pass like an activation, not a callback about one rule.

The reset writes nothing. A pending document that has started is folded into `effective` by `ConfigurationSaveRouter` on the next save, because the router routes against `inForce(on:)` rather than against `effective`; until then `inForce(on:)` keeps returning it. Leaving the file alone is what lets every reader stay read-only, and it keeps the monitor extension off a write path nothing has established it can take.

The removed rule's runtime file is deleted by the orphan cleanup that already runs on app activation — `AppModel.cleanupOrphanedRuntimes()` keeps only the rules the in-force document names. A runtime left behind in the meantime changes nothing: `ShieldReconciler` builds the shield set from `configuration.targets`, so a runtime with no target is never read. Its session activity is a one-shot schedule that ends itself.

- [ ] **Step 1: Write the failing test**

```swift
    func testTheResetReleasesAnApplicationWhoseRemovalHasLanded() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedRemovalPending(in: directory, startDay: LogicalDay.containing(now, calendar: calendar))
        var applied: Set<ApplicationToken>?

        _ = makeService(directory: directory, applyApplications: { applied = $0 })
            .reconcile(now: now, trigger: .dailyReset)

        XCTAssertEqual(applied, [])
    }

    func testTheResetKeepsShieldingAnApplicationWhoseRemovalHasNotLanded() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedRemovalPending(in: directory, startDay: LogicalDay.next(after: now, calendar: calendar))
        var applied: Set<ApplicationToken>?

        _ = makeService(directory: directory, applyApplications: { applied = $0 })
            .reconcile(now: now, trigger: .dailyReset)

        XCTAssertEqual(applied, [try token(seed: "instagram")])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command. Expected: the first FAILS — `applied` is `nil`, because no shield set was written. The second passes already: the rule is still in force, its runtime holds no open session, and that is enough to reach the apply.

- [ ] **Step 3: Write the implementation**

In `SessionReconciliationCoordinator.reconcile(...)`, include the reset in the decision:

```swift
        let shouldApplyShields = trigger == .appActivation
            || trigger == .dailyReset
            || selectedCallbackCanStop
            || !result.issues.isEmpty
```

Nothing else changes. The existing reconciliation already builds the shield set from the in-force document, so the removed application is released the moment the apply runs.

- [ ] **Step 4: Run the tests**

Run the test command. Expected: PASS across all suites.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/SessionReconciliationCoordinator.swift Tests/SharedTests/SessionReconciliationServiceTests.swift
git commit -m "feat: release an app when its removal takes effect"
```

---

### Task 13: Showing a scheduled change

**Files:**
- Modify: `Sources/Pause/AppModel.swift` — the initializer's pending read, `sceneDidBecomeActive(now:)`, `applyPickerSelection(now:)`, `persist(_:now:)`
- Create: `Sources/Pause/ScheduledChangeNotice.swift`
- Modify: `Sources/Pause/RulesView.swift`
- Modify: `Sources/Pause/RuleEditorView.swift`
- Test: `Tests/PauseAppTests/AppModelFlowTests.swift` (extend)

**Interfaces:**
- Produces: `AppModel.ruleIDsPendingRemoval`, `ScheduledChangeNotice`, `ScheduledChangeWording.phrase(for:now:)`.
- Consumes: `AppModel.pendingChangeStartDay`, `AppModel.cancelScheduledChange()`, `ConfigurationFile.inForce(on:)`.

**Terms:** *in force* — the document `ConfigurationFile.inForce(on:)` returns for a given day, which is what every rule reader already works from. *Lands* — a scheduled change's start day arrives and it becomes the in-force document.

A scheduled change is invisible until something renders it, and for a removal the rendering is the app itself: an app that has vanished from the list has taken effect, whatever a notice says alongside it. So a removal takes no visible effect until it lands. The rule keeps its row in the rules list, rendered de-emphasised and labelled as removing at the next reset, with the action that cancels it; the app stays selected in the picker. Both readings are true — the app is still shielded and still counting sessions against the same allowance.

The notice says a change is scheduled and when it takes effect. It does not restate what changed: the friction is the wait and the fact of having scheduled something, not a recitation of the fields.

`.familyActivityPicker` is Apple's system UI. Nothing can be drawn as half-removed inside it — an app is selected there or it is not — so the pending-removal presentation lives only in Pause's own list, and the picker's whole part in this is keeping the app selected.

- [ ] **Step 1: Keep the picker selection on the in-force document**

The removal branch of `applyPickerSelection(now:)` returns before the selection is normalised, so an app dropped in the picker reads as deselected while its rule is still in force. Replace that early return and the trailing normalisation with one assignment built from `configuration.targets` — the document in force after the save — keeping the deferred path's skip of shield reconciliation:

```swift
        // The picker mirrors the document in force today rather than the raw
        // tap: an app whose removal is scheduled is still shielded, so it is
        // still selected.
        var inForceSelection = FamilyActivitySelection()
        inForceSelection.applicationTokens = Set(configuration.targets.map(\.applicationToken))
        pickerSelection = inForceSelection

        guard removedRuleIDs.isEmpty else {
            // Dropping an app always loosens the rules, so the edit is
            // scheduled for the next reset and only the pending document is
            // written. Every rule in the save is still in force until then, so
            // their runtimes, shields and monitoring stay as they are.
            return
        }
        reconcileShieldsIfAuthorized(title: "Apps updated, but shields need repair")
```

An edit that adds one app and drops another is a loosening taken whole, so it defers whole: the added app is not in force today either, and the selection says so by leaving it out until the change lands.

- [ ] **Step 2: Name the rules a scheduled change removes**

`RulesView` iterates the in-force document, so a rule pending removal is already in the list. What it needs is to know which rows those are:

```swift
    /// Rules the in-force document still covers that a scheduled change drops.
    var ruleIDsPendingRemoval: Set<UUID> {
        guard let pending = configurationFile?.pending else { return [] }
        let pendingRuleIDs = Set(pending.document.rules.map(\.id))
        return Set(configuration.rules.map(\.id)).subtracting(pendingRuleIDs)
    }
```

Once the change lands, `configuration` is the pending document, so this is empty and the marking stops without a flag to clear.

- [ ] **Step 3: Stop calling a landed change scheduled**

A pending document is selected at read time rather than promoted, so the file still names one after its start day has arrived. `pendingChangeStartDay` therefore has to mean *not arrived yet*, or the notice outlives the wait it describes:

```swift
    /// The start day of a change that has not arrived yet. A start day that has
    /// arrived is in force, not scheduled.
    private static func scheduledStartDay(in file: ConfigurationFile, now: Date) -> CalendarDay? {
        guard let startDay = file.pending?.startDay,
              startDay > LogicalDay.containing(now) else { return nil }
        return startDay
    }
```

Use it in the initializer and in `persist(_:now:)` in place of reading `pending?.startDay` directly.

- [ ] **Step 4: Re-select the in-force document on activation**

`configuration` is selected once, at init. Pause left open across a reset keeps yesterday's document, so a landed removal stays on screen and the orphan cleanup running in that same activation still sees the rule. Re-select first thing in `sceneDidBecomeActive(now:)`:

```swift
    /// Re-selects the document in force for the day Pause is being opened on, so
    /// a change that reached its start day while the app was away takes hold
    /// without a relaunch. The file in hand holds both documents, so this reads
    /// nothing from disk.
    private func refreshInForceConfiguration(now: Date) {
        guard let configurationFile else { return }
        configuration = configurationFile.inForce(on: LogicalDay.containing(now))
        pendingChangeStartDay = Self.scheduledStartDay(in: configurationFile, now: now)
        pickerSelection.applicationTokens = Set(configuration.targets.map(\.applicationToken))
    }
```

- [ ] **Step 5: The notice and its wording**

Create `Sources/Pause/ScheduledChangeNotice.swift`, holding the sentence, the cancel action, and the phrase both surfaces need:

```swift
/// When a scheduled change starts, in the words the two surfaces share.
enum ScheduledChangeWording {
    static func phrase(for day: CalendarDay, now: Date = Date()) -> String {
        if day == LogicalDay.next(after: now) { return "tomorrow" }
        guard let date = day.date(in: .current) else { return "at the next reset" }
        return "on \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
```

`CalendarDay` holds era, year, month and day, so the file also carries a small `date(in:)` extension that rebuilds a `Date` through `DateComponents`. The date branch covers Pause not being opened for a day, which leaves a start day that is neither tomorrow nor arrived; it formats through `Date.formatted`, so the device locale decides the order of the fields.

The notice itself is the sentence and the button:

```swift
struct ScheduledChangeNotice: View {
    @ObservedObject var model: AppModel
    let startDay: CalendarDay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A change to your rules starts \(ScheduledChangeWording.phrase(for: startDay)).")
            Button("Cancel change") { model.cancelScheduledChange() }
        }
    }
}
```

- [ ] **Step 6: The rules list**

In `RulesView`, show the notice in a section above the app list whenever `model.pendingChangeStartDay` is not nil.

Then split the `ForEach` body: a rule in `model.ruleIDsPendingRemoval` renders as a plain row instead of a `NavigationLink` — the app label, its allowance, "Removing tomorrow" in the shared wording, and a "Cancel removal" button calling `model.cancelScheduledChange()` — with the label and allowance de-emphasised so the row reads as on its way out. The row is deliberately not navigable: the editor saves a document built from the rules in force, which would write over the scheduled removal and quietly cancel it.

- [ ] **Step 7: The editor confirmation**

In `RuleEditorView`, show the same notice in a section at the top of the form whenever `model.pendingChangeStartDay` is not nil, and have `save()` dismiss only when the save applied at once. A deferred save leaves the editor standing with the notice under the title, so the outcome is visible at the moment of saving rather than only on the list.

`removeRule()` still dismisses: the rules list is where a pending removal shows itself.

- [ ] **Step 8: Write the model tests**

```swift
    func testDroppingAnAppFromThePickerKeepsItSelectedUntilTheRemovalLands() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        model.pickerSelection.applicationTokens = []

        try model.applyPickerSelection(now: now)

        XCTAssertEqual(model.pickerSelection.applicationTokens, [try token(seed: "instagram")])
        XCTAssertEqual(model.configuration.rules.map(\.id), [ruleID])
        XCTAssertEqual(model.ruleIDsPendingRemoval, [ruleID])
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now))
    }

    func testTheRemovalTakesTheAppAndItsSelectionWhenItLands() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        model.pickerSelection.applicationTokens = []
        try model.applyPickerSelection(now: now)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        model.sceneDidBecomeActive(now: tomorrow)

        XCTAssertTrue(model.configuration.rules.isEmpty)
        XCTAssertTrue(model.pickerSelection.applicationTokens.isEmpty)
        XCTAssertEqual(model.ruleIDsPendingRemoval, [])
        XCTAssertNil(model.pendingChangeStartDay)
    }
```

The second test drives the reset through activation because the initializer reads `Date()` and takes no injected clock, which leaves activation the only path a test can hand tomorrow to.

- [ ] **Step 9: Build, test, and run**

```bash
xcodegen generate
```

```bash
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

```bash
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Expected: both succeed, no failures. Then run the app in the simulator and look at the rules list with a removal scheduled.

- [ ] **Step 10: Commit**

```bash
git add Sources/Pause Tests/PauseAppTests/AppModelFlowTests.swift
```

```bash
git commit -m "feat: keep a removed app on screen until the removal lands"
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
- Removing an app leaves it listed, greyed and marked for tomorrow, still selected in the picker, and shielded and counting until the next day; it then releases without opening Pause, and the row is gone the next time Pause is opened.

The last one is the only row that needs a reset to pass through, so it needs an overnight wait or a deliberate device-clock change — noting that changing the clock is exactly the case the spec records as undefended, so it demonstrates the mechanism rather than the guarantee.
