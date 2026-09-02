import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: TallyStore
    @State private var searchText = ""
    @State private var filter: HistoryFilter = .all

    private var filteredHistory: [TallyHistoryEntry] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.history.filter { entry in
            let matchesSearch = trimmed.isEmpty || entry.counterName.localizedCaseInsensitiveContains(trimmed) || entry.action.localizedCaseInsensitiveContains(trimmed)
            return matchesSearch && filter.includes(entry)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredHistory.isEmpty {
                    ContentUnavailableView(
                        store.history.isEmpty ? "No History Yet" : "No Matches",
                        systemImage: "clock",
                        description: Text(store.history.isEmpty ? "Counter changes will appear here." : "Try a different search or filter.")
                    )
                } else {
                    Section {
                        ForEach(filteredHistory) { entry in
                            HistoryRow(entry: entry)
                        }
                    } header: {
                        Text("\(filteredHistory.count) entries")
                    }
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search history")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(HistoryFilter.allCases) { filter in
                                Label(filter.title, systemImage: filter.systemImage).tag(filter)
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }

                    Button("Clear", role: .destructive) { store.clearHistory() }
                        .disabled(store.history.isEmpty)
                }
            }
        }
    }
}

struct HistoryRow: View {
    let entry: TallyHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.counterName)
                    .font(.headline)
                Spacer()
                Text(entry.action)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(entry.delta >= 0 ? .green : .red)
            }
            HStack {
                Text("\(entry.beforeValue) → \(entry.afterValue)")
                Spacer()
                Text(entry.date, style: .date)
                Text(entry.date, style: .time)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, today, week, positive, negative, resets
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .today: return "Today"
        case .week: return "Last 7 Days"
        case .positive: return "Positive"
        case .negative: return "Negative"
        case .resets: return "Resets"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "clock"
        case .today: return "calendar"
        case .week: return "calendar.badge.clock"
        case .positive: return "plus.circle"
        case .negative: return "minus.circle"
        case .resets: return "arrow.counterclockwise"
        }
    }

    func includes(_ entry: TallyHistoryEntry) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDateInToday(entry.date)
        case .week:
            guard let start = calendar.date(byAdding: .day, value: -7, to: Date()) else { return true }
            return entry.date >= start
        case .positive:
            return entry.delta > 0
        case .negative:
            return entry.delta < 0
        case .resets:
            return entry.action.localizedCaseInsensitiveContains("reset")
        }
    }
}
