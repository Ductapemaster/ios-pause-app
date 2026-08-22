# Per-app rule changes implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Judge a saved edit one app at a time, so an app added in the same picker trip that drops another is covered today, and a change scheduled for one app survives a save about a different one.

**Architecture:** `ConfigurationComparison` gains a per-unit loosening judgment and the document-level one becomes its disjunction. `ConfigurationSaveRouter.route` keeps its inputs and does the whole split internally, so no save path changes. `AppModel` learns whether a save deferred part of itself, which is what the rule editor's dismiss decision needs now that a tightening save can leave the pending slot occupied.

**Tech Stack:** Swift 6, XCTest, XcodeGen, iOS 26.5 deployment target.

**Spec:** `docs/design/per-app-rule-changes.md`

## Global Constraints

- Swift 6, `SWIFT_VERSION: "6.0"`; iOS deployment target 26.5.
- Regenerate the project with `xcodegen generate` after adding any file.
- Full suite: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`. It stood at 237 tests, 0 failures, before this plan; each task adds to that, so measure the baseline at the commit you start from rather than trusting this number.
- The unsigned device build must stay clean and warning-free: `xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`.
- No git remote is configured. Commit locally; never attempt a push.
- `ConfigurationDocument.init` is declared `throws` but never throws; `try` on it is syntax, not a failure path.
- Rule and target order is user-visible in the rules list. Every document this plan builds orders units by the in-force document's target order, then appends units only the candidate has.

---

### Task 1: A loosening judgment per unit

**Files:**
- Modify: `Sources/Shared/ConfigurationComparison.swift`
- Test: `Tests/SharedTests/ConfigurationComparisonTests.swift`

**Interfaces:**
- Consumes: `AppRule`, `RuleTarget`, `GlobalSettings`, `ConfigurationDocument` from `PauseCore` and `Sources/Shared`.
- Produces: `ConfigurationComparison.RuleUnit` (a `public struct` with `rule: AppRule` and `target: RuleTarget`, `Equatable`); `ConfigurationComparison.units(of:) -> [UUID: RuleUnit]`; `ConfigurationComparison.isLoosening(from: RuleUnit?, to: RuleUnit?) -> Bool`; `ConfigurationComparison.isLoosening(from: GlobalSettings, to: GlobalSettings) -> Bool`. Task 2 uses all four.

- [ ] **Step 1: Write the failing tests**

Append these to `ConfigurationComparisonTests.swift`, above the `// MARK: - Helpers` line. They use the existing `token(seed:)` and `ruleID` helpers already in that file.

```swift
    func testAUnitDroppingCoverageLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(from: try unit(), to: nil))
    }

    func testAUnitGainingCoverageDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(from: nil, to: try unit()))
    }

    func testAUnitAbsentThroughoutDoesNotLoosen() {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: nil as ConfigurationComparison.RuleUnit?,
            to: nil as ConfigurationComparison.RuleUnit?
        ))
    }

    func testAUnitRaisingItsAllowanceLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try unit(sessionsPerDay: 3),
            to: try unit(sessionsPerDay: 5)
        ))
    }

    func testAUnitLoweringItsAllowanceDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try unit(sessionsPerDay: 5),
            to: try unit(sessionsPerDay: 3)
        ))
    }

    func testAUnitLengtheningItsSessionLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try unit(sessionLengthMinutes: 5),
            to: try unit(sessionLengthMinutes: 10)
        ))
    }

    func testAUnitShorteningItsSessionDoesNotLoosen() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try unit(sessionLengthMinutes: 10),
            to: try unit(sessionLengthMinutes: 5)
        ))
    }

    func testAUnitRepointedAtAnotherApplicationLoosens() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try unit(seed: "instagram"),
            to: try unit(seed: "threads")
        ))
    }

    func testShorteningThePauseLoosensTheSettingsUnit() throws {
        XCTAssertTrue(ConfigurationComparison.isLoosening(
            from: try GlobalSettings(pauseSeconds: 10),
            to: try GlobalSettings(pauseSeconds: 5)
        ))
    }

    func testLengtheningThePauseDoesNotLoosenTheSettingsUnit() throws {
        XCTAssertFalse(ConfigurationComparison.isLoosening(
            from: try GlobalSettings(pauseSeconds: 5),
            to: try GlobalSettings(pauseSeconds: 10)
        ))
    }

    func testUnitsAreKeyedByRuleIdentity() throws {
        let units = ConfigurationComparison.units(of: try twoRuleDocument())

        XCTAssertEqual(Set(units.keys), [ruleID, otherRuleID])
        XCTAssertEqual(units[ruleID]?.rule.id, ruleID)
        XCTAssertEqual(units[ruleID]?.target.ruleID, ruleID)
    }
```

