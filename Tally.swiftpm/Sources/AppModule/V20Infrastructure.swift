import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

struct TallyEditorCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct StepPresetEditor: View {
    @Binding var steps: [Int]

    private var normalized: [Int] {
        var result = TallyCounter.sanitizedStepValues(steps)
        while result.count < 3 {
            result.append([1, 5, 10][result.count])
        }
        return Array(result.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step Buttons").font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    TextField("Step \(index + 1)", value: valueBinding(index), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func valueBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { normalized[index] },
            set: { value in
                var copy = normalized
                copy[index] = min(max(value, 1), 9999)
                steps = TallyCounter.sanitizedStepValues(copy)
            }
        )
    }
}

enum TallyHapticKind {
    case selection
    case light
    case success
    case warning
}

extension TallyStore {
    func performHaptic(_ kind: TallyHapticKind) {
        guard preferences.hapticsEnabled else { return }
        #if canImport(UIKit)
        switch kind {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }

    func requestResetNotificationAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func cancelResetNotification(for counterID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [resetNotificationIdentifier(counterID)]
        )
    }

    func rescheduleAllResetNotifications() {
        for counter in counters where !counter.isArchived {
            scheduleResetNotification(for: counter)
        }
    }

    func scheduleResetNotification(for counter: TallyCounter) {
        let identifier = resetNotificationIdentifier(counter.id)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard counter.resetNotificationEnabled,
              counter.resetReminder != .none,
              !counter.isArchived else { return }

        Task { @MainActor in
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = await requestResetNotificationAuthorization()
                settings = await center.notificationSettings()
            }
            guard settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "Upcoming reset"
            content.body = "\(counter.name) resets in five minutes."
            content.sound = .default
            content.userInfo = ["counterID": counter.id.uuidString]

            let components = notificationDateComponents(for: counter)
            guard !components.isEmpty else { return }
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func nextResetDate(for counter: TallyCounter, after date: Date = Date()) -> Date? {
        guard counter.resetReminder != .none else { return nil }
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = counter.resetHour
        components.minute = counter.resetMinute
        components.second = 0

        switch counter.resetReminder {
        case .none:
            return nil
        case .daily:
            let today = calendar.date(from: components) ?? date
            return today > date ? today : calendar.date(byAdding: .day, value: 1, to: today)
        case .weekly:
            return calendar.nextDate(
                after: date,
                matching: DateComponents(
                    weekday: counter.resetWeekday,
                    hour: counter.resetHour,
                    minute: counter.resetMinute
                ),
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        case .monthly:
            return calendar.nextDate(
                after: date,
                matching: DateComponents(
                    day: counter.resetDayOfMonth,
                    hour: counter.resetHour,
                    minute: counter.resetMinute
                ),
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        }
    }

    func resetScheduleDescription(for counter: TallyCounter) -> String {
        guard let next = nextResetDate(for: counter) else { return "No scheduled reset" }
        return "Next reset \(next.formatted(date: .abbreviated, time: .shortened))"
    }

    func performScheduledResets(now: Date = Date()) {
        let eligibleIDs = counters.compactMap { counter -> UUID? in
            guard !counter.isArchived,
                  counter.automaticResetEnabled,
                  counter.resetReminder != .none else { return nil }

            let reference = counter.lastAutomaticResetAt ?? counter.updatedAt
            guard let scheduled = mostRecentScheduledReset(for: counter, at: now),
                  scheduled > reference else { return nil }
            return counter.id
        }

        guard !eligibleIDs.isEmpty else { return }
        registerUndoSnapshot(label: "Automatic Reset")

        for id in eligibleIDs {
            guard let index = counters.firstIndex(where: { $0.id == id }) else { continue }
            let before = counters[index].value
            let after = resetValue(for: counters[index])
            counters[index].value = after
            counters[index].lastAutomaticResetAt = now
            counters[index].lastResetReason = "Scheduled"
            counters[index].updatedAt = now
            history.insert(
                TallyHistoryEntry(
                    counterID: id,
                    counterName: counters[index].name,
                    action: "Scheduled Reset",
                    delta: after - before,
                    beforeValue: before,
                    afterValue: after,
                    date: now
                ),
                at: 0
            )
            scheduleResetNotification(for: counters[index])
        }
    }

    private func mostRecentScheduledReset(for counter: TallyCounter, at date: Date) -> Date? {
        let calendar = Calendar.current
        switch counter.resetReminder {
        case .none:
            return nil
        case .daily:
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = counter.resetHour
            components.minute = counter.resetMinute
            components.second = 0
            guard let today = calendar.date(from: components) else { return nil }
            return today <= date ? today : calendar.date(byAdding: .day, value: -1, to: today)
        case .weekly:
            return calendar.nextDate(
                after: date,
                matching: DateComponents(
                    weekday: counter.resetWeekday,
                    hour: counter.resetHour,
                    minute: counter.resetMinute
                ),
                matchingPolicy: .previousTimePreservingSmallerComponents,
                repeatedTimePolicy: .first,
                direction: .backward
            )
        case .monthly:
            return calendar.nextDate(
                after: date,
                matching: DateComponents(
                    day: counter.resetDayOfMonth,
                    hour: counter.resetHour,
                    minute: counter.resetMinute
                ),
                matchingPolicy: .previousTimePreservingSmallerComponents,
                repeatedTimePolicy: .first,
                direction: .backward
            )
        }
    }

    private func notificationDateComponents(for counter: TallyCounter) -> DateComponents {
        let calendar = Calendar.current
        guard let nextReset = nextResetDate(for: counter),
              let warningDate = calendar.date(byAdding: .minute, value: -5, to: nextReset) else {
            return DateComponents()
        }

        switch counter.resetReminder {
        case .none:
            return DateComponents()
        case .daily:
            return calendar.dateComponents([.hour, .minute], from: warningDate)
        case .weekly:
            return calendar.dateComponents([.weekday, .hour, .minute], from: warningDate)
        case .monthly:
            return calendar.dateComponents([.day, .hour, .minute], from: warningDate)
        }
    }

    private func resetNotificationIdentifier(_ counterID: UUID) -> String {
        "tally.reset.\(counterID.uuidString)"
    }
}

private extension DateComponents {
    var isEmpty: Bool {
        calendar == nil &&
        timeZone == nil &&
        era == nil &&
        year == nil &&
        month == nil &&
        day == nil &&
        hour == nil &&
        minute == nil &&
        second == nil &&
        nanosecond == nil &&
        weekday == nil &&
        weekdayOrdinal == nil &&
        quarter == nil &&
        weekOfMonth == nil &&
        weekOfYear == nil &&
        yearForWeekOfYear == nil
    }
}

struct TallySigningCapability: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let availableInAppDBBuild: Bool

    static let all: [TallySigningCapability] = [
        .init(
            id: "local",
            title: "Local counters, sessions, notifications and backups",
            subtitle: "Fully available in the AppDB-safe build.",
            systemImage: "iphone",
            availableInAppDBBuild: true
        ),
        .init(
            id: "shortcuts",
            title: "App Shortcuts",
            subtitle: "Implemented in the main app without an extension target.",
            systemImage: "command",
            availableInAppDBBuild: true
        ),
        .init(
            id: "widgets",
            title: "Widgets and Live Activities",
            subtitle: "Source-ready, but requires a separately signed extension target.",
            systemImage: "rectangle.3.group",
            availableInAppDBBuild: false
        ),
        .init(
            id: "cloud",
            title: "Automatic CloudKit sync",
            subtitle: "Source-ready, but requires iCloud entitlements in the provisioning profile.",
            systemImage: "icloud",
            availableInAppDBBuild: false
        )
    ]
}

struct TallyOnboardingView: View {
    @EnvironmentObject private var store: TallyStore
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let pages: [(String, String, String)] = [
        (
            "Organize your counters",
            "Create folders with their own colors, symbols, steps, and reset presets.",
            "folder.fill.badge.plus"
        ),
        (
            "Pin without removing",
            "Pinned counters remain inside their folder and simply move to the top of that folder.",
            "pin.fill"
        ),
        (
            "AppDB-safe by design",
            "Local notifications, backups, sync packages, Shortcuts, and all core features work without restricted extension entitlements.",
            "checkmark.shield.fill"
        )
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: pages[page].2)
                    .font(.system(size: 72, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                VStack(spacing: 12) {
                    Text(pages[page].0)
                        .font(.largeTitle.weight(.black))
                        .multilineTextAlignment(.center)
                    Text(pages[page].1)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                Spacer()
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: index == page ? 24 : 8, height: 8)
                    }
                }
                Button(page == pages.count - 1 ? "Get Started" : "Continue") {
                    if page == pages.count - 1 {
                        store.preferences.onboardingCompleted = true
                        dismiss()
                    } else {
                        if store.preferences.reducedAnimations {
                            page += 1
                        } else {
                            withAnimation(.snappy) { page += 1 }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                Button("Skip") {
                    store.preferences.onboardingCompleted = true
                    dismiss()
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 18)
            }
            .navigationTitle("Welcome to Tally 2.0")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}
