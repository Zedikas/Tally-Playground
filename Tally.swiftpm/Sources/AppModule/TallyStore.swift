import Foundation
import SwiftUI

@MainActor
final class TallyStore: ObservableObject {
    @Published var counters: [TallyCounter] = [] { didSet { save() } }
    @Published var history: [TallyHistoryEntry] = [] { didSet { save() } }
    @Published var sessions: [TallySession] = [] { didSet { save() } }
    @Published var theme: TallyTheme = .system { didSet { save() } }
    @Published var preferences: TallyPreferences = TallyPreferences() { didSet { save() } }
    @Published private(set) var undoLabel: String?

    private let storageKey = "tally.state.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isRestoringState = false
    private var revisionCounter = 0
    private var undoSnapshots: [UndoSnapshot] = []

    private struct UndoSnapshot {
        let label: String
        let counters: [TallyCounter]
        let folders: [TallyFolder]
        let history: [TallyHistoryEntry]
        let sessions: [TallySession]
        let theme: TallyTheme
        let preferences: TallyPreferences
    }

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
        if counters.isEmpty && history.isEmpty {
            counters = Self.sampleCounters
        }
        ensureFoldersMigrated()
        performAutomaticResets()
        rescheduleAllResetNotifications()
    }

    var activeCounters: [TallyCounter] {
        counters.filter { !$0.isArchived }
    }

    var archivedCounters: [TallyCounter] {
        counters.filter(\.isArchived)
    }

    var activeSessions: [TallySession] {
        sessions.filter(\.isActive).sorted { $0.startedAt > $1.startedAt }
    }

    var finishedSessions: [TallySession] {
        sessions.filter { !$0.isActive }.sorted { $0.startedAt > $1.startedAt }
    }

    var groups: [String] { groups(for: activeCounters) }
    var canUndo: Bool { !undoSnapshots.isEmpty }

    func groups(for counters: [TallyCounter]) -> [String] {
        Array(Set(counters.map(\.displayGroup))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func counters(in group: String) -> [TallyCounter] {
        activeCounters.filter { $0.displayGroup == group }
    }

    func orderedCounters(in folderID: UUID?) -> [TallyCounter] {
        activeCounters
            .filter { $0.folderID == folderID }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                if lhs.sortIndex == rhs.sortIndex { return lhs.createdAt < rhs.createdAt }
                return lhs.sortIndex < rhs.sortIndex
            }
    }

    func registerUndoSnapshot(label: String) {
        guard !isRestoringState else { return }
        let snapshot = UndoSnapshot(
            label: label,
            counters: counters,
            folders: folders,
            history: history,
            sessions: sessions,
            theme: theme,
            preferences: preferences
        )
        undoSnapshots.append(snapshot)
        if undoSnapshots.count > 30 { undoSnapshots.removeFirst(undoSnapshots.count - 30) }
        undoLabel = label
    }

    func undoLastAction() {
        guard let snapshot = undoSnapshots.popLast() else { return }
        isRestoringState = true
        counters = snapshot.counters
        folders = snapshot.folders
        history = snapshot.history
        sessions = snapshot.sessions
        theme = snapshot.theme
        preferences = snapshot.preferences
        isRestoringState = false
        undoLabel = undoSnapshots.last?.label
        save()
        performHaptic(.success)
    }

    @discardableResult
    func addCounter(
        name: String,
        group: String,
        goal: Int?,
        symbol: String,
        color: CounterColor,
        notes: String,
        stepValues: [Int] = [1, 5, 10],
        resetReminder: ResetReminder = .none
    ) -> TallyCounter? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        registerUndoSnapshot(label: "Create Counter")
        let targetFolder = folder(named: group)
        let counter = TallyCounter(
            name: cleanName,
            value: 0,
            goal: goal,
            group: targetFolder?.name ?? "",
            folderID: targetFolder?.id,
            sortIndex: nextCounterSortIndex(in: targetFolder?.id),
            symbol: symbol,
            colorName: color.rawValue,
            notes: notes,
            stepValues: stepValues,
            resetReminder: resetReminder,
            folderColorName: targetFolder?.colorRaw ?? CounterColor.gray.rawValue
        )
        counters.append(counter)
        performHaptic(.success)
        return counter
    }

    func deleteCounter(_ counter: TallyCounter) {
        archiveCounter(counter)
    }

    func archiveCounter(_ counter: TallyCounter) {
        guard let index = counters.firstIndex(where: { $0.id == counter.id }) else { return }
        registerUndoSnapshot(label: "Archive Counter")
        counters[index].isArchived = true
        counters[index].updatedAt = Date()
        cancelResetNotification(for: counter.id)
    }

    func restoreCounter(_ counter: TallyCounter) {
        guard let index = counters.firstIndex(where: { $0.id == counter.id }) else { return }
        registerUndoSnapshot(label: "Restore Counter")
        counters[index].isArchived = false
        counters[index].updatedAt = Date()
        scheduleResetNotification(for: counters[index])
    }

    func permanentlyDeleteCounter(_ counter: TallyCounter) {
        registerUndoSnapshot(label: "Delete Counter")
        counters.removeAll { $0.id == counter.id }
        history.removeAll { $0.counterID == counter.id }
        sessions.removeAll { $0.counterID == counter.id }
        cancelResetNotification(for: counter.id)
    }

    func updateCounter(_ counter: TallyCounter) {
        guard let index = counters.firstIndex(where: { $0.id == counter.id }) else { return }
        registerUndoSnapshot(label: "Edit Counter")
        var updated = normalizedCounter(counter)
        if let folder = folder(id: updated.folderID) ?? folder(named: updated.group) {
            updated.folderID = folder.id
            updated.group = folder.name
            updated.folderColorName = folder.colorRaw
        } else {
            updated.folderID = nil
            updated.group = ""
        }
        updated.updatedAt = Date()
        counters[index] = updated
        scheduleResetNotification(for: updated)
    }

    func duplicateCounter(_ counter: TallyCounter) {
        guard let index = counters.firstIndex(where: { $0.id == counter.id }) else { return }
        registerUndoSnapshot(label: "Duplicate Counter")
        var copy = counter
        copy.id = UUID()
        copy.name = uniqueCopyName(for: counter.name)
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.sortIndex = counter.sortIndex + 0.5
        copy.isArchived = false
        copy.isPinned = false
        copy.isLocked = false
        copy.reachedMilestones = []
        copy.lastAutomaticResetAt = nil
        copy.lastResetReason = nil
        counters.insert(copy, at: min(index + 1, counters.endIndex))
        normalizeCounterSortIndexes(folderID: copy.folderID)
        scheduleResetNotification(for: copy)
    }

    func moveCounter(_ counter: TallyCounter, by offset: Int) {
        let siblings = orderedCounters(in: counter.folderID)
        guard let position = siblings.firstIndex(where: { $0.id == counter.id }) else { return }
        let targetPosition = position + offset
        guard siblings.indices.contains(targetPosition) else { return }
        moveCounter(counter, before: siblings[targetPosition], to: folder(id: counter.folderID))
    }

    func adjust(_ counter: TallyCounter, by delta: Int) {
        guard let index = counters.firstIndex(where: { $0.id == counter.id }), !counters[index].isLocked else { return }
        registerUndoSnapshot(label: delta >= 0 ? "Increase Counter" : "Decrease Counter")
        let before = counters[index].value
        let after = before + delta
        counters[index].value = after
        counters[index].updatedAt = Date()
        history.insert(
            TallyHistoryEntry(
                counterID: counter.id,
                counterName: counters[index].name,
                action: delta >= 0 ? "+\(delta)" : "\(delta)",
                delta: delta,
                beforeValue: before,
                afterValue: after
            ),
            at: 0
        )
        performHaptic(.light)
    }

    func reset(_ counter: TallyCounter) {
        guard let index = counters.firstIndex(where: { $0.id == counter.id }), !counters[index].isLocked else { return }
        registerUndoSnapshot(label: "Reset Counter")
        let before = counters[index].value
        let after = resetValue(for: counters[index])
        counters[index].value = after
        counters[index].lastAutomaticResetAt = Date()
        counters[index].lastResetReason = "Manual"
        counters[index].updatedAt = Date()
        history.insert(
            TallyHistoryEntry(
                counterID: counter.id,
                counterName: counters[index].name,
                action: "Reset",
                delta: after - before,
                beforeValue: before,
                afterValue: after
            ),
            at: 0
        )
        performHaptic(.warning)
    }

    func clearHistory() {
        guard !history.isEmpty else { return }
        registerUndoSnapshot(label: "Clear History")
        history.removeAll()
    }

    @discardableResult
    func startSession(
        counterID: UUID?,
        title: String,
        notes: String,
        goalDuration: TimeInterval? = nil
    ) -> TallySession {
        registerUndoSnapshot(label: "Start Session")
        let counter = counterID.flatMap { id in counters.first { $0.id == id } }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = TallySession(
            title: cleanTitle.isEmpty ? (counter?.name ?? "Counting Session") : cleanTitle,
            counterID: counter?.id,
            counterName: counter?.name ?? "Standalone",
            startedAt: Date(),
            endedAt: nil,
            startValue: counter?.value ?? 0,
            endValue: nil,
            notes: notes,
            goalDuration: goalDuration
        )
        sessions.insert(session, at: 0)
        performHaptic(.success)
        return session
    }

    func pauseSession(_ session: TallySession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }), sessions[index].isActive, !sessions[index].isPaused else { return }
        registerUndoSnapshot(label: "Pause Session")
        sessions[index].pausedAt = Date()
        performHaptic(.selection)
    }

    func resumeSession(_ session: TallySession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }),
              let pausedAt = sessions[index].pausedAt,
              sessions[index].isActive else { return }
        registerUndoSnapshot(label: "Resume Session")
        sessions[index].accumulatedPausedDuration += Date().timeIntervalSince(pausedAt)
        sessions[index].pausedAt = nil
        performHaptic(.selection)
    }

    func endSession(_ session: TallySession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        registerUndoSnapshot(label: "End Session")
        if let pausedAt = sessions[index].pausedAt {
            sessions[index].accumulatedPausedDuration += Date().timeIntervalSince(pausedAt)
            sessions[index].pausedAt = nil
        }
        let counterValue = sessions[index].counterID.flatMap { id in counters.first(where: { $0.id == id })?.value }
        sessions[index].endedAt = Date()
        sessions[index].endValue = counterValue ?? sessions[index].startValue
        performHaptic(.success)
    }

    func cancelSession(_ session: TallySession) {
        guard sessions.contains(where: { $0.id == session.id && $0.isActive }) else { return }
        registerUndoSnapshot(label: "Cancel Session")
        sessions.removeAll { $0.id == session.id && $0.isActive }
    }

    func deleteSession(_ session: TallySession) {
        registerUndoSnapshot(label: "Delete Session")
        sessions.removeAll { $0.id == session.id }
    }

    func activeSession(for counter: TallyCounter) -> TallySession? {
        activeSessions.first { $0.counterID == counter.id }
    }

    func exportJSONURL() -> URL? {
        let backup = makeBackup()
        guard let data = try? encoder.encode(backup) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tally_Backup_\(Self.timestamp()).json")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    func exportSyncPackageURL() -> URL? {
        let backup = makeBackup()
        guard let data = try? encoder.encode(backup) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tally_Sync_\(preferences.deviceID.uuidString.prefix(8))_r\(revisionCounter).tallysync")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    func exportDiagnosticsURL() -> URL? {
        let dictionary: [String: Any] = [
            "schemaVersion": "2.0",
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            "signingMode": preferences.signingMode,
            "counterCount": counters.count,
            "folderCount": folders.count,
            "historyCount": history.count,
            "sessionCount": sessions.count,
            "revision": revisionCounter,
            "deviceID": preferences.deviceID.uuidString,
            "generatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tally_Diagnostics_\(Self.timestamp()).json")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    func exportCSVURL() -> URL? {
        var rows = ["Date,Counter,Action,Before,After,Delta"]
        let formatter = ISO8601DateFormatter()
        for entry in history.reversed() {
            rows.append([
                formatter.string(from: entry.date), entry.counterName, entry.action,
                String(entry.beforeValue), String(entry.afterValue), String(entry.delta)
            ].map(Self.csvEscape).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tally_History_\(Self.timestamp()).csv")
        do { try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    func exportSessionsCSVURL() -> URL? {
        var rows = ["Title,Counter,Started,Ended,DurationSeconds,StartValue,EndValue,Delta,Notes"]
        let formatter = ISO8601DateFormatter()
        for session in sessions.reversed() {
            let fields: [String] = [
                session.title,
                session.counterName,
                formatter.string(from: session.startedAt),
                session.endedAt.map(formatter.string) ?? "",
                String(Int(session.duration)),
                String(session.startValue),
                session.endValue.map(String.init) ?? "",
                session.delta.map(String.init) ?? "",
                session.notes
            ]
            rows.append(fields.map(Self.csvEscape).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tally_Sessions_\(Self.timestamp()).csv")
        do { try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    func previewBackup(from url: URL) throws -> TallyBackupPreview {
        let data = try Data(contentsOf: url)
        let backup = try decoder.decode(TallyBackup.self, from: data)
        return TallyBackupPreview(
            url: url,
            version: backup.version,
            exportedAt: backup.exportedAt,
            counterCount: backup.counters.count,
            activeCounterCount: backup.counters.filter { !$0.isArchived }.count,
            archivedCounterCount: backup.counters.filter(\.isArchived).count,
            folderCount: backup.folders.count,
            historyCount: backup.history.count,
            sessionCount: backup.sessions.count,
            themeTitle: backup.theme.title,
            revision: backup.revision
        )
    }

    func importBackup(from url: URL, replaceExisting: Bool) throws {
        let securityScoped = url.startAccessingSecurityScopedResource()
        defer { if securityScoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let backup = try decoder.decode(TallyBackup.self, from: data)
        registerUndoSnapshot(label: replaceExisting ? "Replace From Backup" : "Merge Backup")

        if replaceExisting {
            isRestoringState = true
            folders = backup.folders
            counters = backup.counters.map(normalizedCounter)
            history = backup.history
            sessions = backup.sessions
            theme = backup.theme
            preferences = backup.preferences
            revisionCounter = max(backup.revision, backup.preferences.syncRevision)
            isRestoringState = false
            ensureFoldersMigrated()
        } else {
            mergeBackup(backup)
        }
        preferences.lastSyncAt = Date()
        rescheduleAllResetNotifications()
        save()
    }

    private func mergeBackup(_ backup: TallyBackup) {
        var folderIDMap: [UUID: UUID] = [:]
        var destinationFolders = folders

        for sourceFolder in backup.folders.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            if let existing = destinationFolders.first(where: { $0.name.localizedCaseInsensitiveCompare(sourceFolder.name) == .orderedSame }) {
                folderIDMap[sourceFolder.id] = existing.id
            } else {
                var imported = sourceFolder
                let oldID = imported.id
                imported.id = UUID()
                imported.name = uniqueFolderName(imported.name, in: destinationFolders)
                imported.sortIndex = (destinationFolders.map(\.sortIndex).max() ?? -1) + 1
                folderIDMap[oldID] = imported.id
                destinationFolders.append(imported)
            }
        }
        folders = destinationFolders

        var counterIDMap: [UUID: UUID] = [:]
        var importedCounters: [TallyCounter] = []
        for source in backup.counters {
            var imported = normalizedCounter(source)
            let oldID = imported.id
            imported.id = UUID()
            counterIDMap[oldID] = imported.id
            imported.createdAt = Date()
            imported.updatedAt = Date()
            imported.name = uniqueImportedName(for: imported.name)
            if let oldFolderID = source.folderID, let mapped = folderIDMap[oldFolderID], let target = folder(id: mapped) {
                imported.folderID = target.id
                imported.group = target.name
                imported.folderColorName = target.colorRaw
                imported.sortIndex = nextCounterSortIndex(in: target.id)
            } else if let legacyFolder = folder(named: source.group) {
                imported.folderID = legacyFolder.id
                imported.group = legacyFolder.name
                imported.folderColorName = legacyFolder.colorRaw
                imported.sortIndex = nextCounterSortIndex(in: legacyFolder.id)
            } else {
                imported.folderID = nil
                imported.group = ""
                imported.folderColorName = CounterColor.gray.rawValue
                imported.sortIndex = nextCounterSortIndex(in: nil)
            }
            importedCounters.append(imported)
        }

        let importedHistory = backup.history.map { entry -> TallyHistoryEntry in
            var imported = entry
            imported.id = UUID()
            imported.counterID = counterIDMap[entry.counterID] ?? entry.counterID
            return imported
        }
        let importedSessions = backup.sessions.map { session -> TallySession in
            var imported = session
            imported.id = UUID()
            if let oldCounterID = session.counterID { imported.counterID = counterIDMap[oldCounterID] }
            return imported
        }

        counters.append(contentsOf: importedCounters)
        history.insert(contentsOf: importedHistory, at: 0)
        sessions.insert(contentsOf: importedSessions, at: 0)
        revisionCounter = max(revisionCounter, backup.revision) + 1
    }

    private func makeBackup() -> TallyBackup {
        var exportedPreferences = preferences
        exportedPreferences.syncRevision = revisionCounter
        return TallyBackup(
            version: "2.0",
            revision: revisionCounter,
            counters: counters,
            folders: folders,
            history: history,
            theme: theme,
            sessions: sessions,
            preferences: exportedPreferences
        )
    }

    private func save() {
        guard !isRestoringState else { return }
        revisionCounter += 1
        let backup = makeBackup()
        guard let data = try? encoder.encode(backup) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let backup = try? decoder.decode(TallyBackup.self, from: data) else { return }
        isRestoringState = true
        if !backup.folders.isEmpty { folders = backup.folders }
        counters = backup.counters.map(normalizedCounter)
        history = backup.history
        sessions = backup.sessions
        theme = backup.theme
        preferences = backup.preferences
        revisionCounter = max(backup.revision, backup.preferences.syncRevision)
        isRestoringState = false
    }

    func normalizedCounter(_ counter: TallyCounter) -> TallyCounter {
        var normalized = counter
        normalized.stepValues = TallyCounter.sanitizedStepValues(counter.stepValues)
        normalized.milestones = TallyCounter.sanitizedMilestones(counter.milestones)
        normalized.reachedMilestones = Array(Set(counter.reachedMilestones)).sorted()
        if CounterColor(rawValue: normalized.folderColorName) == nil && TallyStoredColor.customHex(normalized.folderColorName) == nil {
            normalized.folderColorName = normalized.colorName
        }
        if !normalized.sortIndex.isFinite { normalized.sortIndex = normalized.createdAt.timeIntervalSinceReferenceDate }
        return normalized
    }

    func resetValue(for counter: TallyCounter) -> Int {
        guard counter.carryExcessOnReset, let goal = counter.goal, goal > 0 else { return 0 }
        return max(counter.value - goal, 0)
    }

    private func uniqueCopyName(for baseName: String) -> String {
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Counter" : baseName
        var candidate = "\(base) Copy"
        var number = 2
        while counters.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(base) Copy \(number)"
            number += 1
        }
        return candidate
    }

    private func uniqueImportedName(for baseName: String) -> String {
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Imported Counter" : baseName
        var candidate = base
        guard counters.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) else { return candidate }
        var number = 2
        repeat { candidate = "\(base) Imported \(number)"; number += 1 }
        while counters.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame })
        return candidate
    }

    private func uniqueFolderName(_ baseName: String, in values: [TallyFolder]) -> String {
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Imported Folder" : baseName
        var candidate = base
        var number = 2
        while values.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(base) Imported \(number)"
            number += 1
        }
        return candidate
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    static let sampleCounters: [TallyCounter] = [
        TallyCounter(name: "Water", value: 3, goal: 8, group: "Today", symbol: "drop.fill", colorName: CounterColor.blue.rawValue, notes: "Daily glasses", stepValues: [1, 2, 4], resetReminder: .daily, automaticResetEnabled: true, milestones: [8, 30, 100]),
        TallyCounter(name: "Push-ups", value: 25, goal: 100, group: "Fitness", symbol: "figure.strengthtraining.traditional", colorName: CounterColor.green.rawValue, notes: "", stepValues: [1, 10, 25], resetReminder: .weekly, milestones: [50, 100, 500]),
        TallyCounter(name: "Study reps", value: 12, goal: nil, group: "Focus", symbol: "book.fill", colorName: CounterColor.purple.rawValue, notes: "", stepValues: [1, 5, 10], resetReminder: .none, milestones: [25, 50, 100])
    ]
}
