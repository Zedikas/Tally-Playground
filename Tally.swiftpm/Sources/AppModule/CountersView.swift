import SwiftUI

struct CountersView: View {
    @EnvironmentObject private var store: TallyStore

    @State private var showingAddCounter = false
    @State private var showingAddFolder = false
    @State private var editingFolder: TallyFolder?
    @State private var quickCreateFolder: TallyFolder?
    @State private var exactValueCounter: TallyCounter?
    @State private var searchText = ""
    @State private var sort: CounterSort = .manual

    @State private var draggingCounterID: UUID?
    @State private var targetedFolderID: UUID?
    @State private var targetedCounterID: UUID?
    @State private var isUnfiledTargeted = false
    @State private var cleanupTask: Task<Void, Never>?
    @State private var expandTask: Task<Void, Never>?

    @AppStorage("tally.collapsedFolders.v17") private var legacyCollapsedFoldersRaw = ""

    private var motion: Animation? {
        store.preferences.reducedAnimations
            ? nil
            : .interactiveSpring(response: 0.28, dampingFraction: 0.84, blendDuration: 0.12)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        quickStats

                        if hasFiledCounters {
                            unfiledDropTarget
                        }

                        ForEach(visibleFolders) { folder in
                            folderSection(folder)
                        }

                        if !unfiledCounters.isEmpty || store.folders.isEmpty {
                            unfiledSection
                        }

                        if visibleCounters.isEmpty && store.folders.isEmpty {
                            ContentUnavailableView(
                                searchText.isEmpty ? "No Counters or Folders" : "No Matches",
                                systemImage: "square.grid.2x2",
                                description: Text(
                                    searchText.isEmpty
                                        ? "Create a folder or a counter to begin."
                                        : "Try another search."
                                )
                            )
                            .padding(.top, 36)
                        }
                    }
                    .safeAreaPadding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Tally")
            .searchable(text: $searchText, prompt: "Search counters and folders")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.undoLastAction()
                    } label: {
                        Label(
                            store.undoLabel.map { "Undo \($0)" } ?? "Undo",
                            systemImage: "arrow.uturn.backward"
                        )
                    }
                    .disabled(!store.canUndo)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(CounterSort.allCases) { option in
                                Label(option.title, systemImage: option.systemImage)
                                    .tag(option)
                            }
                        }
                        Divider()
                        Button("Expand All", systemImage: "rectangle.expand.vertical") {
                            setAllCollapsed(false)
                        }
                        Button("Collapse All", systemImage: "rectangle.compress.vertical") {
                            setAllCollapsed(true)
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                    }

                    Menu {
                        Button("New Counter", systemImage: "number.square.fill") {
                            showingAddCounter = true
                        }
                        Button("New Folder", systemImage: "folder.badge.plus") {
                            showingAddFolder = true
                        }
                    } label: {
                        Label("Create", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAddCounter) {
                CounterEditorView(mode: .add)
            }
            .sheet(isPresented: $showingAddFolder) {
                FolderEditorView()
            }
            .sheet(item: $editingFolder) {
                FolderEditorView(existing: $0)
            }
            .sheet(item: $quickCreateFolder) {
                QuickFolderCreateSheet(folder: $0)
            }
            .sheet(item: $exactValueCounter) {
                ExactValueEditor(counter: $0)
            }
            .task {
                store.ensureFoldersMigrated()
            }
            .onDisappear {
                cleanupTask?.cancel()
                expandTask?.cancel()
            }
        }
    }

    private var unfiledDropTarget: some View {
        HStack(spacing: 12) {
            Image(systemName: isUnfiledTargeted ? "tray.and.arrow.down.fill" : "tray")
                .font(.title3.weight(.bold))

            VStack(alignment: .leading, spacing: 2) {
                Text(isUnfiledTargeted ? "Release to move to Unfiled" : "Move out of a folder")
                    .font(.subheadline.weight(.heavy))
                Text(
                    isUnfiledTargeted
                        ? "This counter will no longer belong to a folder."
                        : "Drag any counter here to remove it from its folder."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isUnfiledTargeted ? Color.accentColor : Color.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, isUnfiledTargeted ? 16 : 12)
        .background(
            Color.accentColor.opacity(isUnfiledTargeted ? 0.16 : 0.055),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    Color.accentColor.opacity(isUnfiledTargeted ? 0.9 : 0.2),
                    style: StrokeStyle(lineWidth: isUnfiledTargeted ? 2 : 1, dash: isUnfiledTargeted ? [7, 5] : [])
                )
        }
        .scaleEffect(isUnfiledTargeted && !store.preferences.reducedAnimations ? 1.015 : 1)
        .padding(.horizontal)
        .dropDestination(for: String.self) { values, _ in
            guard let payload = values.first,
                  let counter = counter(from: payload),
                  resolvedFolderID(for: counter) != nil else {
                finishDrag(success: false)
                return false
            }

            withAnimation(motion) {
                store.moveCounter(counter, to: nil)
            }
            finishDrag(success: true)
            return true
        } isTargeted: { targeted in
            guard draggingCounterID != nil else { return }
            withAnimation(motion) {
                isUnfiledTargeted = targeted
                if targeted {
                    targetedFolderID = nil
                    targetedCounterID = nil
                }
            }
            if targeted {
                store.performHaptic(.selection)
            }
        }
        .animation(motion, value: isUnfiledTargeted)
    }

    private func folderSection(_ folder: TallyFolder) -> some View {
        let counters = counters(in: folder)
        let tint = TallyStoredColor.color(folder.colorRaw, fallback: .blue)
        let targeted = targetedFolderID == folder.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    toggleFolder(folder)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isCollapsed(folder) ? "folder.fill" : "folder.fill.badge.minus")
                            .foregroundStyle(tint)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.name)
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(tint)
                            Text("\(counters.count) counters • Total \(counters.map(\.value).reduce(0, +))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    quickCreateFolder = folder
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(tint)
                }
                .accessibilityLabel("Quick Create in \(folder.name)")

                Menu {
                    Button("Edit Folder", systemImage: "pencil") {
                        editingFolder = folder
                    }
                    Button("Quick Create", systemImage: "plus.circle") {
                        quickCreateFolder = folder
                    }
                    Divider()
                    Button("Delete Folder", systemImage: "trash", role: .destructive) {
                        store.deleteFolder(folder, keepCounters: true)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }

                Image(systemName: isCollapsed(folder) ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .draggable("folder:\(folder.id.uuidString)") {
                FolderDragPreview(
                    folder: folder,
                    tint: tint,
                    reducedMotion: store.preferences.reducedAnimations
                )
            }

            if !isCollapsed(folder) {
                ForEach(counters) { counter in
                    draggableCard(counter, targetFolder: folder)
                }

                if counters.isEmpty {
                    EmptyCounterDropTarget(
                        title: targeted ? "Release to move the counter here" : "Drop a counter here or use Quick Create.",
                        tint: tint,
                        targeted: targeted
                    )
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 6)
        .background(
            tint.opacity(targeted ? 0.13 : 0.035),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(tint.opacity(targeted ? 0.82 : 0), lineWidth: targeted ? 2 : 0)
        }
        .scaleEffect(targeted && !store.preferences.reducedAnimations ? 1.008 : 1)
        .dropDestination(for: String.self) { values, _ in
            guard let payload = values.first else {
                finishDrag(success: false)
                return false
            }

            if let counter = counter(from: payload) {
                withAnimation(motion) {
                    store.moveCounter(counter, to: folder)
                }
                finishDrag(success: true)
                return true
            }

            if let sourceFolder = folder(from: payload), sourceFolder.id != folder.id {
                withAnimation(motion) {
                    store.moveFolder(sourceFolder, before: folder)
                }
                finishDrag(success: true)
                return true
            }

            finishDrag(success: false)
            return false
        } isTargeted: { isTargeted in
            withAnimation(motion) {
                targetedFolderID = isTargeted ? folder.id : (targetedFolderID == folder.id ? nil : targetedFolderID)
                if isTargeted {
                    targetedCounterID = nil
                    isUnfiledTargeted = false
                }
            }

            if isTargeted {
                store.performHaptic(.selection)
                scheduleAutoExpand(folder)
            } else {
                expandTask?.cancel()
            }
        }
        .animation(motion, value: targeted)
        .animation(motion, value: isCollapsed(folder))
    }

    private var unfiledSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Unfiled", systemImage: "tray")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Counters without a folder")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)

            ForEach(unfiledCounters) { counter in
                draggableCard(counter, targetFolder: nil)
            }
        }
        .padding(.vertical, 6)
    }

    private func draggableCard(_ counter: TallyCounter, targetFolder: TallyFolder?) -> some View {
        let dragging = draggingCounterID == counter.id
        let insertionTarget = targetedCounterID == counter.id && draggingCounterID != counter.id
        let tint = targetFolder.map { TallyStoredColor.color($0.colorRaw, fallback: .blue) }
            ?? TallyStoredColor.color(counter.colorName)

        return CounterCard(
            counter: counter,
            showsDragHandle: sort == .manual,
            onEditExactValue: {
                exactValueCounter = counter
            }
        )
        .padding(.horizontal)
        .scaleEffect(dragging && !store.preferences.reducedAnimations ? 0.98 : 1)
        .opacity(dragging ? 0.38 : 1)
        .overlay(alignment: .top) {
            if insertionTarget {
                Capsule()
                    .fill(tint)
                    .frame(height: 4)
                    .padding(.horizontal, 24)
                    .offset(y: -8)
                    .shadow(color: tint.opacity(0.45), radius: 5)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .draggable("counter:\(counter.id.uuidString)") {
            CounterDragPreview(
                counter: counter,
                color: TallyStoredColor.color(counter.colorName),
                reducedMotion: store.preferences.reducedAnimations
            )
            .onAppear {
                beginDrag(counter)
            }
            .onDisappear {
                scheduleCleanup(counter.id)
            }
        }
        .dropDestination(for: String.self) { values, _ in
            guard sort == .manual,
                  let payload = values.first,
                  let source = self.counter(from: payload),
                  source.id != counter.id else {
                finishDrag(success: false)
                return false
            }

            withAnimation(motion) {
                store.moveCounter(source, before: counter, to: targetFolder)
            }
            finishDrag(success: true)
            return true
        } isTargeted: { targeted in
            guard draggingCounterID != nil else { return }
            withAnimation(motion) {
                targetedCounterID = targeted ? counter.id : (targetedCounterID == counter.id ? nil : targetedCounterID)
                if targeted {
                    targetedFolderID = targetFolder?.id
                    isUnfiledTargeted = targetFolder == nil
                }
            }
            if targeted {
                store.performHaptic(.selection)
            }
        }
        .animation(motion, value: dragging)
        .animation(motion, value: insertionTarget)
    }

    private func beginDrag(_ counter: TallyCounter) {
        cleanupTask?.cancel()
        withAnimation(motion) {
            draggingCounterID = counter.id
            targetedFolderID = nil
            targetedCounterID = nil
            isUnfiledTargeted = false
        }
        store.performHaptic(.light)
    }

    private func finishDrag(success: Bool) {
        cleanupTask?.cancel()
        expandTask?.cancel()
        if success {
            store.performHaptic(.success)
        }
        withAnimation(motion) {
            draggingCounterID = nil
            targetedFolderID = nil
            targetedCounterID = nil
            isUnfiledTargeted = false
        }
    }

    private func scheduleCleanup(_ id: UUID) {
        cleanupTask?.cancel()
        cleanupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, draggingCounterID == id else { return }
            finishDrag(success: false)
        }
    }

    private func scheduleAutoExpand(_ folder: TallyFolder) {
        expandTask?.cancel()
        guard isCollapsed(folder), draggingCounterID != nil else { return }
        expandTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, targetedFolderID == folder.id else { return }
            setFolder(folder, collapsed: false)
        }
    }

    private func counter(from payload: String) -> TallyCounter? {
        let raw = payload.hasPrefix("counter:")
            ? String(payload.dropFirst("counter:".count))
            : payload
        guard let id = UUID(uuidString: raw) else { return nil }
        return store.counters.first { $0.id == id }
    }

    private func folder(from payload: String) -> TallyFolder? {
        guard payload.hasPrefix("folder:") else { return nil }
        let raw = String(payload.dropFirst("folder:".count))
        guard let id = UUID(uuidString: raw) else { return nil }
        return store.folder(id: id)
    }

    private var collapsedFolderIDs: Set<UUID> {
        var values = Set(store.preferences.collapsedFolderIDs)
        for raw in legacyCollapsedFoldersRaw.split(separator: "\n") {
            if let id = UUID(uuidString: String(raw)) {
                values.insert(id)
            }
        }
        return values
    }

    private func isCollapsed(_ folder: TallyFolder) -> Bool {
        collapsedFolderIDs.contains(folder.id)
    }

    private func toggleFolder(_ folder: TallyFolder) {
        setFolder(folder, collapsed: !isCollapsed(folder))
    }

    private func setFolder(_ folder: TallyFolder, collapsed: Bool) {
        var values = collapsedFolderIDs
        if collapsed {
            values.insert(folder.id)
        } else {
            values.remove(folder.id)
        }
        withAnimation(motion) {
            store.preferences.collapsedFolderIDs = Array(values)
            legacyCollapsedFoldersRaw = ""
        }
    }

    private func setAllCollapsed(_ collapsed: Bool) {
        withAnimation(motion) {
            store.preferences.collapsedFolderIDs = collapsed ? store.folders.map(\.id) : []
            legacyCollapsedFoldersRaw = ""
        }
    }

    private var filteredCounters: [TallyCounter] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.activeCounters }
        return store.activeCounters.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.displayGroup.localizedCaseInsensitiveContains(query)
                || $0.notes.localizedCaseInsensitiveContains(query)
        }
    }

    private var visibleCounters: [TallyCounter] {
        sortCounters(filteredCounters)
    }

    private var visibleFolders: [TallyFolder] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let folders = query.isEmpty
            ? store.folders
            : store.folders.filter { folder in
                folder.name.localizedCaseInsensitiveContains(query)
                    || filteredCounters.contains { resolvedFolderID(for: $0) == folder.id }
            }
        return folders.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var unfiledCounters: [TallyCounter] {
        sortCounters(filteredCounters.filter { resolvedFolderID(for: $0) == nil })
    }

    private func counters(in folder: TallyFolder) -> [TallyCounter] {
        sortCounters(filteredCounters.filter { resolvedFolderID(for: $0) == folder.id })
    }

    private func resolvedFolderID(for counter: TallyCounter) -> UUID? {
        if let id = counter.folderID, store.folder(id: id) != nil {
            return id
        }
        return store.folder(named: counter.group)?.id
    }

    private var hasFiledCounters: Bool {
        store.activeCounters.contains { resolvedFolderID(for: $0) != nil }
    }

    private func sortCounters(_ counters: [TallyCounter]) -> [TallyCounter] {
        counters.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            switch sort {
            case .manual:
                if lhs.sortIndex == rhs.sortIndex {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortIndex < rhs.sortIndex
            case .recent:
                return lhs.updatedAt > rhs.updatedAt
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .value:
                return lhs.value > rhs.value
            }
        }
    }

    private var background: some View {
        Group {
            if store.theme == .oled {
                Color.black.ignoresSafeArea()
            } else if store.theme == .dark {
                Color(red: 0.055, green: 0.055, blue: 0.065)
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [Color(.systemBackground), Color.blue.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }

    private var quickStats: some View {
        HStack(spacing: 12) {
            StatPill(title: "Active", value: "\(store.activeCounters.count)", systemImage: "number")
            StatPill(title: "Folders", value: "\(store.folders.count)", systemImage: "folder")
            StatPill(title: "Total", value: "\(visibleCounters.map(\.value).reduce(0, +))", systemImage: "sum")
        }
        .padding(.horizontal)
    }
}

private struct EmptyCounterDropTarget: View {
    let title: String
    let tint: Color
    let targeted: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(targeted ? .semibold : .regular))
            .foregroundStyle(targeted ? tint : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, targeted ? 24 : 18)
            .background(
                tint.opacity(targeted ? 0.14 : 0.06),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        tint.opacity(targeted ? 0.75 : 0),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
            }
    }
}
