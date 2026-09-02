import SwiftUI
import UniformTypeIdentifiers

struct TallyFolder: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var colorRaw: String = CounterColor.blue.rawValue
    var defaultCounterColorRaw: String = CounterColor.blue.rawValue
    var defaultSymbol: String = "number.square.fill"
    var defaultStepValues: [Int] = [1, 5, 10]
    var defaultResetReminder: ResetReminder = .none
    var defaultAutomaticReset: Bool = false
    var defaultResetHour: Int = 0
    var defaultResetMinute: Int = 0
    var defaultResetWeekday: Int = 2
    var defaultResetDayOfMonth: Int = 1
    var defaultCarryExcess: Bool = false
    var defaultResetNotification: Bool = false
    var createdAt: Date = Date()
    var sortIndex: Double = Date().timeIntervalSinceReferenceDate

    var cleanName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, colorRaw, defaultCounterColorRaw, defaultSymbol, defaultStepValues
        case defaultResetReminder, defaultAutomaticReset, defaultResetHour, defaultResetMinute
        case defaultResetWeekday, defaultResetDayOfMonth, defaultCarryExcess
        case defaultResetNotification, createdAt, sortIndex
    }

    init(
        id: UUID = UUID(),
        name: String,
        colorRaw: String = CounterColor.blue.rawValue,
        defaultCounterColorRaw: String = CounterColor.blue.rawValue,
        defaultSymbol: String = "number.square.fill",
        defaultStepValues: [Int] = [1, 5, 10],
        defaultResetReminder: ResetReminder = .none,
        defaultAutomaticReset: Bool = false,
        defaultResetHour: Int = 0,
        defaultResetMinute: Int = 0,
        defaultResetWeekday: Int = 2,
        defaultResetDayOfMonth: Int = 1,
        defaultCarryExcess: Bool = false,
        defaultResetNotification: Bool = false,
        createdAt: Date = Date(),
        sortIndex: Double = Date().timeIntervalSinceReferenceDate
    ) {
        self.id = id
        self.name = name
        self.colorRaw = colorRaw
        self.defaultCounterColorRaw = defaultCounterColorRaw
        self.defaultSymbol = defaultSymbol
        self.defaultStepValues = TallyCounter.sanitizedStepValues(defaultStepValues)
        self.defaultResetReminder = defaultResetReminder
        self.defaultAutomaticReset = defaultAutomaticReset
        self.defaultResetHour = min(max(defaultResetHour, 0), 23)
        self.defaultResetMinute = min(max(defaultResetMinute, 0), 59)
        self.defaultResetWeekday = min(max(defaultResetWeekday, 1), 7)
        self.defaultResetDayOfMonth = min(max(defaultResetDayOfMonth, 1), 28)
        self.defaultCarryExcess = defaultCarryExcess
        self.defaultResetNotification = defaultResetNotification
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Folder"
        colorRaw = try container.decodeIfPresent(String.self, forKey: .colorRaw) ?? CounterColor.blue.rawValue
        defaultCounterColorRaw = try container.decodeIfPresent(String.self, forKey: .defaultCounterColorRaw) ?? CounterColor.blue.rawValue
        defaultSymbol = try container.decodeIfPresent(String.self, forKey: .defaultSymbol) ?? "number.square.fill"
        defaultStepValues = TallyCounter.sanitizedStepValues(try container.decodeIfPresent([Int].self, forKey: .defaultStepValues) ?? [1, 5, 10])
        defaultResetReminder = try container.decodeIfPresent(ResetReminder.self, forKey: .defaultResetReminder) ?? .none
        defaultAutomaticReset = try container.decodeIfPresent(Bool.self, forKey: .defaultAutomaticReset) ?? false
        defaultResetHour = min(max(try container.decodeIfPresent(Int.self, forKey: .defaultResetHour) ?? 0, 0), 23)
        defaultResetMinute = min(max(try container.decodeIfPresent(Int.self, forKey: .defaultResetMinute) ?? 0, 0), 59)
        defaultResetWeekday = min(max(try container.decodeIfPresent(Int.self, forKey: .defaultResetWeekday) ?? 2, 1), 7)
        defaultResetDayOfMonth = min(max(try container.decodeIfPresent(Int.self, forKey: .defaultResetDayOfMonth) ?? 1, 1), 28)
        defaultCarryExcess = try container.decodeIfPresent(Bool.self, forKey: .defaultCarryExcess) ?? false
        defaultResetNotification = try container.decodeIfPresent(Bool.self, forKey: .defaultResetNotification) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        sortIndex = try container.decodeIfPresent(Double.self, forKey: .sortIndex) ?? createdAt.timeIntervalSinceReferenceDate
    }
}

