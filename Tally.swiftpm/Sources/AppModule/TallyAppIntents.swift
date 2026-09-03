import AppIntents
import Foundation

struct IncrementTallyCounterIntent: AppIntent {
    static let title: LocalizedStringResource = "Increment Tally Counter"
    static let description = IntentDescription("Increase or decrease a Tally counter by name without opening the full interface.")
    static let openAppWhenRun = false

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
    static let title: LocalizedStringResource = "Read Tally Counter"
    static let description = IntentDescription("Return the current value of a Tally counter by name.")
    static let openAppWhenRun = false

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
    static let title: LocalizedStringResource = "Start Tally Session"
    static let description = IntentDescription("Start a standalone or counter-linked Tally session.")
    static let openAppWhenRun = false

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

            await TallyLiveActivityManager.shared.startLiveActivity(for: session, store: store)
            return "Started \(session.title)."
        }.value
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct OpenTallyIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Tally"
    static let description = IntentDescription("Open Tally to your counters.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct TallyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: OpenTallyIntent(),
                phrases: [
                    "Open \(.applicationName)",
                    "Show my counters in \(.applicationName)"
                ],
                shortTitle: "Open Tally",
                systemImageName: "number.circle.fill"
            )
        ]
    }
}