And add this helper immediately after the `// MARK: - Helpers` line:

```swift
    private func unit(
        sessionsPerDay: Int = 3,
        sessionLengthMinutes: Int = 5,
        seed: String = "instagram"
    ) throws -> ConfigurationComparison.RuleUnit {
        ConfigurationComparison.RuleUnit(
            rule: try AppRule(
                id: ruleID,
                sessionsPerDay: sessionsPerDay,
                sessionLengthMinutes: sessionLengthMinutes
            ),
            target: RuleTarget(
                ruleID: ruleID,
                applicationToken: try token(seed: seed),
                launchRoute: nil
            )
        )
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|\*\* TEST"`

Expected: compilation failure — `RuleUnit` and the two new `isLoosening` overloads do not exist.

- [ ] **Step 3: Write the implementation**

Replace the whole body of `Sources/Shared/ConfigurationComparison.swift` with:

```swift
import Foundation
import PauseCore

/// Judges whether one configuration permits more app use than another.
///
/// The judgment is per unit: one rule together with the target naming its app,
/// plus global settings as a unit of their own. A document is a loosening when
/// any of its units is, which is the question a reader of the whole document
/// asks; a save asks it one unit at a time instead, so that a decision about one
/// app does not hold up a decision about another.
public enum ConfigurationComparison {
    /// One rule and the target naming its app. Absent means the app is not
    /// covered: absent before is an app being added, absent after is one whose
    /// coverage is being dropped.
    public struct RuleUnit: Equatable {
        public var rule: AppRule
        public var target: RuleTarget

        public init(rule: AppRule, target: RuleTarget) {
            self.rule = rule
            self.target = target
        }
    }

    public static func units(of document: ConfigurationDocument) -> [UUID: RuleUnit] {
        let rulesByID = Dictionary(uniqueKeysWithValues: document.rules.map { ($0.id, $0) })
        return document.targets.reduce(into: [:]) { units, target in
            guard let rule = rulesByID[target.ruleID] else { return }
            units[target.ruleID] = RuleUnit(rule: rule, target: target)
        }
    }

    public static func isLoosening(from before: RuleUnit?, to after: RuleUnit?) -> Bool {
        guard let before else {
            // Nothing covered this app before, so nothing it does now permits
            // more than it did. Covering it is a tightening.
            return false
        }
        guard let after else {
            // Coverage dropped, which is how an app leaves Pause.
            return true
        }
        if after.rule.sessionsPerDay > before.rule.sessionsPerDay { return true }
        if after.rule.sessionLengthMinutes > before.rule.sessionLengthMinutes { return true }
        // A target re-pointed at another application drops coverage of the app
        // it named before.
        return after.target.applicationToken != before.target.applicationToken
    }

    public static func isLoosening(from before: GlobalSettings, to after: GlobalSettings) -> Bool {
        after.pauseSeconds < before.pauseSeconds
    }

    public static func isLoosening(
        from before: ConfigurationDocument,
        to after: ConfigurationDocument
    ) -> Bool {
        if isLoosening(from: before.settings, to: after.settings) { return true }
        let afterUnits = units(of: after)
        for (ruleID, beforeUnit) in units(of: before) {
            if isLoosening(from: beforeUnit, to: afterUnits[ruleID]) { return true }
        }
        return false
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|\*\* TEST"`

