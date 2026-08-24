# Session Usage Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show, for each restricted app in the rules list, how many sessions are charged against the current allowance day.

**Architecture:** A new `RuleUsageReader` in `Sources/Shared/` pairs the configuration file with the runtime repository and returns the used count per rule, running each through `RuleLookup.evaluate` so the stored count is rolled over to the current allowance day. `AppModel` publishes the reader's result; `RulesView` renders it as a trailing value on each row.

**Tech Stack:** Swift 6, Xcode 26.6, XcodeGen, XCTest, SwiftUI.

**Spec:** [`docs/design/session-usage-display.md`](../design/session-usage-display.md)

## Global Constraints

- Deployment target iOS 26.5 or later; iPhone only. Xcode 26.6, Swift 6.
- Public APIs only. No private framework calls.
- **The count is never read raw from disk.** `RuleRuntime.sessionsStarted` rolls over lazily, so every surface showing it must resolve the allowance day and apply the rollover. Reuse `RuleLookup.evaluate`; do not add a second way of counting.
- **The reader takes `ConfigurationFile`, never `ConfigurationDocument`.** The allowance day comes from the effective document's reset, and only the file can pair the two. This mirrors `ShieldStateReader` and `RuleLookup.resolve`.
- The row shows `used/limit` — e.g. `2/4`. Session length leaves the row and stays in the editor.
- An open session is not marked. Exhaustion needs no treatment: `3/3` states it.
- A rule whose runtime cannot be read shows no number rather than a wrong one.
- No new stored state. Nothing about previous days is kept.
- Regenerate the project with `xcodegen generate` after adding any file. `*.xcodeproj` is gitignored, so expect no project hunk in any diff.
- Full suite: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` (currently green at 292 tests, 0 Swift warnings)
- Generic-device build: `xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`

---

### Task 1: Read the day's usage per rule

**Files:**
- Create: `Sources/Shared/RuleUsageReader.swift`
- Test: `Tests/SharedTests/RuleUsageReaderTests.swift` (create)

**Interfaces:**
- Consumes: `RuleLookup.evaluate(rule:runtime:logicalDay:now:)`, `ConfigurationFile.inForce(at:calendar:)`, `ConfigurationFile.logicalDay(at:calendar:)`, `RuntimeReading` — all existing.
- Produces: `RuleUsageReader.init(runtimeReader: any RuntimeReading)` and `RuleUsageReader.sessionsUsed(in:now:calendar:) -> [UUID: Int]`.

- [x] **Step 1: Write the failing tests**

Create `Tests/SharedTests/RuleUsageReaderTests.swift`:

```swift
import Foundation
import PauseCore
import XCTest

