import Foundation
import SwiftUI

struct TallyCounter: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var value: Int
    var goal: Int?

    /// Legacy folder name retained so 1.6/1.7 backups and Android exports remain readable.
    var group: String
    /// Stable relationship used by Tally 2.0. Folder names can now change safely.
    var folderID: UUID?
    var sortIndex: Double

    var symbol: String
    var colorName: CounterColor.RawValue
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var stepValues: [Int]
    var resetReminder: ResetReminder
    var isPinned: Bool
    var isLocked: Bool
    var automaticResetEnabled: Bool
    var lastAutomaticResetAt: Date?
    var milestones: [Int]
    var reachedMilestones: [Int]
    var folderColorName: CounterColor.RawValue

    // Tally 2.0 reset controls. These are deliberately local-only and AppDB-safe.
    var resetHour: Int
    var resetMinute: Int
    var resetWeekday: Int
    var resetDayOfMonth: Int
    var carryExcessOnReset: Bool
    var resetNotificationEnabled: Bool
    var lastResetReason: String?

    init(
        id: UUID = UUID(),
        name: String,
        value: Int,
        goal: Int?,
        group: String,
        folderID: UUID? = nil,
        sortIndex: Double = Date().timeIntervalSinceReferenceDate,
        symbol: String,
        colorName: CounterColor.RawValue,
        notes: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        stepValues: [Int] = [1, 5, 10],
        resetReminder: ResetReminder = .none,
        isPinned: Bool = false,
        isLocked: Bool = false,
        automaticResetEnabled: Bool = false,
        lastAutomaticResetAt: Date? = nil,
        milestones: [Int] = [10, 50, 100],
        reachedMilestones: [Int] = [],
        folderColorName: CounterColor.RawValue? = nil,
        resetHour: Int = 0,
        resetMinute: Int = 0,
        resetWeekday: Int = 2,
        resetDayOfMonth: Int = 1,
        carryExcessOnReset: Bool = false,
        resetNotificationEnabled: Bool = false,
        lastResetReason: String? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.goal = goal
        self.group = group
        self.folderID = folderID
        self.sortIndex = sortIndex
        self.symbol = symbol
        self.colorName = colorName
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.stepValues = Self.sanitizedStepValues(stepValues)
        self.resetReminder = resetReminder
        self.isPinned = isPinned
        self.isLocked = isLocked
        self.automaticResetEnabled = automaticResetEnabled
        self.lastAutomaticResetAt = lastAutomaticResetAt
        self.milestones = Self.sanitizedMilestones(milestones)
        self.reachedMilestones = reachedMilestones
        self.folderColorName = folderColorName ?? colorName
        self.resetHour = min(max(resetHour, 0), 23)
        self.resetMinute = min(max(resetMinute, 0), 59)
        self.resetWeekday = min(max(resetWeekday, 1), 7)
        self.resetDayOfMonth = min(max(resetDayOfMonth, 1), 28)
        self.carryExcessOnReset = carryExcessOnReset
        self.resetNotificationEnabled = resetNotificationEnabled
        self.lastResetReason = lastResetReason
    }

    var displayGroup: String {
        group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unfiled" : group
    }

    var progress: Double? {
        guard let goal, goal > 0 else { return nil }
        return min(max(Double(value) / Double(goal), 0), 1)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, value, goal, group, folderID, sortIndex, symbol, colorName, notes, createdAt, updatedAt
        case isArchived, stepValues, resetReminder, isPinned, isLocked, automaticResetEnabled
        case lastAutomaticResetAt, milestones, reachedMilestones, folderColorName
        case resetHour, resetMinute, resetWeekday, resetDayOfMonth, carryExcessOnReset
        case resetNotificationEnabled, lastResetReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        value = try container.decode(Int.self, forKey: .value)
        goal = try container.decodeIfPresent(Int.self, forKey: .goal)
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? ""
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        sortIndex = try container.decodeIfPresent(Double.self, forKey: .sortIndex) ?? createdAt.timeIntervalSinceReferenceDate
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "number.square.fill"
        colorName = try container.decodeIfPresent(CounterColor.RawValue.self, forKey: .colorName) ?? CounterColor.blue.rawValue
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        stepValues = Self.sanitizedStepValues(try container.decodeIfPresent([Int].self, forKey: .stepValues) ?? [1, 5, 10])
        resetReminder = try container.decodeIfPresent(ResetReminder.self, forKey: .resetReminder) ?? .none
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        automaticResetEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticResetEnabled) ?? false
        lastAutomaticResetAt = try container.decodeIfPresent(Date.self, forKey: .lastAutomaticResetAt)
        milestones = Self.sanitizedMilestones(try container.decodeIfPresent([Int].self, forKey: .milestones) ?? [10, 50, 100])
        reachedMilestones = try container.decodeIfPresent([Int].self, forKey: .reachedMilestones) ?? []
        folderColorName = try container.decodeIfPresent(CounterColor.RawValue.self, forKey: .folderColorName) ?? colorName
        resetHour = min(max(try container.decodeIfPresent(Int.self, forKey: .resetHour) ?? 0, 0), 23)
        resetMinute = min(max(try container.decodeIfPresent(Int.self, forKey: .resetMinute) ?? 0, 0), 59)
        resetWeekday = min(max(try container.decodeIfPresent(Int.self, forKey: .resetWeekday) ?? 2, 1), 7)
        resetDayOfMonth = min(max(try container.decodeIfPresent(Int.self, forKey: .resetDayOfMonth) ?? 1, 1), 28)
        carryExcessOnReset = try container.decodeIfPresent(Bool.self, forKey: .carryExcessOnReset) ?? false
        resetNotificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .resetNotificationEnabled) ?? false
        lastResetReason = try container.decodeIfPresent(String.self, forKey: .lastResetReason)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(goal, forKey: .goal)
        try container.encode(group, forKey: .group)
        try container.encodeIfPresent(folderID, forKey: .folderID)
        try container.encode(sortIndex, forKey: .sortIndex)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(colorName, forKey: .colorName)
        try container.encode(notes, forKey: .notes)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(Self.sanitizedStepValues(stepValues), forKey: .stepValues)
        try container.encode(resetReminder, forKey: .resetReminder)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(automaticResetEnabled, forKey: .automaticResetEnabled)
        try container.encodeIfPresent(lastAutomaticResetAt, forKey: .lastAutomaticResetAt)
        try container.encode(Self.sanitizedMilestones(milestones), forKey: .milestones)
        try container.encode(reachedMilestones, forKey: .reachedMilestones)
        try container.encode(folderColorName, forKey: .folderColorName)
        try container.encode(resetHour, forKey: .resetHour)
        try container.encode(resetMinute, forKey: .resetMinute)
        try container.encode(resetWeekday, forKey: .resetWeekday)
        try container.encode(resetDayOfMonth, forKey: .resetDayOfMonth)
        try container.encode(carryExcessOnReset, forKey: .carryExcessOnReset)
        try container.encode(resetNotificationEnabled, forKey: .resetNotificationEnabled)
        try container.encodeIfPresent(lastResetReason, forKey: .lastResetReason)
    }

    static func sanitizedStepValues(_ values: [Int]) -> [Int] {
        let cleaned = values.filter { $0 > 0 }.map { min($0, 9999) }
        var unique: [Int] = []
        for value in cleaned where !unique.contains(value) { unique.append(value) }
        let result = Array(unique.prefix(3))
        return result.isEmpty ? [1, 5, 10] : result
    }

    static func sanitizedMilestones(_ values: [Int]) -> [Int] {
        Array(Set(values.filter { $0 > 0 }.map { min($0, 9_999_999) })).sorted()
    }
}