Expected: `** TEST SUCCEEDED **`. Every pre-existing `ConfigurationComparisonTests` case must still pass — the document-level function keeps its behavior exactly, and those tests are the proof.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shared/ConfigurationComparison.swift Tests/SharedTests/ConfigurationComparisonTests.swift
git commit -m "refactor: judge loosening one unit at a time"
```

---

### Task 2: The router splits a save by unit

**Files:**
- Modify: `Sources/Shared/ConfigurationSaveRouter.swift`
- Modify: `Sources/Pause/AppModel.swift:856-860` (add `try` at the one call site)
- Test: `Tests/SharedTests/ConfigurationSaveRouterTests.swift`

**Interfaces:**
- Consumes: everything Task 1 produced.
- Produces: `ConfigurationSaveRouter.route(candidate:into:now:calendar:) throws -> ConfigurationFile` — same parameters as before, now throwing. Task 3 relies on the guarantee that `result.effective != candidate` exactly when the save deferred part of itself.

- [ ] **Step 1: Write the failing tests**

Append these to `ConfigurationSaveRouterTests.swift`, above `// MARK: - Helpers`. Note that every existing test in this file must be updated to `try ConfigurationSaveRouter.route(...)` in the same step, since the function becomes throwing.

```swift
    func testAnAddedAppIsCoveredTodayWhileADroppedOneWaits() throws {
        let existing = ConfigurationFile(effective: try document(seeds: ["a", "b"]), pending: nil)
        // The picker's candidate: "b" dropped, "c" added, "a" retained.
        let candidate = try document(seeds: ["a", "c"])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(seeds(of: result.effective), ["a", "b", "c"])
        XCTAssertEqual(seeds(of: result.pending?.document), ["a", "c"])
        XCTAssertEqual(result.pending?.startDay, LogicalDay.next(after: now(), calendar: calendar))
    }

    func testAScheduledRemovalSurvivesASaveAboutAnotherApp() throws {
        let existing = ConfigurationFile(
            effective: try document(seeds: ["a", "b"]),
            pending: PendingConfiguration(
                document: try document(seeds: ["a"]),
                startDay: LogicalDay.next(after: now(), calendar: calendar)
            )
        )
        // Adding "c" says nothing about "b", whose removal is already scheduled.
        let candidate = try document(seeds: ["a", "b", "c"])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(seeds(of: result.effective), ["a", "b", "c"])
        XCTAssertEqual(seeds(of: result.pending?.document), ["a", "c"])
    }

    func testAScheduledAllowanceSurvivesASaveAboutAnotherApp() throws {
        let scheduled = try document(seeds: ["a", "b"], sessionsPerDay: ["a": 5])
        let existing = ConfigurationFile(
            effective: try document(seeds: ["a", "b"]),
            pending: PendingConfiguration(
                document: scheduled,
                startDay: LogicalDay.next(after: now(), calendar: calendar)
            )
        )
        let candidate = try document(seeds: ["a", "b", "c"])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(sessionsPerDay(of: result.effective, seed: "a"), 3)
        XCTAssertEqual(sessionsPerDay(of: result.pending?.document, seed: "a"), 5)
        XCTAssertEqual(seeds(of: result.effective), ["a", "b", "c"])
    }

    func testASaveAboutAnAppReplacesWhatWasScheduledForIt() throws {
        let existing = ConfigurationFile(
            effective: try document(seeds: ["a", "b"]),
            pending: PendingConfiguration(
                document: try document(seeds: ["a", "b"], sessionsPerDay: ["a": 5]),
                startDay: LogicalDay.next(after: now(), calendar: calendar)
            )
        )
        let candidate = try document(seeds: ["a", "b"], sessionsPerDay: ["a": 4])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(sessionsPerDay(of: result.effective, seed: "a"), 3)
        XCTAssertEqual(sessionsPerDay(of: result.pending?.document, seed: "a"), 4)
    }

    func testASaveThatDefersNothingLeavesTheCandidateAsEffective() throws {
        let existing = ConfigurationFile(effective: try document(seeds: ["a", "b"]), pending: nil)
        let candidate = try document(seeds: ["a", "b"], sessionsPerDay: ["a": 2])

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(result.effective, candidate)
        XCTAssertNil(result.pending)
    }

    func testASettingsLooseningWaitsWhileAnAppChangeApplies() throws {
        let existing = ConfigurationFile(effective: try document(seeds: ["a", "b"]), pending: nil)
        let candidate = try document(seeds: ["a", "b"], sessionsPerDay: ["a": 2], pauseSeconds: 5)

        let result = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now(),
            calendar: calendar
        )

        XCTAssertEqual(sessionsPerDay(of: result.effective, seed: "a"), 2)
        XCTAssertEqual(result.effective.settings.pauseSeconds, 10)
        XCTAssertEqual(result.pending?.document.settings.pauseSeconds, 5)
    }
```

