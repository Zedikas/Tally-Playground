import SwiftUI

struct SessionsView: View {
    @EnvironmentObject private var store: TallyStore
    @State private var showingNewSession = false

    var body: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            SessionStatCard(title: "Active", value: "\(store.activeSessions.count)", systemImage: "timer")
                            SessionStatCard(title: "Completed", value: "\(store.finishedSessions.count)", systemImage: "checkmark.seal")
                        }
                        .padding(.horizontal)

                        Button { showingNewSession = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "play.circle.fill").font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Start Session").font(.headline.weight(.heavy))
                                    Text("Track a standalone timer or link it to a counter.").font(.caption).opacity(0.82)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity)
                            .background(.tint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)

                        if store.activeSessions.isEmpty, let last = store.finishedSessions.first {
                            Button {
                                let session = store.startSession(
                                    counterID: last.counterID,
                                    title: last.title,
                                    notes: last.notes,
                                    goalDuration: last.goalDuration
                                )
                                Task { await TallyFullSigningBridge.shared.startLiveActivity(for: session, store: store) }
                            } label: {
                                Label("Resume Last Session", systemImage: "arrow.clockwise.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(15)
                            }
                            .buttonStyle(.bordered)
                            .padding(.horizontal)
                        }

                        if !store.activeSessions.isEmpty {
                            SectionHeader(title: "Active Sessions", subtitle: "Pause, resume, or finish at any time")
                            VStack(spacing: 10) {
                                ForEach(store.activeSessions) { session in
                                    ActiveSessionRow(session: session)
                                }
                            }
                            .padding(.horizontal)
                        }

                        if !store.finishedSessions.isEmpty {
                            SectionHeader(title: "Recent Sessions", subtitle: "Finished counting blocks")
                            VStack(spacing: 10) {
                                ForEach(store.finishedSessions.prefix(20)) { session in
                                    FinishedSessionRow(session: session)
                                }
                            }
                            .padding(.horizontal)
                        }

                        if store.sessions.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "timer.circle").font(.system(size: 70)).foregroundStyle(.secondary)
                                Text("No Sessions Yet").font(.title2.weight(.heavy))
                                Text("Start a focused timing block from here or use Quick Create beside a folder.")
                                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.top, 52).padding(.horizontal, 28)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewSession = true } label: { Label("Start", systemImage: "plus.circle.fill") }
                }
            }
            .sheet(isPresented: $showingNewSession) { NewSessionView() }
        }
    }

    private var background: some View {
        Group {
            if store.theme == .oled { Color.black.ignoresSafeArea() }
            else if store.theme == .dark { Color(red: 0.055, green: 0.055, blue: 0.065).ignoresSafeArea() }
            else {
                LinearGradient(colors: [Color(.systemBackground), Color.orange.opacity(0.06)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            }
        }
    }
}

struct NewSessionView: View {
    @EnvironmentObject private var store: TallyStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var selectedCounterID: UUID?
    @State private var goalMinutesText = ""

    private var selectedCounterName: String {
        guard let selectedCounterID,
              let counter = store.activeCounters.first(where: { $0.id == selectedCounterID }) else { return "Standalone" }
        return counter.name
    }

    private var goalDuration: TimeInterval? {
        guard let minutes = Double(goalMinutesText), minutes > 0 else { return nil }
        return minutes * 60
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TallyEditorCard(title: "Session", systemImage: "timer") {
                        TextField("Session name", text: $title)
                            .font(.title3.weight(.semibold))
                        Divider()
                        Menu {
                            Button { selectedCounterID = nil } label: {
                                Label("Standalone", systemImage: selectedCounterID == nil ? "checkmark" : "timer")
                            }
                            if !store.activeCounters.isEmpty { Divider() }
                            ForEach(store.activeCounters) { counter in
                                Button { selectedCounterID = counter.id } label: {
                                    Label(counter.name, systemImage: selectedCounterID == counter.id ? "checkmark" : counter.symbol)
                                }
                            }
                        } label: {
                            HStack {
                                Text("Counter").foregroundStyle(.primary)
                                Spacer()
                                Text(selectedCounterName).foregroundStyle(.secondary).lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        TextField("Optional goal in minutes", text: $goalMinutesText)
                            .keyboardType(.decimalPad)
                    }

                    TallyEditorCard(title: "Notes", systemImage: "note.text") {
                        TextField("Optional notes", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                        Text("Linked sessions record the counter value when they begin and end. Sessions can be paused without affecting elapsed time.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let session = store.startSession(
                            counterID: selectedCounterID,
                            title: title,
                            notes: notes,
                            goalDuration: goalDuration
                        )
                        Task { await TallyFullSigningBridge.shared.startLiveActivity(for: session, store: store) }
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ActiveSessionRow: View {
    @EnvironmentObject private var store: TallyStore
    let session: TallySession
    @State private var showingCancelConfirmation = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(.orange.opacity(0.18))
                        .overlay(Image(systemName: session.isPaused ? "pause.fill" : "timer").foregroundStyle(.orange))
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.title).font(.headline)
                        Text("\(session.counterName) • \(session.isPaused ? "Paused" : "Running")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(formatDuration(session.duration))
                            .font(.title3.weight(.heavy).monospacedDigit())
                    }
                    Spacer()
                    Menu {
                        if session.isPaused {
                            Button("Resume Session", systemImage: "play.circle") { resume() }
                        } else {
                            Button("Pause Session", systemImage: "pause.circle") { pause() }
                        }
                        Button("End Session", systemImage: "stop.circle") { finish() }
                        Button("Cancel Session", systemImage: "xmark.circle", role: .destructive) { showingCancelConfirmation = true }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                }

                if let progress = session.progress {
                    ProgressView(value: progress).tint(.orange)
                    if let goal = session.goalDuration {
                        Text("Goal \(formatDuration(goal))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button(session.isPaused ? "Resume" : "Pause") {
                        session.isPaused ? resume() : pause()
                    }
                    .buttonStyle(.bordered)
                    Button("Finish") { finish() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .confirmationDialog("Cancel session?", isPresented: $showingCancelConfirmation) {
            Button("Cancel Session", role: .destructive) { cancel() }
        } message: { Text("Canceling removes this active session without saving a summary.") }
    }

    private func pause() {
        store.pauseSession(session)
        Task { await TallyFullSigningBridge.shared.updateLiveActivities(from: store) }
    }

    private func resume() {
        store.resumeSession(session)
        Task { await TallyFullSigningBridge.shared.updateLiveActivities(from: store) }
    }

    private func finish() {
        let id = session.id
        store.endSession(session)
        Task { await TallyFullSigningBridge.shared.endLiveActivity(sessionID: id, store: store) }
    }

    private func cancel() {
        let id = session.id
        store.cancelSession(session)
        Task { await TallyFullSigningBridge.shared.endLiveActivity(sessionID: id, store: store) }
    }
}

struct FinishedSessionRow: View {
    @EnvironmentObject private var store: TallyStore
    let session: TallySession
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(.blue.opacity(0.16)).overlay(Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title).font(.headline)
                Text("\(session.counterName) • \(session.startedAt, style: .date)").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(formatDuration(session.duration))
                    if let delta = session.delta { Text(delta >= 0 ? "+\(delta)" : "\(delta)") }
                    if let goal = session.goalDuration, session.duration >= goal {
                        Label("Goal", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                .font(.subheadline.weight(.bold).monospacedDigit())
            }
            Spacer()
            Menu {
                Button("Start Again", systemImage: "arrow.clockwise") {
                    let restarted = store.startSession(
                        counterID: session.counterID,
                        title: session.title,
                        notes: session.notes,
                        goalDuration: session.goalDuration
                    )
                    Task { await TallyFullSigningBridge.shared.startLiveActivity(for: restarted, store: store) }
                }
                Button("Delete Session", systemImage: "trash", role: .destructive) { showingDeleteConfirmation = true }
            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .confirmationDialog("Delete session?", isPresented: $showingDeleteConfirmation) {
            Button("Delete Session", role: .destructive) { store.deleteSession(session) }
        }
    }
}

struct SessionStatCard: View {
    let title: String
    let value: String
    let systemImage: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 30, weight: .black, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private func formatDuration(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval))
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let remaining = seconds % 60
    if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remaining) }
    return String(format: "%02d:%02d", minutes, remaining)
}