struct TallyHistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var counterID: UUID
    var counterName: String
    var action: String
    var delta: Int
    var beforeValue: Int
    var afterValue: Int
    var date: Date = Date()
}

struct TallySession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var counterID: UUID?
    var counterName: String
    var startedAt: Date = Date()
    var endedAt: Date?
    var startValue: Int
    var endValue: Int?
    var notes: String
    var pausedAt: Date?
    var accumulatedPausedDuration: TimeInterval
    var goalDuration: TimeInterval?

    init(
        id: UUID = UUID(),
        title: String,
        counterID: UUID?,
        counterName: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        startValue: Int,
        endValue: Int? = nil,
        notes: String,
        pausedAt: Date? = nil,
        accumulatedPausedDuration: TimeInterval = 0,
        goalDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.counterID = counterID
        self.counterName = counterName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startValue = startValue
        self.endValue = endValue
        self.notes = notes
        self.pausedAt = pausedAt
        self.accumulatedPausedDuration = accumulatedPausedDuration
        self.goalDuration = goalDuration
    }

    var isActive: Bool { endedAt == nil }
    var isPaused: Bool { isActive && pausedAt != nil }
    var duration: TimeInterval {
        let endpoint = endedAt ?? pausedAt ?? Date()
        return max(0, endpoint.timeIntervalSince(startedAt) - accumulatedPausedDuration)
    }
    var delta: Int? { guard let endValue else { return nil }; return endValue - startValue }
    var progress: Double? {
        guard let goalDuration, goalDuration > 0 else { return nil }
        return min(max(duration / goalDuration, 0), 1)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, counterID, counterName, startedAt, endedAt, startValue, endValue, notes
        case pausedAt, accumulatedPausedDuration, goalDuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Counting Session"
        counterID = try container.decodeIfPresent(UUID.self, forKey: .counterID)
        counterName = try container.decodeIfPresent(String.self, forKey: .counterName) ?? "Standalone"
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        startValue = try container.decodeIfPresent(Int.self, forKey: .startValue) ?? 0
        endValue = try container.decodeIfPresent(Int.self, forKey: .endValue)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        accumulatedPausedDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .accumulatedPausedDuration) ?? 0
        goalDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .goalDuration)
    }
}