Replace the file's existing `document(sessionsPerDay:)` helper with these, and update the four pre-existing tests to call `document(seeds: ["a"], sessionsPerDay: ["a": n])` in its place:

```swift
    private let ruleIDs = [
        "a": UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!,
        "b": UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!,
        "c": UUID(uuidString: "cccccccc-0000-0000-0000-000000000003")!,
    ]

    /// Each app keeps one rule id across every document a test builds, which is
    /// what pairs its unit between them.
    private func document(
        seeds: [String],
        sessionsPerDay: [String: Int] = [:],
        pauseSeconds: Int = 10
    ) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: GlobalSettings(pauseSeconds: pauseSeconds),
            rules: try seeds.map { seed in
                try AppRule(
                    id: ruleIDs[seed]!,
                    sessionsPerDay: sessionsPerDay[seed] ?? 3,
                    sessionLengthMinutes: 5
                )
            },
            targets: try seeds.map { seed in
                RuleTarget(
                    ruleID: ruleIDs[seed]!,
                    applicationToken: try token(seed: seed),
                    launchRoute: nil
                )
            }
        )
    }

    private func seeds(of document: ConfigurationDocument?) -> [String]? {
        document?.targets.compactMap { target in
            ruleIDs.first { $0.value == target.ruleID }?.key
        }
    }

    private func sessionsPerDay(of document: ConfigurationDocument?, seed: String) -> Int? {
        document?.rules.first { $0.id == ruleIDs[seed] }?.sessionsPerDay
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|\*\* TEST"`

Expected: FAIL. The new cases assert a split the router does not do yet.

- [ ] **Step 3: Write the implementation**

Replace the whole body of `Sources/Shared/ConfigurationSaveRouter.swift` with:

