import AppIntents
import Foundation
#if TALLY_APPDB_EXTENSIONS || TALLY_FULL_SIGNING
import ActivityKit
#endif

struct IncrementTallyCounterIntent: AppIntent {
    static var title: LocalizedStringResource = "Increment Tally Counter"
    static var description = IntentDescription("Increase or decrease a Tally counter by name without opening the full interface.")
    static var openAppWhenRun = false

    @Parameter(title: "Counter Name")
    var counterName: String

    @Parameter(title: "Amount", default: 1)
    var amount: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { () -> String in
            let store = TallyStore()
            guard let counter = store.activeCounters.first(where: {
                $0.name.localizedCaseInsensitiveCompare(counterName) == .orderedSame
            }) else {
                return "I could not find a counter named \(counterName)."
            }
            guard !counter.isLocked else {
                return "\(counter.name) is locked."
            }
            let safeAmount = min(max(amount, -9999), 9999)
            store.safeAdjust(counter, by: safeAmount)
            let updated = store.counters.first(where: { $0.id == counter.id })?.value ?? counter.value
            return "\(counter.name) is now \(updated)."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct ReadTallyCounterIntent: AppIntent {
    static var title: LocalizedStringResource = "Read Tally Counter"
    static var description = IntentDescription("Return the current value of a Tally counter by name.")
    static var openAppWhenRun = false

    @Parameter(title: "Counter Name")
    var counterName: String

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let result = await MainActor.run { () -> (Int, String) in
            let store = TallyStore()
            guard let counter = store.activeCounters.first(where: {
                $0.name.localizedCaseInsensitiveCompare(counterName) == .orderedSame
            }) else {
                return (0, "I could not find a counter named \(counterName).")
            }
            return (counter.value, "\(counter.name) is \(counter.value).")
        }
        return .result(value: result.0, dialog: IntentDialog(stringLiteral: result.1))
    }
}

struct StartTallySessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Tally Session"
    static var description = IntentDescription("Start a standalone or counter-linked Tally session.")
    static var openAppWhenRun = false

    @Parameter(title: "Counter Name", description: "Leave blank for a standalone session.", default: "")
    var counterName: String

    @Parameter(title: "Session Name", default: "")
    var sessionName: String

    @Parameter(title: "Goal Minutes", default: 0)
    var goalMinutes: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await Task { @MainActor in
            let store = TallyStore()
            let trimmed = counterName.trimmingCharacters(in: .whitespacesAndNewlines)
            let counter = trimmed.isEmpty ? nil : store.activeCounters.first(where: {
                $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
            })
            if !trimmed.isEmpty && counter == nil {
                return "I could not find a counter named \(trimmed)."
            }
            let goal = goalMinutes > 0 ? TimeInterval(min(goalMinutes, 24 * 60) * 60) : nil
            let session = store.startSession(
                counterID: counter?.id,
                title: sessionName,
                notes: "Started from Shortcuts",
                goalDuration: goal
            )

            #if TALLY_APPDB_EXTENSIONS || TALLY_FULL_SIGNING
            await TallyFullSigningBridge.shared.startLiveActivity(for: session, store: store)
            #endif

            return "Started \(session.title)."
        }.value
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

#if TALLY_APPDB_EXTENSIONS || TALLY_FULL_SIGNING
struct TestTallyLiveActivityIntent: AppIntent {
    static var title: LocalizedStringResource = "Test Tally Live Activity"
    static var description = IntentDescription("Start a five-minute diagnostic Tally session and request its Live Activity immediately.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await Task { @MainActor in
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                return "Live Activities are disabled for Tally in iOS Settings. Enable them, then run this test again."
            }

            let store = TallyStore()
            let session = store.startSession(
                counterID: nil,
                title: "Live Activity Test",
                notes: "Diagnostic Live Activity test",
                goalDuration: 5 * 60
            )

            await TallyFullSigningBridge.shared.startLiveActivity(for: session, store: store)

            let isRunning = Activity<TallySessionActivityAttributes>.activities.contains {
                $0.attributes.sessionID == session.id
            }
            return isRunning
                ? "Live Activity started. Lock your iPhone now and look near the bottom of the Lock Screen."
                : "Tally requested the Live Activity, but iOS did not report it as active."
        }.value

        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
#endif

struct OpenTallyIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Tally"
    static var description = IntentDescription("Open Tally to your counters.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct TallyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTallyIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show my counters in \(.applicationName)"
            ],
            shortTitle: "Open Tally",
            systemImageName: "number.circle.fill"
        )

        #if TALLY_APPDB_EXTENSIONS || TALLY_FULL_SIGNING
        AppShortcut(
            intent: TestTallyLiveActivityIntent(),
            phrases: [
                "Test Live Activity in \(.applicationName)"
            ],
            shortTitle: "Test Live Activity",
            systemImageName: "waveform.path.ecg.rectangle"
        )
        #endif
    }
}