/// The reader consults `rules` alone, so these documents carry no targets.
/// Adding one would mean fabricating an `ApplicationToken` and would test
/// nothing the reader reads.
final class RuleUsageReaderTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testReportsTheStoredCountForTheCurrentAllowanceDay() throws {
        let ruleID = UUID()
        let now = date(year: 2026, month: 8, day: 20, hour: 9)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 0)
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: calendar),
                    sessionsStarted: 2
                )
            ])
        )

        let used = reader.sessionsUsed(in: file, now: now, calendar: calendar)

        XCTAssertEqual(used[ruleID], 2)
    }

    func testAnUntouchedRuleReadsAsNoneUsed() throws {
        let ruleID = UUID()
        let now = date(year: 2026, month: 8, day: 20, hour: 9)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 0)
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: calendar),
                    sessionsStarted: 0
                )
            ])
        )

        XCTAssertEqual(reader.sessionsUsed(in: file, now: now, calendar: calendar)[ruleID], 0)
    }

    func testAnExhaustedRuleReadsAsItsLimit() throws {
        let ruleID = UUID()
        let now = date(year: 2026, month: 8, day: 20, hour: 9)
        let file = try file(ruleID: ruleID, sessionsPerDay: 3, resetMinuteOfDay: 0)
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: calendar),
                    sessionsStarted: 3
                )
            ])
        )

        XCTAssertEqual(reader.sessionsUsed(in: file, now: now, calendar: calendar)[ruleID], 3)
    }

    /// The stored count rolls over lazily, so a record left from an earlier day
    /// still carries that day's number. Reading it raw is the defect this reader
    /// exists to avoid.
    func testACountLeftFromAnEarlierDayReadsAsNoneUsed() throws {
        let ruleID = UUID()
        let spentAt = date(year: 2026, month: 8, day: 20, hour: 9)
        let today = date(year: 2026, month: 8, day: 21, hour: 9)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 0)
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(spentAt, resetMinuteOfDay: 0, calendar: calendar),
                    sessionsStarted: 4
                )
            ])
        )

        XCTAssertEqual(reader.sessionsUsed(in: file, now: today, calendar: calendar)[ruleID], 0)
    }

    /// The feature's central behaviour, and the shape of the defect the
    /// configurable-reset effort shipped: with the reset away from midnight, the
    /// civil date turning over must not renew the count.
    func testTheCountSurvivesMidnightWhenTheResetIsLater() throws {
        let ruleID = UUID()
        let spentAt = date(year: 2026, month: 8, day: 20, hour: 9)
        let afterMidnight = date(year: 2026, month: 8, day: 21, hour: 2)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 6 * 60)
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(
                        spentAt,
                        resetMinuteOfDay: 6 * 60,
                        calendar: calendar
                    ),
                    sessionsStarted: 3
                )
            ])
        )

        XCTAssertEqual(reader.sessionsUsed(in: file, now: afterMidnight, calendar: calendar)[ruleID], 3)
    }

    func testTheCountRenewsOnceTheConfiguredResetHasPassed() throws {
        let ruleID = UUID()
        let spentAt = date(year: 2026, month: 8, day: 20, hour: 9)
        let afterReset = date(year: 2026, month: 8, day: 21, hour: 7)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 6 * 60)
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(
                        spentAt,
                        resetMinuteOfDay: 6 * 60,
                        calendar: calendar
                    ),
                    sessionsStarted: 3
                )
            ])
        )

        XCTAssertEqual(reader.sessionsUsed(in: file, now: afterReset, calendar: calendar)[ruleID], 0)
    }

    func testARuleWhoseRuntimeIsMissingCarriesNoCount() throws {
        let ruleID = UUID()
        let now = date(year: 2026, month: 8, day: 20, hour: 9)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 0)

        let used = RuleUsageReader(runtimeReader: StubRuntimeReader())
            .sessionsUsed(in: file, now: now, calendar: calendar)

        XCTAssertNil(used[ruleID])
    }

    func testARuleWhoseRuntimeCannotBeReadCarriesNoCount() throws {
        let ruleID = UUID()
        let now = date(year: 2026, month: 8, day: 20, hour: 9)
        let file = try file(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 0)

        let used = RuleUsageReader(
            runtimeReader: StubRuntimeReader(unreadableRuleIDs: [ruleID])
        ).sessionsUsed(in: file, now: now, calendar: calendar)

        XCTAssertNil(used[ruleID])
    }

    /// The reset that decides the allowance day is the effective document's. A
    /// pending document carrying a different reset must not move the boundary
    /// that the count is charged against.
    func testTheEffectiveResetDecidesTheDayNotThePendingOne() throws {
        let ruleID = UUID()
        let spentAt = date(year: 2026, month: 8, day: 20, hour: 9)
        let afterMidnight = date(year: 2026, month: 8, day: 21, hour: 2)
        let effective = try document(ruleID: ruleID, sessionsPerDay: 4, resetMinuteOfDay: 6 * 60)
        let scheduled = try document(ruleID: ruleID, sessionsPerDay: 8, resetMinuteOfDay: 0)
        let file = ConfigurationFile(
            effective: effective,
            pending: PendingConfiguration(
                document: scheduled,
                startDay: CalendarDay(date: afterMidnight, calendar: calendar)
            )
        )
        let reader = RuleUsageReader(
            runtimeReader: StubRuntimeReader(runtimes: [
                ruleID: RuleRuntime(
                    logicalDay: LogicalDay.containing(
                        spentAt,
                        resetMinuteOfDay: 6 * 60,
                        calendar: calendar
                    ),
                    sessionsStarted: 3
                )
            ])
        )

        XCTAssertEqual(reader.sessionsUsed(in: file, now: afterMidnight, calendar: calendar)[ruleID], 3)
    }

    private func document(
        ruleID: UUID,
        sessionsPerDay: Int,
        resetMinuteOfDay: Int
    ) throws -> ConfigurationDocument {
        try ConfigurationDocument(
            settings: GlobalSettings(pauseSeconds: 10, resetMinuteOfDay: resetMinuteOfDay),
            rules: [AppRule(id: ruleID, sessionsPerDay: sessionsPerDay, sessionLengthMinutes: 5)],
            targets: []
        )
    }

    private func file(
        ruleID: UUID,
        sessionsPerDay: Int,
        resetMinuteOfDay: Int
    ) throws -> ConfigurationFile {
        ConfigurationFile(
            effective: try document(
                ruleID: ruleID,
                sessionsPerDay: sessionsPerDay,
                resetMinuteOfDay: resetMinuteOfDay
            ),
            pending: nil
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}

private struct StubRuntimeReader: RuntimeReading {
    var runtimes: [UUID: RuleRuntime] = [:]
    var unreadableRuleIDs: Set<UUID> = []

    func load(ruleID: UUID) throws -> RuleRuntime? {
        if unreadableRuleIDs.contains(ruleID) {
            throw StubError.unreadable
        }
        return runtimes[ruleID]
    }

    enum StubError: Error {
        case unreadable
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseSharedTests/RuleUsageReaderTests` Expected: FAIL — `RuleUsageReader` does not exist.

- [x] **Step 3: Write the implementation**

Create `Sources/Shared/RuleUsageReader.swift`:

```swift
import Foundation
import PauseCore

/// How many sessions each rule has charged against the current allowance day.
///
/// The sibling of `ShieldStateReader`: that one answers what the shield should
/// say about a single app, this one answers what the list should show for every
/// app. Both take the configuration file rather than a document, because the
/// allowance day comes from the effective document's reset and only the file can
/// pair the two.
public struct RuleUsageReader {
    private let runtimeReader: any RuntimeReading

    public init(runtimeReader: any RuntimeReading) {
        self.runtimeReader = runtimeReader
    }

    /// Sessions charged per rule, keyed by rule ID.
    ///
    /// The stored count rolls over lazily, so a record keeps an earlier day's
    /// number until something touches it. `RuleLookup.evaluate` is what resolves
    /// that — it rolls the runtime to the day and writes nothing, so asking it
    /// for a display is free of side effects. Counting here instead would be a
    /// second implementation of which day a session is charged to, and the two
    /// would agree only until one was edited.
    ///
    /// A rule whose runtime is missing or unreadable is absent from the result
    /// rather than present with a wrong count: the list shows no number instead
    /// of a false one.
    public func sessionsUsed(
        in configurationFile: ConfigurationFile,
        now: Date,
        calendar: Calendar = .current
    ) -> [UUID: Int] {
        let configuration = configurationFile.inForce(at: now, calendar: calendar)
        let logicalDay = configurationFile.logicalDay(at: now, calendar: calendar)

        return configuration.rules.reduce(into: [:]) { used, rule in
            guard let runtime = try? runtimeReader.load(ruleID: rule.id) else { return }
            used[rule.id] = RuleLookup.evaluate(
                rule: rule,
                runtime: runtime,
                logicalDay: logicalDay,
                now: now
            ).runtime.sessionsStarted
        }
    }
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseSharedTests/RuleUsageReaderTests` Expected: PASS, 9 tests.

- [x] **Step 5: Run the full suite**

Run the full suite command from Global Constraints. Expected: PASS, no new Swift warnings. Nothing existing changed.

- [x] **Step 6: Commit**

```bash
git add Sources/Shared/RuleUsageReader.swift Tests/SharedTests/RuleUsageReaderTests.swift
git commit -m "feat: read the day's charged sessions per rule"
```

---

### Task 2: Publish the usage to the views

**Files:**
- Modify: `Sources/Pause/AppModel.swift`
- Test: `Tests/PauseAppTests/AppModelFlowTests.swift`

**Interfaces:**
- Consumes: `RuleUsageReader.sessionsUsed(in:now:calendar:)` (Task 1).
- Produces: `AppModel.sessionsUsedByRule: [UUID: Int]`, published and read-only from outside.

- [x] **Step 1: Add the published property**

Beside the other published properties in `AppModel` (the block beginning `@Published private(set) var authorizationStatus`), add:

```swift
    /// Sessions charged against the current allowance day, per rule, for the
    /// list. Empty until a configuration file and runtime repository exist.
    @Published private(set) var sessionsUsedByRule: [UUID: Int] = [:]
```

- [x] **Step 2: Add the refresh**

Add this private method beside `refreshInForceConfiguration(now:)`:

```swift
    /// Rebuilt rather than tracked. The stored count rolls over lazily, so the
    /// only correct answer is the one resolved against the allowance day now —
    /// a cached number would be wrong for exactly as long as nobody opened the
    /// app, which is when it is most likely to be read.
    private func refreshUsage(now: Date) {
        guard let configurationFile, let runtimeRepository else {
            sessionsUsedByRule = [:]
            return
        }
        sessionsUsedByRule = RuleUsageReader(runtimeReader: runtimeRepository)
            .sessionsUsed(in: configurationFile, now: now)
    }
```

- [x] **Step 3: Call it at the three points state changes**

**In `sceneDidBecomeActive(now:)`** — insert immediately after the line `authorizationStatusAtLastActivation = authorizationStatus`, so it reads:

```swift
        activationCoordinator = coordinator
        authorizationStatusAtLastActivation = authorizationStatus
        refreshUsage(now: now)

        switch outcome {
```

This position is deliberate and must not move. It sits after the activation coordinator has run cleanup and reconciliation — which can roll back a provisional session and so lower a count — and before the `switch outcome`, whose `.unchanged` case returns early. `.unchanged` is the ordinary foreground outcome, so a refresh placed at the end of the method would never run on a normal return to the app.

**In `persist(_:now:)`** — after `pendingChangeStartDay = Self.scheduledStartDay(in: routed, now: now)`, add:

```swift
        refreshUsage(now: now)
```

A save can add a rule, remove one, or change a limit, so the snapshot has to be rebuilt against the document that is now in force.

**In `requestSessionGrant(now:)`** — inside the `do` block, after `activationCoordinator.returnedToConfiguration()` and before `switch result`, add:

```swift
            refreshUsage(now: now)
```

Granting a session is the only event that raises a count.

- [x] **Step 4: Write the failing test**

`AppModelFlowTests` already seeds a rule and a runtime at a non-zero reset in `testEntryIsRefusedAfterMidnightWhileTheAllowanceDayStillRuns`. Read that test and reuse its seeding verbatim — same helpers, same fixture shape — then assert the published snapshot rather than the entry route:

```swift
    /// The list reads this snapshot, so activation must populate it with the
    /// count resolved against the allowance day — not the civil date, and not
    /// whatever the record happened to carry on disk.
    func testActivationPublishesTheCountResolvedAgainstTheAllowanceDay() throws {
        // Seed exactly as testEntryIsRefusedAfterMidnightWhileTheAllowanceDayStillRuns
        // does: a rule of 4 sessions per day, a 06:00 reset, a runtime charged
        // with 4 sessions on the allowance day that began at 06:00 the previous
        // morning, and `now` set after local midnight but before that reset.

        model.sceneDidBecomeActive(now: afterMidnight)

        XCTAssertEqual(
            model.sessionsUsedByRule[ruleID],
            4,
            "midnight passing must not renew the count when the reset is later"
        )
    }
```

Fill the seeding in from that test; the assertion above is the whole of what is new. If its fixture uses a different rule limit, keep the limit and change the expected count to match what it charges.

- [x] **Step 5: Run to verify it fails, then passes**

Run: `xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PauseAppTests/AppModelFlowTests`

Before Steps 1-3 this fails to compile — `sessionsUsedByRule` does not exist. After them: PASS.

Steps 1-3 and this test are one commit; the property cannot exist without its first reader. Task 1 covers the reader's correctness exhaustively against a stub. This test covers what only the model can prove: that activation actually runs the refresh, and that the number reaching the view survives midnight under a configured reset.

- [x] **Step 6: Run the full suite**

Run the full suite command. Expected: PASS, no new Swift warnings.

- [x] **Step 7: Commit**

```bash
git add Sources/Pause/AppModel.swift Tests/PauseAppTests/AppModelFlowTests.swift
git commit -m "feat: publish the day's session usage to the views"
```

---

### Task 3: Show the count on each row

**Files:**
- Modify: `Sources/Pause/RulesView.swift`

**Interfaces:**
- Consumes: `AppModel.sessionsUsedByRule` (Task 2).
- Produces: nothing other tasks rely on.

- [x] **Step 1: Replace the row's second line with a trailing count**

In the `Section("Apps")` block, the `NavigationLink`'s label is currently a `VStack` carrying the app label above `Text("\(rule.sessionsPerDay) × \(rule.sessionLengthMinutes) min")`. Replace that label with:

```swift
                            } label: {
                                HStack {
                                    AppTokenLabel(applicationToken: target.applicationToken)
                                    Spacer()
                                    Text(usageText(for: rule))
                                        .font(.system(.body, design: .rounded).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
```

`HStack` with a `Spacer` rather than `LabeledContent`: the leading view is a FamilyControls `Label`, whose intrinsic sizing inside `LabeledContent`'s label slot is not something this project can rely on, and the file already composes rows this way.

Session length leaves the row. It stays in `RuleEditorView`, which is where it is set.

- [x] **Step 2: Add the helper**

Beside the other private helpers in `RulesView`:

```swift
    /// Empty when the rule has no count — a runtime that is missing or
    /// unreadable shows nothing rather than a number that would be wrong.
    private func usageText(for rule: AppRule) -> String {
        guard let used = model.sessionsUsedByRule[rule.id] else { return "" }
        return "\(used)/\(rule.sessionsPerDay)"
    }
```

- [x] **Step 3: Give the pending-removal row the same treatment**

In `pendingRemovalRow(rule:target:)`, replace:

```swift
            Text("\(rule.sessionsPerDay) × \(rule.sessionLengthMinutes) min")
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundStyle(.tertiary)
```

with:

```swift
            Text(usageText(for: rule))
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundStyle(.tertiary)
```

A rule scheduled for removal is still in force until it goes, so its count is still the truth. This row keeps its vertical layout — it carries the removal sentence and a button, so it is not a one-line row.

- [x] **Step 4: Build and run the full suite**

Run the full suite command, then the generic-device build command. Expected: all PASS, BUILD SUCCEEDED, no Swift warnings.

There is no unit test for this step. `RulesView` is a SwiftUI view with no logic beyond `usageText`, and the project has no view-snapshot harness; the value it renders is pinned in Tasks 1 and 2. This is one of the things the device check below is for.

- [x] **Step 5: Commit**

```bash
git add Sources/Pause/RulesView.swift
git commit -m "feat: show each app's charged sessions in the list"
```

---

### Task 4: Close it out

**Files:**
- Modify: `docs/README.md`
- Modify: `docs/status.md`
- Modify: `docs/ROADMAP.md`

- [x] **Step 1: Verify the whole change**

```bash
xcodegen generate
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git status --short
```

Record the passing test count.

- [x] **Step 2: Extend docs/README.md**

The model section describes rules, shields, the countdown, and the allowance renewing at the daily reset. Add one sentence stating that the list shows each app's charged sessions against its limit for the day in progress, and that the same allowance is what the shield reports — the two cannot disagree because both resolve it the same way.

Present tense, no dates, no history. Do not restate the design's reasoning; point at [the design](design/session-usage-display.md) for it.

- [x] **Step 3: Update the status block**

Rewrite `## Status — resume here` in `docs/status.md` to state that the in-app session count is built and unverified on the phone, and keep the two device checks already owed — the configurable reset, and the three interface changes — plus the standing blocker that there is no git remote. Keep it to the block's four parts: state, next step, blockers, read first.

- [x] **Step 4: Note the device check on the roadmap**

Add to `docs/ROADMAP.md` under Deferred: the in-app count is unverified on the phone. The check is to spend a session and confirm the app's number moves in step with the shield's, and that both renew at the configured reset rather than at midnight.

This rides the same signed build as the reset check already listed, so say so — the two are one trip to the phone, not two.

- [x] **Step 5: Commit**

```bash
git add -A
git commit -m "docs: record the in-app session count and what the device still owes"
```

---

## Device check

Not a task — it needs a signed build on the phone and cannot run in the simulator.

Spend a session on a restricted app and confirm the list's number rises in step with the shield's. Then move the reset to a quarter-hour a few minutes ahead, wait for it to pass, and confirm the list renews at the new time rather than at midnight. The list and the shield must never disagree; if they do, they are resolving the allowance day differently, which is the defect this design exists to prevent.
