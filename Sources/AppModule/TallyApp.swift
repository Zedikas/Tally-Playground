import SwiftUI
import Foundation

// MARK: - Models

struct TallyCounter: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var value: Int = 0
    var goal: Int? = nil
    var folder: String = ""
    var symbol: String = "number.square.fill"
    var color: CounterColor = .blue
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isPinned: Bool = false
    var isArchived: Bool = false
    var step: Int = 1

    var progress: Double? {
        guard let goal, goal > 0 else { return nil }
        return min(max(Double(value) / Double(goal), 0), 1)
    }
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var counterID: UUID
    var counterName: String
    var delta: Int
    var before: Int
    var after: Int
    var date = Date()
}

enum CounterColor: String, CaseIterable, Codable, Identifiable {
    case blue, purple, pink, green, orange, red, teal, gray
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .teal: .teal
        case .gray: .gray
        }
    }
}

enum TallyTheme: String, CaseIterable, Codable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

// MARK: - Store

@MainActor
final class TallyStore: ObservableObject {
    @Published var counters: [TallyCounter] = [] { didSet { save() } }
    @Published var history: [HistoryEntry] = [] { didSet { save() } }
    @Published var theme: TallyTheme = .system { didSet { save() } }

    private let countersKey = "tally.playground.counters"
    private let historyKey = "tally.playground.history"
    private let themeKey = "tally.playground.theme"

    init() { load() }

    func addCounter(name: String, folder: String = "", goal: Int? = nil, color: CounterColor = .blue) {
        let counter = TallyCounter(name: name.isEmpty ? "New Counter" : name, goal: goal, folder: folder, color: color)
        counters.insert(counter, at: 0)
    }

    func delete(at offsets: IndexSet, from visible: [TallyCounter]) {
        let ids = offsets.map { visible[$0].id }
        counters.removeAll { ids.contains($0.id) }
    }

    func togglePin(_ counter: TallyCounter) {
        guard let i = counters.firstIndex(where: { $0.id == counter.id }) else { return }
        counters[i].isPinned.toggle()
        counters[i].updatedAt = Date()
    }

    func update(_ counter: TallyCounter) {
        guard let i = counters.firstIndex(where: { $0.id == counter.id }) else { return }
        counters[i] = counter
        counters[i].updatedAt = Date()
    }

    func change(_ counter: TallyCounter, by amount: Int) {
        guard let i = counters.firstIndex(where: { $0.id == counter.id }) else { return }
        let old = counters[i].value
        counters[i].value += amount
        counters[i].updatedAt = Date()
        history.insert(HistoryEntry(counterID: counter.id, counterName: counter.name, delta: amount, before: old, after: counters[i].value), at: 0)
        if history.count > 1000 { history.removeLast(history.count - 1000) }
    }

    func reset(_ counter: TallyCounter) {
        let amount = -counter.value
        guard amount != 0 else { return }
        change(counter, by: amount)
    }

    func folders() -> [String] {
        Array(Set(counters.map { $0.folder }.filter { !$0.isEmpty })).sorted()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(counters) { UserDefaults.standard.set(data, forKey: countersKey) }
        if let data = try? encoder.encode(history) { UserDefaults.standard.set(data, forKey: historyKey) }
        UserDefaults.standard.set(theme.rawValue, forKey: themeKey)
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: countersKey), let value = try? decoder.decode([TallyCounter].self, from: data) { counters = value }
        if let data = UserDefaults.standard.data(forKey: historyKey), let value = try? decoder.decode([HistoryEntry].self, from: data) { history = value }
        if let raw = UserDefaults.standard.string(forKey: themeKey), let value = TallyTheme(rawValue: raw) { theme = value }
    }
}

// MARK: - App

@main
struct TallyApp: App {
    @StateObject private var store = TallyStore()