enum ResetReminder: String, CaseIterable, Codable, Identifiable {
    case none, daily, weekly, monthly
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var subtitle: String {
        switch self {
        case .none: return "No automatic reset schedule"
        case .daily: return "Reset at the selected time each day"
        case .weekly: return "Reset on the selected weekday and time"
        case .monthly: return "Reset on the selected day and time"
        }
    }
    var systemImage: String {
        switch self {
        case .none: return "bell.slash"
        case .daily: return "1.circle.fill"
        case .weekly: return "7.circle.fill"
        case .monthly: return "30.circle.fill"
        }
    }
}

enum CounterColor: String, CaseIterable, Codable, Identifiable {
    case blue, purple, pink, green, orange, red, teal, gray
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return Color(hex: "9000FF") ?? .purple
        case .pink: return Color(hex: "FF7EFF") ?? .pink
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .teal: return .teal
        case .gray: return .gray
        }
    }
}

enum CounterSort: String, CaseIterable, Identifiable {
    case manual, recent, name, value
    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual: return "Manual"
        case .recent: return "Recently Updated"
        case .name: return "Name"
        case .value: return "Value"
        }
    }
    var systemImage: String {
        switch self {
        case .manual: return "line.3.horizontal"
        case .recent: return "clock.arrow.circlepath"
        case .name: return "textformat.abc"
        case .value: return "number"
        }
    }
}

enum TallyTheme: String, CaseIterable, Codable, Identifiable {
    case system, light, dark, oled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Default"
        case .light: return "Light"
        case .dark: return "Dark"
        case .oled: return "OLED Black"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .oled: return .dark
        }
    }
}

struct CounterTemplate: Identifiable, Equatable {
    var id: String; var title: String; var subtitle: String; var name: String; var group: String
    var goal: Int?; var symbol: String; var color: CounterColor; var notes: String
    var stepValues: [Int]; var resetReminder: ResetReminder
    static let allCases: [CounterTemplate] = [
        .init(id: "simple", title: "Simple Tally", subtitle: "Basic count-up tracker", name: "New Counter", group: "", goal: nil, symbol: "number.square.fill", color: .blue, notes: "", stepValues: [1,5,10], resetReminder: .none),
        .init(id: "daily-goal", title: "Daily Goal", subtitle: "Track progress toward a target", name: "Daily Goal", group: "Today", goal: 10, symbol: "checkmark.circle.fill", color: .green, notes: "", stepValues: [1,2,5], resetReminder: .daily),
        .init(id: "water", title: "Water", subtitle: "Daily glasses or bottles", name: "Water", group: "Today", goal: 8, symbol: "drop.fill", color: .blue, notes: "Daily hydration", stepValues: [1,2,4], resetReminder: .daily),
        .init(id: "workout", title: "Workout Reps", subtitle: "Sets, reps, or exercises", name: "Workout Reps", group: "Fitness", goal: 100, symbol: "figure.strengthtraining.traditional", color: .green, notes: "", stepValues: [1,10,25], resetReminder: .weekly),
        .init(id: "inventory", title: "Inventory", subtitle: "Stock or item tracking", name: "Inventory", group: "Inventory", goal: nil, symbol: "shippingbox.fill", color: .orange, notes: "Use + and − to adjust stock.", stepValues: [1,5,20], resetReminder: .monthly),
        .init(id: "score", title: "Game Score", subtitle: "Simple score counter", name: "Player Score", group: "Games", goal: nil, symbol: "gamecontroller.fill", color: .purple, notes: "", stepValues: [1,2,3], resetReminder: .none),
        .init(id: "reading", title: "Reading", subtitle: "Pages, chapters, or sessions", name: "Reading", group: "Focus", goal: 50, symbol: "book.fill", color: .purple, notes: "", stepValues: [1,5,10], resetReminder: .weekly),
        .init(id: "streak", title: "Streak", subtitle: "Count days or wins", name: "Streak", group: "Habits", goal: nil, symbol: "flame.fill", color: .red, notes: "", stepValues: [1,7,30], resetReminder: .daily),
        .init(id: "shopping", title: "Shopping List", subtitle: "Items collected or packed", name: "Items", group: "Shopping", goal: nil, symbol: "cart.fill", color: .teal, notes: "", stepValues: [1,5,10], resetReminder: .none)
    ]
}