```swift
import Foundation
import PauseCore

/// Decides what a saved edit changes now and what waits for the next reset,
/// one unit at a time.
///
/// A save rebuilds the whole document, so what it left as the rules in force is
/// what it had no opinion about. Those units keep whatever was already
/// scheduled for them; the units it did state differently take what it says.
/// Each resulting unit then applies at once unless it loosens, in which case
/// only the scheduled document carries it.
public enum ConfigurationSaveRouter {
    public static func route(
        candidate: ConfigurationDocument,
        into existing: ConfigurationFile,
        now: Date,
        calendar: Calendar = .current
    ) throws -> ConfigurationFile {
        let inForce = existing.inForce(on: LogicalDay.containing(now, calendar: calendar))
        let scheduled = existing.pending?.document

        let inForceUnits = ConfigurationComparison.units(of: inForce)
        let candidateUnits = ConfigurationComparison.units(of: candidate)
        let scheduledUnits = scheduled.map(ConfigurationComparison.units(of:))

        var immediateUnits: [ConfigurationComparison.RuleUnit] = []
        var scheduledResultUnits: [ConfigurationComparison.RuleUnit] = []

        for ruleID in orderedRuleIDs(inForce: inForce, candidate: candidate) {
            let inForceUnit = inForceUnits[ruleID]
            let candidateUnit = candidateUnits[ruleID]
            let target: ConfigurationComparison.RuleUnit?
            if candidateUnit != inForceUnit {
                target = candidateUnit
            } else if let scheduledUnits {
                target = scheduledUnits[ruleID]
            } else {
                target = inForceUnit
            }

            if let target { scheduledResultUnits.append(target) }
            let immediate = ConfigurationComparison.isLoosening(from: inForceUnit, to: target)
                ? inForceUnit
                : target
            if let immediate { immediateUnits.append(immediate) }
        }

        let targetSettings: GlobalSettings
        if candidate.settings != inForce.settings {
            targetSettings = candidate.settings
        } else {
            targetSettings = scheduled?.settings ?? inForce.settings
        }
        let immediateSettings = ConfigurationComparison.isLoosening(
            from: inForce.settings,
            to: targetSettings
        ) ? inForce.settings : targetSettings

        let immediate = try document(settings: immediateSettings, units: immediateUnits)
        let scheduledResult = try document(settings: targetSettings, units: scheduledResultUnits)

        guard scheduledResult != immediate else {
            return ConfigurationFile(effective: immediate, pending: nil)
        }
        return ConfigurationFile(
            effective: immediate,
            pending: PendingConfiguration(
                document: scheduledResult,
                startDay: LogicalDay.next(after: now, calendar: calendar)
            )
        )
    }

    /// Rule order is user-visible in the rules list, so the documents this
    /// builds keep the in-force order and append only what the candidate adds.
    /// A unit named by the scheduled document alone is ignored: a scheduled
    /// document can only hold units the effective one holds, since an addition
    /// is a tightening and never waits.
    private static func orderedRuleIDs(
        inForce: ConfigurationDocument,
        candidate: ConfigurationDocument
    ) -> [UUID] {
        var ordered = inForce.targets.map(\.ruleID)
        let known = Set(ordered)
        ordered.append(contentsOf: candidate.targets.map(\.ruleID).filter { !known.contains($0) })
        return ordered
    }

    private static func document(
        settings: GlobalSettings,
        units: [ConfigurationComparison.RuleUnit]
    ) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: settings,
            rules: units.map(\.rule),
            targets: units.map(\.target)
        )
    }
}
```

- [ ] **Step 4: Update the one call site**

In `Sources/Pause/AppModel.swift`, the call inside `persist` becomes throwing. Change:

```swift
        let routed = ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now
        )
```

to:

```swift
        let routed = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now
        )
```

`persist` is already declared `throws`, so nothing else changes.

- [ ] **Step 5: Run the full suite**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|failed|\*\* TEST"`

Expected: `** TEST SUCCEEDED **`. If a pre-existing test fails on document *order* rather than content, that is this task's bug — fix `orderedRuleIDs`, not the test. If it fails on content, stop and report: the split is changing behavior the existing tests pinned deliberately.

- [ ] **Step 6: Commit**

```bash
git add Sources/Shared/ConfigurationSaveRouter.swift Sources/Pause/AppModel.swift Tests/SharedTests/ConfigurationSaveRouterTests.swift
git commit -m "feat: split a saved edit by app rather than deferring it whole"
```

---

### Task 3: The editor closes on a save that deferred nothing of its own

**Files:**
- Modify: `Sources/Pause/AppModel.swift` (a published flag, set in `persist`, cleared in `cancelScheduledChange`)
- Modify: `Sources/Pause/RuleEditorView.swift:79`
- Test: `Tests/PauseAppTests/AppModelFlowTests.swift`

**Interfaces:**
- Consumes: the guarantee from Task 2 that `route`'s effective document differs from the candidate exactly when the save deferred part of itself.
- Produces: `AppModel.lastSaveDeferredPart: Bool`, published and private-set.

- [ ] **Step 1: Write the failing tests**