extension TallyStore {
    static var foldersStorageKey: String { "tally.folders.v2" }
    private static var legacyFoldersStorageKey: String { "tally.folders.v1" }

    var folders: [TallyFolder] {
        get {
            let defaults = UserDefaults.standard
            let data = defaults.data(forKey: Self.foldersStorageKey) ?? defaults.data(forKey: Self.legacyFoldersStorageKey)
            guard let data, let decoded = try? JSONDecoder().decode([TallyFolder].self, from: data) else { return [] }
            return decoded.sorted { lhs, rhs in
                if lhs.sortIndex == rhs.sortIndex { return lhs.createdAt < rhs.createdAt }
                return lhs.sortIndex < rhs.sortIndex
            }
        }
        set {
            let normalized = newValue.enumerated().map { offset, folder -> TallyFolder in
                var copy = folder
                if !copy.sortIndex.isFinite { copy.sortIndex = Double(offset) }
                return copy
            }
            if let data = try? JSONEncoder().encode(normalized) {
                UserDefaults.standard.set(data, forKey: Self.foldersStorageKey)
            }
            objectWillChange.send()
        }
    }

    func ensureFoldersMigrated() {
        var currentFolders = folders
        let legacyNames = Array(Set(counters.map { $0.group.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        if currentFolders.isEmpty {
            currentFolders = legacyNames.enumerated().map { offset, name in
                let sample = counters.first { $0.group.localizedCaseInsensitiveCompare(name) == .orderedSame }
                return TallyFolder(
                    name: name,
                    colorRaw: sample?.folderColorName ?? CounterColor.blue.rawValue,
                    defaultCounterColorRaw: sample?.colorName ?? CounterColor.blue.rawValue,
                    defaultSymbol: sample?.symbol ?? "number.square.fill",
                    defaultStepValues: sample?.stepValues ?? [1, 5, 10],
                    defaultResetReminder: sample?.resetReminder ?? .none,
                    defaultAutomaticReset: sample?.automaticResetEnabled ?? false,
                    defaultResetHour: sample?.resetHour ?? 0,
                    defaultResetMinute: sample?.resetMinute ?? 0,
                    defaultResetWeekday: sample?.resetWeekday ?? 2,
                    defaultResetDayOfMonth: sample?.resetDayOfMonth ?? 1,
                    defaultCarryExcess: sample?.carryExcessOnReset ?? false,
                    defaultResetNotification: sample?.resetNotificationEnabled ?? false,
                    sortIndex: Double(offset)
                )
            }
        } else {
            for name in legacyNames where !currentFolders.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                currentFolders.append(TallyFolder(name: name, sortIndex: (currentFolders.map(\.sortIndex).max() ?? -1) + 1))
            }
        }

        folders = currentFolders

        var didChangeCounters = false
        for index in counters.indices {
            if let folderID = counters[index].folderID,
               let folder = currentFolders.first(where: { $0.id == folderID }) {
                if counters[index].group != folder.name || counters[index].folderColorName != folder.colorRaw {
                    counters[index].group = folder.name
                    counters[index].folderColorName = folder.colorRaw
                    didChangeCounters = true
                }
                continue
            }

            let rawGroup = counters[index].group.trimmingCharacters(in: .whitespacesAndNewlines)
            if let folder = currentFolders.first(where: { $0.name.localizedCaseInsensitiveCompare(rawGroup) == .orderedSame }) {
                counters[index].folderID = folder.id
                counters[index].group = folder.name
                counters[index].folderColorName = folder.colorRaw
                didChangeCounters = true
            } else if !rawGroup.isEmpty {
                counters[index].group = ""
                counters[index].folderID = nil
                counters[index].folderColorName = CounterColor.gray.rawValue
                didChangeCounters = true
            }
        }
        if didChangeCounters { objectWillChange.send() }
    }

    func folder(id: UUID?) -> TallyFolder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    func folder(named name: String) -> TallyFolder? {
        folders.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    func folder(for counter: TallyCounter) -> TallyFolder? {
        folder(id: counter.folderID) ?? folder(named: counter.group)
    }

    @discardableResult
    func createFolder(_ proposed: TallyFolder) -> Bool {
        let clean = proposed.cleanName
        guard !clean.isEmpty, self.folder(named: clean) == nil else { return false }
        registerUndoSnapshot(label: "Create Folder")
        var copy = proposed
        copy.name = clean
        copy.sortIndex = (folders.map(\.sortIndex).max() ?? -1) + 1
        var value = folders
        value.append(copy)
        folders = value
        return true
    }

    func updateFolder(_ folder: TallyFolder, previousName: String? = nil) {
        var value = folders
        guard let index = value.firstIndex(where: { $0.id == folder.id }) else { return }
        let oldName = previousName ?? value[index].name
        var updated = folder
        updated.name = folder.cleanName
        guard !updated.name.isEmpty else { return }
        guard !value.contains(where: { $0.id != updated.id && $0.name.localizedCaseInsensitiveCompare(updated.name) == .orderedSame }) else { return }
        registerUndoSnapshot(label: "Edit Folder")
        value[index] = updated
        folders = value
        for counterIndex in counters.indices where counters[counterIndex].folderID == updated.id || counters[counterIndex].group.localizedCaseInsensitiveCompare(oldName) == .orderedSame {
            counters[counterIndex].folderID = updated.id
            counters[counterIndex].group = updated.name
            counters[counterIndex].folderColorName = updated.colorRaw
        }
    }

    func deleteFolder(_ folder: TallyFolder, keepCounters: Bool = true) {
        registerUndoSnapshot(label: "Delete Folder")
        var value = folders
        value.removeAll { $0.id == folder.id }
        folders = value
        let related = counters.filter { $0.folderID == folder.id || $0.group.localizedCaseInsensitiveCompare(folder.name) == .orderedSame }
        if keepCounters {
            for index in counters.indices where counters[index].folderID == folder.id || counters[index].group.localizedCaseInsensitiveCompare(folder.name) == .orderedSame {
                counters[index].folderID = nil
                counters[index].group = ""
                counters[index].folderColorName = CounterColor.gray.rawValue
                counters[index].sortIndex = nextCounterSortIndex(in: nil)
            }
        } else {
            let ids = Set(related.map(\.id))
            counters.removeAll { ids.contains($0.id) }
            history.removeAll { ids.contains($0.counterID) }
            sessions.removeAll { session in session.counterID.map(ids.contains) ?? false }
        }
    }

    func moveCounter(_ counter: TallyCounter, to folder: TallyFolder?) {
        guard let index = counters.firstIndex(where: { $0.id == counter.id }) else { return }
        let currentFolderID = counters[index].folderID
        guard currentFolderID != folder?.id else { return }
        registerUndoSnapshot(label: "Move Counter")
        counters[index].folderID = folder?.id
        counters[index].group = folder?.name ?? ""
        counters[index].folderColorName = folder?.colorRaw ?? CounterColor.gray.rawValue
        counters[index].sortIndex = nextCounterSortIndex(in: folder?.id)
        counters[index].updatedAt = Date()
        performHaptic(.selection)
    }

    func moveCounter(_ counter: TallyCounter, before target: TallyCounter, to folder: TallyFolder?) {
        guard counter.id != target.id,
              let sourceIndex = counters.firstIndex(where: { $0.id == counter.id }) else { return }
        registerUndoSnapshot(label: "Reorder Counter")
        counters[sourceIndex].folderID = folder?.id
        counters[sourceIndex].group = folder?.name ?? ""
        counters[sourceIndex].folderColorName = folder?.colorRaw ?? CounterColor.gray.rawValue

        let siblings = counters
            .filter { $0.id != counter.id && $0.folderID == folder?.id && !$0.isArchived }
            .sorted { $0.sortIndex < $1.sortIndex }
        guard let targetPosition = siblings.firstIndex(where: { $0.id == target.id }) else {
            counters[sourceIndex].sortIndex = nextCounterSortIndex(in: folder?.id)
            return
        }
        let previous = targetPosition > 0 ? siblings[targetPosition - 1].sortIndex : siblings[targetPosition].sortIndex - 2
        let next = siblings[targetPosition].sortIndex
        counters[sourceIndex].sortIndex = (previous + next) / 2
        counters[sourceIndex].updatedAt = Date()
        normalizeCounterSortIndexes(folderID: folder?.id)
        performHaptic(.selection)
    }

    func moveFolder(_ folder: TallyFolder, before target: TallyFolder) {
        guard folder.id != target.id else { return }
        var value = folders
        guard let source = value.firstIndex(where: { $0.id == folder.id }) else { return }
        registerUndoSnapshot(label: "Reorder Folder")
        let moving = value.remove(at: source)
        guard let destination = value.firstIndex(where: { $0.id == target.id }) else { return }
        value.insert(moving, at: destination)
        for index in value.indices { value[index].sortIndex = Double(index) }
        folders = value
        performHaptic(.selection)
    }

    func nextCounterSortIndex(in folderID: UUID?) -> Double {
        (counters.filter { !$0.isArchived && $0.folderID == folderID }.map(\.sortIndex).max() ?? -1) + 1
    }

    func normalizeCounterSortIndexes(folderID: UUID?) {
        let orderedIDs = counters
            .filter { !$0.isArchived && $0.folderID == folderID }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.id)
        for (position, id) in orderedIDs.enumerated() {
            if let index = counters.firstIndex(where: { $0.id == id }) {
                counters[index].sortIndex = Double(position)
            }
        }
    }

    @discardableResult
    func quickCreateCounter(in folder: TallyFolder, name: String) -> TallyCounter? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let baseColor = CounterColor(rawValue: folder.defaultCounterColorRaw) ?? .blue
        guard let created = addCounter(
            name: clean,
            group: folder.name,
            goal: nil,
            symbol: folder.defaultSymbol,
            color: baseColor,
            notes: "",
            stepValues: folder.defaultStepValues,
            resetReminder: folder.defaultResetReminder
        ) else { return nil }
        if let index = counters.firstIndex(where: { $0.id == created.id }) {
            counters[index].folderID = folder.id
            counters[index].group = folder.name
            counters[index].sortIndex = nextCounterSortIndex(in: folder.id)
            counters[index].colorName = folder.defaultCounterColorRaw
            counters[index].folderColorName = folder.colorRaw
            counters[index].automaticResetEnabled = folder.defaultAutomaticReset
            counters[index].resetHour = folder.defaultResetHour
            counters[index].resetMinute = folder.defaultResetMinute
            counters[index].resetWeekday = folder.defaultResetWeekday
            counters[index].resetDayOfMonth = folder.defaultResetDayOfMonth
            counters[index].carryExcessOnReset = folder.defaultCarryExcess
            counters[index].resetNotificationEnabled = folder.defaultResetNotification
            scheduleResetNotification(for: counters[index])
        }
        performHaptic(.success)
        return counters.first { $0.id == created.id }
    }

    @discardableResult
    func quickCreateTimer(in folder: TallyFolder, name: String) -> TallyCounter? {
        guard let created = quickCreateCounter(in: folder, name: name) else { return nil }
        startSession(counterID: created.id, title: created.name, notes: "")
        return created
    }
}

struct FolderEditorView: View {
    @EnvironmentObject private var store: TallyStore
    @Environment(\.dismiss) private var dismiss
    let existing: TallyFolder?

