import SwiftUI

struct CounterDragPreview: View {
    let counter: TallyCounter
    let color: Color
    let reducedMotion: Bool
    @State private var lifted = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: counter.symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(counter.name)
                        .font(.headline.weight(.heavy))
                    if counter.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                    }
                }

                Text("\(counter.value)")
                    .font(.title3.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            Spacer(minLength: 10)

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Color.secondary)
        }
        .padding(14)
        .frame(width: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(color.opacity(0.45), lineWidth: 1.5)
        }
        .scaleEffect(lifted && !reducedMotion ? 1.045 : 1)
        .rotationEffect(.degrees(lifted && !reducedMotion ? 1.1 : 0))
        .shadow(color: Color.black.opacity(0.28), radius: lifted ? 22 : 8, x: 0, y: lifted ? 14 : 4)
        .onAppear {
            withAnimation(reducedMotion ? nil : .interactiveSpring(response: 0.25, dampingFraction: 0.78)) {
                lifted = true
            }
        }
    }
}

struct FolderDragPreview: View {
    let folder: TallyFolder
    let tint: Color
    let reducedMotion: Bool
    @State private var lifted = false

    var body: some View {
        Label(folder.name, systemImage: "folder.fill")
            .font(.headline.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(tint.opacity(0.45), lineWidth: 1.5)
            }
            .scaleEffect(lifted && !reducedMotion ? 1.04 : 1)
            .rotationEffect(.degrees(lifted && !reducedMotion ? -1 : 0))
            .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 10)
            .onAppear {
                withAnimation(reducedMotion ? nil : .interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                    lifted = true
                }
            }
    }
}

struct StatPill: View {
    @EnvironmentObject private var store: TallyStore
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.secondary)

            Text(value)
                .font(.title2.weight(.black))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            store.theme == .oled ? Color(white: 0.035) : Color.clear,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct CounterCard: View {
    @EnvironmentObject private var store: TallyStore
    let counter: TallyCounter
    var showsDragHandle = false
    let onEditExactValue: () -> Void

    @State private var showingEdit = false
    @State private var showingResetConfirmation = false
    @State private var showingArchiveConfirmation = false
    @State private var showingDeleteConfirmation = false

    private var color: Color {
        TallyStoredColor.color(counter.colorName)
    }

    private var activeSession: TallySession? {
        store.activeSession(for: counter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                NavigationLink {
                    CounterDetailView(counterID: counter.id)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: counter.symbol)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(color)
                            .frame(width: 44, height: 44)
                            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(counter.name)
                                    .font(.headline.weight(.heavy))
                                    .foregroundStyle(Color.primary)

                                if counter.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption)
                                }

                                if counter.isLocked {
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                }

                                if let session = activeSession {
                                    Image(systemName: session.isPaused ? "pause.circle.fill" : "timer.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.orange)
                                }
                            }

                            if let goal = counter.goal, goal > 0 {
                                Text("Goal: \(counter.value) / \(goal)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.secondary)
                            } else if !counter.notes.isEmpty {
                                Text(counter.notes)
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                                    .lineLimit(1)
                            }

                            if counter.resetReminder != .none {
                                Label(
                                    store.resetScheduleDescription(for: counter),
                                    systemImage: counter.resetReminder.systemImage
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onEditExactValue) {
                    Text("\(counter.value)")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(color)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(store.preferences.reducedAnimations ? nil : .snappy, value: counter.value)
                }
                .buttonStyle(.plain)
                .disabled(counter.isLocked)
            }

            if let progress = counter.progress {
                ProgressView(value: progress)
                    .tint(color)
            }

            if let session = activeSession, let progress = session.progress {
                ProgressView(value: progress)
                    .tint(Color.orange)
            }

            HStack(spacing: 8) {
                StepButton(title: "−1", isDisabled: counter.isLocked) {
                    store.safeAdjust(counter, by: -1)
                }

                ForEach(counter.stepValues, id: \.self) { step in
                    StepButton(title: "+\(step)", isDisabled: counter.isLocked) {
                        store.safeAdjust(counter, by: step)
                    }
                }

                Menu {
                    Button(
                        counter.isPinned ? "Unpin" : "Pin in Folder",
                        systemImage: counter.isPinned ? "pin.slash" : "pin"
                    ) {
                        store.togglePinned(counter)
                    }

                    Button(
                        counter.isLocked ? "Unlock" : "Lock",
                        systemImage: counter.isLocked ? "lock.open" : "lock"
                    ) {
                        store.toggleLocked(counter)
                    }

                    Button("Exact Value", systemImage: "number.square") {
                        onEditExactValue()
                    }
                    .disabled(counter.isLocked)

                    if let session = activeSession {
                        if session.isPaused {
                            Button("Resume Session", systemImage: "play.circle") {
                                store.resumeSession(session)
                            }
                        } else {
                            Button("Pause Session", systemImage: "pause.circle") {
                                store.pauseSession(session)
                            }
                        }

                        Button("End Session", systemImage: "stop.circle") {
                            store.endSession(session)
                        }
                    } else {
                        Button("Start Session", systemImage: "timer") {
                            store.startSession(counterID: counter.id, title: counter.name, notes: "")
                        }
                    }

                    Divider()

                    Button("Edit", systemImage: "pencil") {
                        showingEdit = true
                    }

                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        store.duplicateCounter(counter)
                    }

                    Menu("Reorder", systemImage: "arrow.up.arrow.down") {
                        Button("Move Up", systemImage: "arrow.up") {
                            store.moveCounter(counter, by: -1)
                        }
                        Button("Move Down", systemImage: "arrow.down") {
                            store.moveCounter(counter, by: 1)
                        }
                    }

                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("+100", systemImage: "plus.circle") {
                            store.safeAdjust(counter, by: 100)
                        }
                        .disabled(counter.isLocked)

                        Button("Reset", systemImage: "arrow.counterclockwise", role: .destructive) {
                            showingResetConfirmation = true
                        }
                        .disabled(counter.isLocked)

                        Button("Archive", systemImage: "archivebox", role: .destructive) {
                            showingArchiveConfirmation = true
                        }
                    }

                    Divider()

                    Button("Delete", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.heavy))
                        .frame(width: 38, height: 32)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            store.theme == .oled ? Color(white: 0.035) : Color.clear,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            if showsDragHandle {
                Capsule()
                    .fill(Color.secondary.opacity(0.34))
                    .frame(width: 32, height: 4)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .confirmationDialog("Reset \(counter.name)?", isPresented: $showingResetConfirmation) {
            Button("Reset Counter", role: .destructive) {
                store.safeReset(counter)
            }
        }
        .confirmationDialog("Archive \(counter.name)?", isPresented: $showingArchiveConfirmation) {
            Button("Archive Counter", role: .destructive) {
                store.archiveCounter(counter)
            }
        }
        .confirmationDialog("Delete \(counter.name) permanently?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                store.permanentlyDeleteCounter(counter)
            }
        } message: {
            Text("This removes the counter, history, and linked sessions. You can use Undo until the app closes.")
        }
        .sheet(isPresented: $showingEdit) {
            CounterEditorView(mode: .edit(counter))
        }
    }
}

struct StepButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.heavy))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isDisabled)
    }
}