struct TallyPreferences: Codable, Equatable {
    var hapticsEnabled: Bool = true
    var reducedAnimations: Bool = false
    var onboardingCompleted: Bool = false
    var collapsedFolderIDs: [UUID] = []
    var deviceID: UUID = UUID()
    var syncRevision: Int = 0
    var lastSyncAt: Date?
    var signingMode: String = "AppDB-safe"

    enum CodingKeys: String, CodingKey {
        case hapticsEnabled, reducedAnimations, onboardingCompleted, collapsedFolderIDs
        case deviceID, syncRevision, lastSyncAt, signingMode
    }

    init(
        hapticsEnabled: Bool = true,
        reducedAnimations: Bool = false,
        onboardingCompleted: Bool = false,
        collapsedFolderIDs: [UUID] = [],
        deviceID: UUID = UUID(),
        syncRevision: Int = 0,
        lastSyncAt: Date? = nil,
        signingMode: String = "AppDB-safe"
    ) {
        self.hapticsEnabled = hapticsEnabled
        self.reducedAnimations = reducedAnimations
        self.onboardingCompleted = onboardingCompleted
        self.collapsedFolderIDs = collapsedFolderIDs
        self.deviceID = deviceID
        self.syncRevision = syncRevision
        self.lastSyncAt = lastSyncAt
        self.signingMode = signingMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        reducedAnimations = try container.decodeIfPresent(Bool.self, forKey: .reducedAnimations) ?? false
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        collapsedFolderIDs = try container.decodeIfPresent([UUID].self, forKey: .collapsedFolderIDs) ?? []
        deviceID = try container.decodeIfPresent(UUID.self, forKey: .deviceID) ?? UUID()
        syncRevision = try container.decodeIfPresent(Int.self, forKey: .syncRevision) ?? 0
        lastSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        signingMode = try container.decodeIfPresent(String.self, forKey: .signingMode) ?? "AppDB-safe"
    }
}

struct TallyBackup: Codable {
    var version: String
    var exportedAt: Date
    var revision: Int
    var counters: [TallyCounter]
    var folders: [TallyFolder]
    var history: [TallyHistoryEntry]
    var theme: TallyTheme
    var sessions: [TallySession]
    var preferences: TallyPreferences

    init(
        version: String = "2.0",
        exportedAt: Date = Date(),
        revision: Int = 0,
        counters: [TallyCounter],
        folders: [TallyFolder] = [],
        history: [TallyHistoryEntry],
        theme: TallyTheme,
        sessions: [TallySession] = [],
        preferences: TallyPreferences = TallyPreferences()
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.revision = revision
        self.counters = counters
        self.folders = folders
        self.history = history
        self.theme = theme
        self.sessions = sessions
        self.preferences = preferences
    }

    enum CodingKeys: String, CodingKey {
        case version, exportedAt, revision, counters, folders, history, theme, sessions, preferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "Unknown"
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        counters = try container.decode([TallyCounter].self, forKey: .counters)
        folders = try container.decodeIfPresent([TallyFolder].self, forKey: .folders) ?? []
        history = try container.decodeIfPresent([TallyHistoryEntry].self, forKey: .history) ?? []
        theme = try container.decodeIfPresent(TallyTheme.self, forKey: .theme) ?? .system
        sessions = try container.decodeIfPresent([TallySession].self, forKey: .sessions) ?? []
        preferences = try container.decodeIfPresent(TallyPreferences.self, forKey: .preferences) ?? TallyPreferences()
    }
}

struct TallyBackupPreview: Identifiable {
    let id = UUID()
    let url: URL
    let version: String
    let exportedAt: Date
    let counterCount: Int
    let activeCounterCount: Int
    let archivedCounterCount: Int
    let folderCount: Int
    let historyCount: Int
    let sessionCount: Int
    let themeTitle: String
    let revision: Int
}