    var body: some Scene {
        WindowGroup {
            TallyMainView()
                .environmentObject(store)
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Main UI

struct TallyMainView: View {
    @EnvironmentObject private var store: TallyStore
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            CountersView()
                .tabItem { Label("Counters", systemImage: "number.square.fill") }
                .tag(0)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(1)
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
    }
}

struct CountersView: View {
    @EnvironmentObject private var store: TallyStore
    @State private var showingAdd = false
    @State private var editing: TallyCounter?
    @State private var search = ""
    @State private var folder = "All"

    private var visible: [TallyCounter] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.counters
            .filter { folder == "All" || $0.folder == folder }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .filter { !$0.isArchived }
            .sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.updatedAt > b.updatedAt
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visible.isEmpty {
                    ContentUnavailableView("No Counters", systemImage: "number.square", description: Text("Tap + to create your first counter."))
                } else {
                    List {
                        if store.folders().count > 0 {
                            Section {
                                Picker("Folder", selection: $folder) {
                                    Text("All").tag("All")
                                    ForEach(store.folders(), id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                        Section {
                            ForEach(visible) { counter in
                                CounterRow(counter: counter, edit: { editing = counter })
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button { store.togglePin(counter) } label: {
                                            Label(counter.isPinned ? "Unpin" : "Pin", systemImage: counter.isPinned ? "pin.slash" : "pin")
                                        }
                                    }
                                    .contextMenu {
                                        Button { editing = counter } label: { Label("Edit", systemImage: "pencil") }
                                        Button { store.reset(counter) } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                                        Button { store.togglePin(counter) } label: { Label(counter.isPinned ? "Unpin" : "Pin", systemImage: "pin") }
                                        Button(role: .destructive) {
                                            store.counters.removeAll { $0.id == counter.id }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                            }
                            .onDelete { store.delete(at: $0, from: visible) }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Tally")
            .searchable(text: $search, prompt: "Search counters")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) { CounterEditor(counter: nil) }
            .sheet(item: $editing) { CounterEditor(counter: $0) }
        }
    }
}

struct CounterRow: View {
    @EnvironmentObject private var store: TallyStore
    let counter: TallyCounter
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: counter.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(counter.color.color)
                .frame(width: 34, height: 34)
                .background(counter.color.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(counter.name).font(.headline)
                    if counter.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                }
                if !counter.folder.isEmpty { Text(counter.folder).font(.caption).foregroundStyle(.secondary) }
                if let progress = counter.progress {
                    ProgressView(value: progress)
                        .tint(counter.color.color)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                Text(counter.value.formatted()).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                HStack(spacing: 8) {
                    Button { store.change(counter, by: -counter.step) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain)
                    Button { store.change(counter, by: counter.step) } label: { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.plain)
                }
                .foregroundStyle(counter.color.color)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
    }
}

struct CounterEditor: View {
    @EnvironmentObject private var store: TallyStore
    @Environment(\.dismiss) private var dismiss
    let original: TallyCounter?
    @State private var name: String
    @State private var folder: String
    @State private var goal: String
    @State private var step: Int
    @State private var color: CounterColor
    @State private var symbol: String
    @State private var notes: String

    init(counter: TallyCounter?) {
        original = counter
        _name = State(initialValue: counter?.name ?? "")
        _folder = State(initialValue: counter?.folder ?? "")
        _goal = State(initialValue: counter?.goal.map(String.init) ?? "")
        _step = State(initialValue: counter?.step ?? 1)
        _color = State(initialValue: counter?.color ?? .blue)
        _symbol = State(initialValue: counter?.symbol ?? "number.square.fill")
        _notes = State(initialValue: counter?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Counter") {
                    TextField("Name", text: $name)
                    TextField("Folder (optional)", text: $folder)
                    TextField("Goal (optional)", text: $goal).keyboardType(.numberPad)
                    Stepper("Step: \(step)", value: $step, in: 1...1000)
                }
                Section("Appearance") {
                    Picker("Color", selection: $color) {
                        ForEach(CounterColor.allCases) { c in Text(c.title).tag(c) }
                    }
                    TextField("SF Symbol", text: $symbol)
                    HStack { Image(systemName: symbol.isEmpty ? "number.square.fill" : symbol).foregroundStyle(color.color); Text("Preview") }
                }
                Section("Notes") { TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8) }
                if original != nil {
                    Section {
                        Button(role: .destructive) {
                            if let id = original?.id { store.counters.removeAll { $0.id == id } }
                            dismiss()
                        } label: { Label("Delete Counter", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(original == nil ? "New Counter" : "Edit Counter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func save() {
        let parsedGoal = Int(goal.trimmingCharacters(in: .whitespacesAndNewlines))
        if var counter = original {
            counter.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            counter.folder = folder.trimmingCharacters(in: .whitespacesAndNewlines)
            counter.goal = parsedGoal
            counter.step = step
            counter.color = color
            counter.symbol = symbol.isEmpty ? "number.square.fill" : symbol
            counter.notes = notes
            store.update(counter)
        } else {
            store.addCounter(name: name.trimmingCharacters(in: .whitespacesAndNewlines), folder: folder.trimmingCharacters(in: .whitespacesAndNewlines), goal: parsedGoal, color: color)
            if let last = store.counters.first {
                var created = last
                created.step = step
                created.symbol = symbol.isEmpty ? "number.square.fill" : symbol
                created.notes = notes
                store.update(created)
            }
        }
        dismiss()
    }
}

extension CounterEditor {
    init(counter: TallyCounter?) { self.init(counter: counter, original: counter) }
    private init(counter: TallyCounter?, original: TallyCounter?) {
        self.original = original
        _name = State(initialValue: counter?.name ?? "")
        _folder = State(initialValue: counter?.folder ?? "")
        _goal = State(initialValue: counter?.goal.map(String.init) ?? "")
        _step = State(initialValue: counter?.step ?? 1)
        _color = State(initialValue: counter?.color ?? .blue)
        _symbol = State(initialValue: counter?.symbol ?? "number.square.fill")
        _notes = State(initialValue: counter?.notes ?? "")
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject private var store: TallyStore
    var body: some View {
        NavigationStack {
            Group {
                if store.history.isEmpty {
                    ContentUnavailableView("No History", systemImage: "clock.arrow.circlepath", description: Text("Your counter changes will appear here."))
                } else {
                    List(store.history) { entry in
                        HStack {
                            Image(systemName: entry.delta >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(entry.delta >= 0 ? .green : .red)
                            VStack(alignment: .leading) {
                                Text(entry.counterName).font(.headline)
                                Text(entry.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.delta >= 0 ? "+\(entry.delta)" : "\(entry.delta)")
                                .font(.headline.monospacedDigit())
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !store.history.isEmpty {
                    Button("Clear") { store.history.removeAll() }
                }
            }
        }
    }
}

// MARK: - Statistics

struct StatsView: View {
    @EnvironmentObject private var store: TallyStore
    var total: Int { store.counters.reduce(0) { $0 + $1.value } }
    var changes: Int { store.history.reduce(0) { $0 + $1.delta } }
    var body: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    StatRow(title: "Counters", value: store.counters.count.formatted(), icon: "number.square.fill")
                    StatRow(title: "Total", value: total.formatted(), icon: "sum")
                    StatRow(title: "Changes", value: store.history.count.formatted(), icon: "arrow.up.arrow.down")
                    StatRow(title: "Net Change", value: changes.formatted(), icon: "chart.line.uptrend.xyaxis")
                }
                Section("Counters") {
                    ForEach(store.counters) { counter in
                        HStack {
                            Image(systemName: counter.symbol).foregroundStyle(counter.color.color)
                            Text(counter.name)
                            Spacer()
                            Text(counter.value.formatted()).bold().monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Stats")
        }
    }
}

struct StatRow: View {
    let title: String; let value: String; let icon: String
    var body: some View {
        HStack {
            Image(systemName: icon).frame(width: 26).foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Text(value).font(.headline.monospacedDigit())
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var store: TallyStore
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $store.theme) {
                        ForEach(TallyTheme.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Data") {
                    LabeledContent("Counters", value: store.counters.count.formatted())
                    LabeledContent("History entries", value: store.history.count.formatted())
                    Button("Reset All Data", role: .destructive) {
                        store.counters.removeAll()
                        store.history.removeAll()
                    }
                }
                Section("About") {
                    LabeledContent("Tally", value: "2.0 Playground")
                    Text("This is the Swift Playgrounds edition of Tally. Data is stored locally on this device using UserDefaults.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