Append these to `AppModelFlowTests.swift`, above `private func makeModel(`. They use the file's existing `ruleID`, `now`, `temporaryDirectory()`, `seedOneRule(in:sessionsPerDay:)`, `makeModel(directory:probe:hasProtectedState:)` and `token(seed:)` helpers unchanged.

```swift
    func testAPickerSaveThatAddsAndDropsCoversTheAddedAppToday() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        // One trip through the picker: Instagram dropped, Threads added.
        model.pickerSelection.applicationTokens = [try token(seed: "threads")]

        try model.applyPickerSelection(now: now)

        XCTAssertEqual(
            Set(model.configuration.targets.map(\.applicationToken)),
            [try token(seed: "instagram"), try token(seed: "threads")]
        )
        XCTAssertEqual(model.ruleIDsPendingRemoval, [ruleID])
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now))
        XCTAssertTrue(model.lastSaveDeferredPart)
    }

    func testTheAddedAppSurvivesTheDropWhenItLands() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        model.pickerSelection.applicationTokens = [try token(seed: "threads")]
        try model.applyPickerSelection(now: now)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        model.sceneDidBecomeActive(now: tomorrow)

        XCTAssertEqual(
            model.configuration.targets.map(\.applicationToken),
            [try token(seed: "threads")]
        )
        XCTAssertEqual(model.ruleIDsPendingRemoval, [])
        XCTAssertNil(model.pendingChangeStartDay)
    }

    func testATighteningSaveDefersNothingOfItsOwnWhileAChangeIsScheduled() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seedOneRule(in: directory, sessionsPerDay: 3)
        let model = makeModel(
            directory: directory,
            probe: FlowProbe(status: .approved),
            hasProtectedState: false
        )
        // Schedule Instagram's removal, then lengthen the pause — a tightening
        // that says nothing about Instagram.
        model.pickerSelection.applicationTokens = []
        try model.applyPickerSelection(now: now)
        XCTAssertTrue(model.lastSaveDeferredPart)

        try model.updatePauseSeconds(20, now: now)

        XCTAssertEqual(model.configuration.settings.pauseSeconds, 20)
        XCTAssertFalse(model.lastSaveDeferredPart)
        // The removal is still scheduled; only this save deferred nothing.
        XCTAssertEqual(model.pendingChangeStartDay, LogicalDay.next(after: now))
        XCTAssertEqual(model.ruleIDsPendingRemoval, [ruleID])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|\*\* TEST"`

Expected: compilation failure on `lastSaveDeferredPart`, and the picker case failing if written before Task 2 landed.

- [ ] **Step 3: Write the implementation**

In `AppModel`, beside `pendingChangeStartDay`:

```swift
    /// Whether the last save deferred part of itself, as opposed to leaving a
    /// change scheduled that it never touched. The rule editor stays open only
    /// for the former: the wait it shows should be the one just chosen.
    @Published private(set) var lastSaveDeferredPart = false
```

At the end of `persist`, after `pendingChangeStartDay` is set:

```swift
        lastSaveDeferredPart = routed.effective != candidate
```

In `cancelScheduledChange`, beside the existing `pendingChangeStartDay = nil`:

```swift
        lastSaveDeferredPart = false
```

In `RuleEditorView.swift:79`, change:

```swift
            if model.pendingChangeStartDay == nil {
                dismiss()
            }
```

to:

```swift
            if !model.lastSaveDeferredPart {
                dismiss()
            }
```

Leave `RuleEditorView.swift:23` and `RulesView.swift:54` reading `pendingChangeStartDay` — the notice shows everything scheduled, which has not changed.

- [ ] **Step 4: Run the full suite and the device build**

```bash
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|\*\* TEST"
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "warning:.*\.swift|error:|\*\* BUILD"
```

Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **` with no Swift warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/Pause/AppModel.swift Sources/Pause/RuleEditorView.swift Tests/PauseAppTests/AppModelFlowTests.swift
git commit -m "feat: close the editor on a save that deferred nothing of its own"
```