    @State private var name: String
    @State private var colorRaw: String
    @State private var counterColorRaw: String
    @State private var symbol: String
    @State private var steps: [Int]
    @State private var reset: ResetReminder
    @State private var automaticReset: Bool
    @State private var resetTime: Date
    @State private var resetWeekday: Int
    @State private var resetDayOfMonth: Int
    @State private var carryExcess: Bool
    @State private var resetNotification: Bool
    @State private var folderCustomColor = Color.blue
    @State private var counterCustomColor = Color.blue
    @State private var showingFolderCustomColor = false
    @State private var showingCounterCustomColor = false

    init(existing: TallyFolder? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _colorRaw = State(initialValue: existing?.colorRaw ?? CounterColor.blue.rawValue)
        _counterColorRaw = State(initialValue: existing?.defaultCounterColorRaw ?? CounterColor.blue.rawValue)
        _symbol = State(initialValue: existing?.defaultSymbol ?? "number.square.fill")
        _steps = State(initialValue: existing?.defaultStepValues ?? [1, 5, 10])
        _reset = State(initialValue: existing?.defaultResetReminder ?? .none)
        _automaticReset = State(initialValue: existing?.defaultAutomaticReset ?? false)
        let hour = existing?.defaultResetHour ?? 0
        let minute = existing?.defaultResetMinute ?? 0
        _resetTime = State(initialValue: Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date())
        _resetWeekday = State(initialValue: existing?.defaultResetWeekday ?? 2)
        _resetDayOfMonth = State(initialValue: existing?.defaultResetDayOfMonth ?? 1)
        _carryExcess = State(initialValue: existing?.defaultCarryExcess ?? false)
        _resetNotification = State(initialValue: existing?.defaultResetNotification ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TallyEditorCard(title: "Folder", systemImage: "folder.fill") {
                        TextField("Folder name", text: $name).font(.title3.weight(.semibold))
                    }

                    TallyEditorCard(title: "Appearance", systemImage: "paintpalette.fill") {
                        StoredColorMenu(title: "Folder Color", systemImage: "folder.fill", rawValue: $colorRaw, customColor: $folderCustomColor, showingCustomPicker: $showingFolderCustomColor)
                        Divider()
                        StoredColorMenu(title: "Counter Color", systemImage: "circle.fill", rawValue: $counterColorRaw, customColor: $counterCustomColor, showingCustomPicker: $showingCounterCustomColor)
                        Divider()
                        Menu {
                            ForEach(CounterSymbolOption.all) { option in
                                Button { symbol = option.symbol } label: { Label(option.title, systemImage: option.symbol) }
                            }
                        } label: {
                            HStack {
                                Text("Default Symbol").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: symbol).foregroundStyle(TallyStoredColor.color(counterColorRaw))
                                Text(CounterSymbolOption.title(for: symbol)).foregroundStyle(.secondary)
                                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    TallyEditorCard(title: "Quick Create Presets", systemImage: "bolt.fill") {
                        StepPresetEditor(steps: $steps)
                        Divider()
                        Picker("Reset Schedule", selection: $reset) {
                            ForEach(ResetReminder.allCases) { item in Text(item.title).tag(item) }
                        }
                        if reset != .none {
                            Divider()
                            DatePicker("Reset Time", selection: $resetTime, displayedComponents: .hourAndMinute)
                            if reset == .weekly {
                                Divider()
                                Picker("Weekday", selection: $resetWeekday) {
                                    ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, title in
                                        Text(title).tag(index + 1)
                                    }
                                }
                            }
                            if reset == .monthly {
                                Divider()
                                Picker("Day of Month", selection: $resetDayOfMonth) {
                                    ForEach(1...28, id: \.self) { Text("\($0)").tag($0) }
                                }
                            }
                            Divider()
                            Toggle("Reset Automatically", isOn: $automaticReset)
                            Toggle("Notify Before Reset", isOn: $resetNotification)
                            Toggle("Carry Value Above Goal", isOn: $carryExcess)
                        }
                        Text("The shortcut beside this folder creates a counter with these presets, or creates one and starts a linked session.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(existing == nil ? "New Folder" : "Edit Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: reset) { _, value in
                if value == .none { automaticReset = false; resetNotification = false }
            }
            .sheet(isPresented: $showingFolderCustomColor) {
                CustomStoredColorSheet(title: "Folder Color", rawValue: $colorRaw, color: $folderCustomColor)
            }
            .sheet(isPresented: $showingCounterCustomColor) {
                CustomStoredColorSheet(title: "Default Counter Color", rawValue: $counterColorRaw, color: $counterCustomColor)
            }
        }
    }

    private func save() {
        var folder = existing ?? TallyFolder(name: name)
        let previousName = folder.name
        let components = Calendar.current.dateComponents([.hour, .minute], from: resetTime)
        folder.name = name
        folder.colorRaw = colorRaw
        folder.defaultCounterColorRaw = counterColorRaw
        folder.defaultSymbol = symbol
        folder.defaultStepValues = TallyCounter.sanitizedStepValues(steps)
        folder.defaultResetReminder = reset
        folder.defaultAutomaticReset = automaticReset && reset != .none
        folder.defaultResetHour = components.hour ?? 0
        folder.defaultResetMinute = components.minute ?? 0
        folder.defaultResetWeekday = resetWeekday
        folder.defaultResetDayOfMonth = resetDayOfMonth
        folder.defaultCarryExcess = carryExcess
        folder.defaultResetNotification = resetNotification && reset != .none
        if existing == nil { _ = store.createFolder(folder) }
        else { store.updateFolder(folder, previousName: previousName) }
        dismiss()
    }
}

struct QuickFolderCreateSheet: View {
    @EnvironmentObject private var store: TallyStore
    @Environment(\.dismiss) private var dismiss
    let folder: TallyFolder
    @State private var name = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 54)).foregroundStyle(TallyStoredColor.color(folder.colorRaw))
                TextField("Counter name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.weight(.semibold))
                    .submitLabel(.done)
                Text("Uses the colors, symbol, steps, and reset presets from \(folder.name).")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button {
                        _ = store.quickCreateCounter(in: folder, name: trimmedName)
                        dismiss()
                    } label: {
                        Label("Create Counter", systemImage: "number.square.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty)

                    Button {
                        _ = store.quickCreateTimer(in: folder, name: trimmedName)
                        dismiss()
                    } label: {
                        Label("Create & Start Timer", systemImage: "timer").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(trimmedName.isEmpty)
                }
            }
            .padding(24)
            .navigationTitle("Quick Create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

// Compatibility for older call sites while the 2.0 UI migrates.
typealias QuickFolderTimerSheet = QuickFolderCreateSheet
