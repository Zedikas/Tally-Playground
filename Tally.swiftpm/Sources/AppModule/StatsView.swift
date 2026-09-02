import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var store: TallyStore
    @State private var range: StatsRange = .sevenDays

    private var entries: [TallyHistoryEntry] {
        guard let startDate = range.startDate else { return store.history }
        return store.history.filter { $0.date >= startDate }
    }

    private var totalChange: Int {
        entries.map(\.delta).reduce(0, +)
    }

    private var positiveChange: Int {
        entries.filter { $0.delta > 0 }.map(\.delta).reduce(0, +)
    }

    private var negativeChange: Int {
        abs(entries.filter { $0.delta < 0 }.map(\.delta).reduce(0, +))
    }

    private var activeCounterCount: Int {
        Set(entries.map(\.counterID)).count
    }

    private var goalCounters: [TallyCounter] {
        store.counters.filter { ($0.goal ?? 0) > 0 }
    }

    private var completedGoals: Int {
        goalCounters.filter { counter in
            guard let goal = counter.goal else { return false }
            return counter.value >= goal
        }.count
    }

    private var counterStats: [CounterStatsRowModel] {
        let grouped = Dictionary(grouping: entries, by: \.counterID)
        return grouped.compactMap { counterID, entries in
            let counter = store.counters.first { $0.id == counterID }
            let name = counter?.name ?? entries.first?.counterName ?? "Deleted Counter"
            let color = CounterColor(rawValue: counter?.colorName ?? CounterColor.gray.rawValue) ?? .gray
            let net = entries.map(\.delta).reduce(0, +)
            return CounterStatsRowModel(
                id: counterID,
                name: name,
                group: counter?.displayGroup ?? "History",
                color: color,
                netChange: net,
                changes: entries.count,
                currentStreak: currentStreak(for: counterID)
            )
        }
        .sorted { lhs, rhs in
            if abs(lhs.netChange) == abs(rhs.netChange) {
                return lhs.changes > rhs.changes
            }
            return abs(lhs.netChange) > abs(rhs.netChange)
        }
    }

    private var dailySummaries: [DailySummary] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.date)
        }
        return grouped.map { day, entries in
            DailySummary(
                id: day,
                date: day,
                changes: entries.count,
                netChange: entries.map(\.delta).reduce(0, +),
                counters: Set(entries.map(\.counterID)).count
            )
        }
        .sorted { $0.date > $1.date }
    }

    private var bestStreaks: [CounterStatsRowModel] {
        counterStats
            .filter { $0.currentStreak > 0 }
            .sorted { $0.currentStreak > $1.currentStreak }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Picker("Range", selection: $range) {
                            ForEach(StatsRange.allCases) { range in
                                Text(range.title).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            StatsCard(title: "Changes", value: "\(entries.count)", subtitle: "\(activeCounterCount) active counters", systemImage: "plus.forwardslash.minus")
                            StatsCard(title: "Net", value: signed(totalChange), subtitle: "+\(positiveChange) / −\(negativeChange)", systemImage: "sum")
                            StatsCard(title: "Counters", value: "\(store.counters.count)", subtitle: "\(store.groups.count) groups", systemImage: "number.circle")
                            StatsCard(title: "Goals", value: "\(completedGoals)/\(goalCounters.count)", subtitle: "completed", systemImage: "target")
                        }
                        .padding(.horizontal)

                        if !goalCounters.isEmpty {
                            SectionHeader(title: "Goals", subtitle: "Current progress")
                            VStack(spacing: 10) {
                                ForEach(goalCounters.sorted { ($0.progress ?? 0) > ($1.progress ?? 0) }) { counter in
                                    GoalProgressRow(counter: counter)
                                }
                            }
                            .padding(.horizontal)
                        }

                        if !bestStreaks.isEmpty {
                            SectionHeader(title: "Streaks", subtitle: "Consecutive days with activity")
                            VStack(spacing: 10) {
                                ForEach(bestStreaks.prefix(5)) { stat in
                                    CounterStatsRow(stat: stat, mode: .streak)
                                }
                            }
                            .padding(.horizontal)
                        }

                        if !counterStats.isEmpty {
                            SectionHeader(title: "Top Counters", subtitle: "Ranked by activity in selected range")
                            VStack(spacing: 10) {
                                ForEach(counterStats.prefix(8)) { stat in
                                    CounterStatsRow(stat: stat, mode: .change)
                                }
                            }
                            .padding(.horizontal)
                        }

                        if !dailySummaries.isEmpty {
                            SectionHeader(title: "Daily Summary", subtitle: "Recent activity by day")
                            VStack(spacing: 10) {
                                ForEach(dailySummaries.prefix(14)) { summary in
                                    DailySummaryRow(summary: summary)
                                }
                            }
                            .padding(.horizontal)
                        }

                        if entries.isEmpty {
                            ContentUnavailableView("No Stats Yet", systemImage: "chart.bar.xaxis", description: Text("Make counter changes to build up your dashboard."))
                                .padding(.top, 40)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Stats")
        }
    }

    private var background: some View {
        Group {
            if store.theme == .oled {
                Color.black.ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(.systemBackground), Color.purple.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
    }

    private func currentStreak(for counterID: UUID) -> Int {
        let calendar = Calendar.current
        let activeDays = Set(store.history
            .filter { $0.counterID == counterID && $0.delta > 0 }
            .map { calendar.startOfDay(for: $0.date) })

        var day = calendar.startOfDay(for: Date())
        var streak = 0
        while activeDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

struct StatsCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline.weight(.heavy))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }
}

struct GoalProgressRow: View {
    let counter: TallyCounter

    private var color: CounterColor {
        CounterColor(rawValue: counter.colorName) ?? .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(counter.name, systemImage: counter.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color.color)
                Spacer()
                if let goal = counter.goal {
                    Text("\(counter.value) / \(goal)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: counter.progress ?? 0)
                .tint(color.color)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct CounterStatsRow: View {
    let stat: CounterStatsRowModel
    let mode: CounterStatsRowMode

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(stat.color.color.opacity(0.18))
                .overlay(Image(systemName: mode.systemImage).foregroundStyle(stat.color.color))
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(stat.name)
                    .font(.subheadline.weight(.bold))
                Text(mode == .streak ? stat.group : "\(stat.changes) changes • \(stat.group)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(mode == .streak ? "\(stat.currentStreak)d" : signed(stat.netChange))
                .font(.headline.weight(.heavy).monospacedDigit())
                .foregroundStyle(mode == .streak ? .orange : stat.color.color)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

struct DailySummaryRow: View {
    let summary: DailySummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.date, style: .date)
                    .font(.subheadline.weight(.bold))
                Text("\(summary.changes) changes • \(summary.counters) counters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(summary.netChange > 0 ? "+\(summary.netChange)" : "\(summary.netChange)")
                .font(.headline.weight(.heavy).monospacedDigit())
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

enum StatsRange: String, CaseIterable, Identifiable {
    case today, sevenDays, thirtyDays, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .sevenDays: return "7D"
        case .thirtyDays: return "30D"
        case .all: return "All"
        }
    }

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .today:
            return calendar.startOfDay(for: Date())
        case .sevenDays:
            return calendar.date(byAdding: .day, value: -7, to: Date())
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -30, to: Date())
        case .all:
            return nil
        }
    }
}

struct CounterStatsRowModel: Identifiable {
    var id: UUID
    var name: String
    var group: String
    var color: CounterColor
    var netChange: Int
    var changes: Int
    var currentStreak: Int
}

struct DailySummary: Identifiable {
    var id: Date
    var date: Date
    var changes: Int
    var netChange: Int
    var counters: Int
}

enum CounterStatsRowMode {
    case change, streak

    var systemImage: String {
        switch self {
        case .change: return "chart.line.uptrend.xyaxis"
        case .streak: return "flame.fill"
        }
    }
}
