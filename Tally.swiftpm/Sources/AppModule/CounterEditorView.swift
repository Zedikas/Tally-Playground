import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum CounterEditorMode: Identifiable {
    case add
    case edit(TallyCounter)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let counter): return counter.id.uuidString
        }
    }
}

struct CounterEditorView: View {
    @EnvironmentObject private var store: TallyStore
    @Environment(\.dismiss) private var dismiss

    let mode: CounterEditorMode

    @State private var name = ""
    @State private var selectedFolderID: UUID?
    @State private var goalText = ""
    @State private var symbol = "number.square.fill"
    @State private var colorRaw = CounterColor.blue.rawValue
    @State private var folderColorRaw = CounterColor.gray.rawValue
    @State private var counterCustomColor = Color.blue
    @State private var folderCustomColor = Color.blue
    @State private var showingCounterCustomColor = false
    @State private var showingFolderCustomColor = false
    @State private var notes = ""
    @State private var steps = [1, 5, 10]
    @State private var resetReminder: ResetReminder = .none
    @State private var automaticResetEnabled = false
    @State private var resetTime = Calendar.current.date(from: DateComponents(hour: 0, minute: 0)) ?? Date()
    @State private var resetWeekday = 2
    @State private var resetDayOfMonth = 1
    @State private var carryExcessOnReset = false
    @State private var resetNotificationEnabled = false
    @State private var isPinned = false
    @State private var isLocked = false
    @State private var milestonesText = "10, 50, 100"

    private var counterColor: Color { TallyStoredColor.color(colorRaw) }
    private var selectedFolder: TallyFolder? { store.folder(id: selectedFolderID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isAdding { templates }

                    TallyEditorCard(title: "Counter", systemImage: "number.square.fill") {
                        TextField("Counter name", text: $name)
                            .font(.title3.weight(.semibold))
                        Divider()
                        folderMenu
                        Divider()
                        TextField("Optional goal", text: $goalText)
                            .keyboardType(.numberPad)
                    }

                    TallyEditorCard(title: "Appearance", systemImage: "paintpalette.fill") {
                        StoredColorMenu(
                            title: "Counter Color",
                            systemImage: "circle.fill",
                            rawValue: $colorRaw,
                            customColor: $counterCustomColor,
                            showingCustomPicker: $showingCounterCustomColor
                        )
                        Divider()
                        StoredColorMenu(
                            title: "Folder Color",
                            systemImage: "folder.fill",
                            rawValue: $folderColorRaw,
                            customColor: $folderCustomColor,
                            showingCustomPicker: $showingFolderCustomColor
                        )
                        .disabled(selectedFolderID != nil)
                        Divider()
                        symbolMenu
                        if selectedFolderID != nil {
                            Text("The selected folder controls the folder color.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    TallyEditorCard(title: "Controls", systemImage: "plusminus.circle.fill") {
                        StepPresetEditor(steps: $steps)
                        Text("The −1 button remains available beside these three positive steps.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    TallyEditorCard(title: "Automation", systemImage: "arrow.triangle.2.circlepath") {
                        Picker("Reset Schedule", selection: $resetReminder) {
                            ForEach(ResetReminder.allCases) { reminder in
                                Label(reminder.title, systemImage: reminder.systemImage).tag(reminder)
                            }
                        }
                        if resetReminder != .none {
                            Divider()
                            DatePicker("Reset Time", selection: $resetTime, displayedComponents: .hourAndMinute)
                            if resetReminder == .weekly {
                                Divider()
                                Picker("Weekday", selection: $resetWeekday) {
                                    ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, title in
                                        Text(title).tag(index + 1)
                                    }
                                }
                            }
                            if resetReminder == .monthly {
                                Divider()
                                Picker("Day of Month", selection: $resetDayOfMonth) {
                                    ForEach(1...28, id: \.self) { Text("\($0)").tag($0) }
                                }
                            }
                            Divider()
                            Toggle("Reset Automatically", isOn: $automaticResetEnabled)
                            Toggle("Notify Five Minutes Before", isOn: $resetNotificationEnabled)
                            Toggle("Carry Value Above Goal", isOn: $carryExcessOnReset)
                            Text(resetReminder.subtitle)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    TallyEditorCard(title: "Progress", systemImage: "trophy.fill") {
                        TextField("10, 50, 100", text: $milestonesText)
                            .keyboardType(.numbersAndPunctuation)
                        Text("Enter milestone values separated by commas.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    TallyEditorCard(title: "Favorites & Safety", systemImage: "shield.fill") {
                        Toggle(isOn: $isPinned) {
                            Label("Pin at Top of Its Folder", systemImage: "pin.fill")
                        }
                        Toggle(isOn: $isLocked) {
                            Label("Lock Counter", systemImage: "lock.fill")
                        }
                        Text("Pinned counters stay inside their assigned folder. Locked counters cannot be changed or reset.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    TallyEditorCard(title: "Notes", systemImage: "note.text") {
                        TextField("Optional notes", text: $notes, axis: .vertical)
                            .lineLimit(3...7)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                store.ensureFoldersMigrated()
                populate()
            }
            .onChange(of: resetReminder) { _, newValue in
                if newValue == .none {
                    automaticResetEnabled = false
                    resetNotificationEnabled = false
                    carryExcessOnReset = false
                }
            }
            .sheet(isPresented: $showingCounterCustomColor) {
                CustomStoredColorSheet(title: "Counter Color", rawValue: $colorRaw, color: $counterCustomColor)
            }
            .sheet(isPresented: $showingFolderCustomColor) {
                CustomStoredColorSheet(title: "Folder Color", rawValue: $folderColorRaw, color: $folderCustomColor)
            }
        }
    }

    private var templates: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Templates", systemImage: "square.grid.2x2.fill")
                .font(.headline.weight(.heavy))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CounterTemplate.allCases) { template in
                        Button { apply(template) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: template.symbol)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(template.color.color)
                                    .frame(width: 44, height: 44)
                                    .background(template.color.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                                Text(template.title).font(.subheadline.weight(.heavy)).foregroundStyle(.primary)
                                Text(template.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                if templateMatchesCurrent(template) {
                                    Label("Selected", systemImage: "checkmark.circle.fill")
                                        .font(.caption.weight(.bold)).foregroundStyle(.green)
                                }
                            }
                            .frame(width: 160, alignment: .leading)
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var folderMenu: some View {
        Menu {
            Button {
                selectedFolderID = nil
                folderColorRaw = CounterColor.gray.rawValue
            } label: {
                Label("Unfiled", systemImage: selectedFolderID == nil ? "checkmark" : "tray")
            }
            if !store.folders.isEmpty { Divider() }
            ForEach(store.folders) { folder in
                Button {
                    selectedFolderID = folder.id
                    applyFolderPresets(folder)
                } label: {
                    #if canImport(UIKit)
                    Label {
                        Text(folder.name)
                    } icon: {
                        Image(uiImage: TallyStoredColor.swatchImage(TallyStoredColor.color(folder.colorRaw), selected: selectedFolderID == folder.id))
                            .renderingMode(.original)
                    }
                    #else
                    Text(folder.name)
                    #endif
                }
            }
        } label: {
            HStack {
                Text("Folder").foregroundStyle(.primary)
                Spacer()
                Image(systemName: selectedFolder == nil ? "tray" : "folder.fill")
                    .foregroundStyle(selectedFolder.map { TallyStoredColor.color($0.colorRaw) } ?? .secondary)
                Text(selectedFolder?.name ?? "Unfiled").foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var symbolMenu: some View {
        Menu {
            ForEach(CounterSymbolOption.all) { option in
                Button { symbol = option.symbol } label: {
                    Label(option.title, systemImage: option.symbol)
                }
            }
        } label: {
            HStack {
                Text("Symbol").foregroundStyle(.primary)
                Spacer()
                Image(systemName: symbol).foregroundStyle(counterColor)
                Text(CounterSymbolOption.title(for: symbol)).foregroundStyle(counterColor)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(counterColor)
            }
        }
    }

    private var title: String {
        if case .add = mode { return "New Counter" }
        return "Edit Counter"
    }

    private var isAdding: Bool {
        if case .add = mode { return true }
        return false
    }

    private var milestones: [Int] {
        TallyCounter.sanitizedMilestones(
            milestonesText.split(separator: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        )
    }

    private func populate() {
        guard case .edit(let counter) = mode else { return }
        name = counter.name
        selectedFolderID = store.folder(for: counter)?.id
        goalText = counter.goal.map(String.init) ?? ""
        symbol = counter.symbol
        colorRaw = counter.colorName
        folderColorRaw = store.folder(for: counter)?.colorRaw ?? counter.folderColorName
        counterCustomColor = TallyStoredColor.color(colorRaw)
        folderCustomColor = TallyStoredColor.color(folderColorRaw)
        notes = counter.notes
        steps = counter.stepValues
        resetReminder = counter.resetReminder
        automaticResetEnabled = counter.automaticResetEnabled
        resetTime = Calendar.current.date(from: DateComponents(hour: counter.resetHour, minute: counter.resetMinute)) ?? Date()
        resetWeekday = counter.resetWeekday
        resetDayOfMonth = counter.resetDayOfMonth
        carryExcessOnReset = counter.carryExcessOnReset
        resetNotificationEnabled = counter.resetNotificationEnabled
        isPinned = counter.isPinned
        isLocked = counter.isLocked
        milestonesText = counter.milestones.map(String.init).joined(separator: ", ")
    }

    private func apply(_ template: CounterTemplate) {
        name = template.name
        selectedFolderID = store.folder(named: template.group)?.id
        goalText = template.goal.map(String.init) ?? ""
        symbol = template.symbol
        colorRaw = template.color.rawValue
        folderColorRaw = selectedFolder.map(\.colorRaw) ?? CounterColor.gray.rawValue
        notes = template.notes
        resetReminder = template.resetReminder
        automaticResetEnabled = false
        steps = template.stepValues
    }

    private func applyFolderPresets(_ folder: TallyFolder) {
        folderColorRaw = folder.colorRaw
        guard isAdding else { return }
        colorRaw = folder.defaultCounterColorRaw
        symbol = folder.defaultSymbol
        resetReminder = folder.defaultResetReminder
        automaticResetEnabled = folder.defaultAutomaticReset
        resetTime = Calendar.current.date(from: DateComponents(hour: folder.defaultResetHour, minute: folder.defaultResetMinute)) ?? Date()
        resetWeekday = folder.defaultResetWeekday
        resetDayOfMonth = folder.defaultResetDayOfMonth
        carryExcessOnReset = folder.defaultCarryExcess
        resetNotificationEnabled = folder.defaultResetNotification
        steps = folder.defaultStepValues
    }

    private func templateMatchesCurrent(_ template: CounterTemplate) -> Bool {
        name == template.name &&
        selectedFolderID == store.folder(named: template.group)?.id &&
        goalText == (template.goal.map(String.init) ?? "") &&
        symbol == template.symbol &&
        colorRaw == template.color.rawValue &&
        resetReminder == template.resetReminder &&
        TallyCounter.sanitizedStepValues(steps) == TallyCounter.sanitizedStepValues(template.stepValues)
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = Int(goalText.trimmingCharacters(in: .whitespacesAndNewlines))
        let folder = selectedFolder
        let components = Calendar.current.dateComponents([.hour, .minute], from: resetTime)
        let resolvedFolderColor = folder?.colorRaw ?? folderColorRaw
        let baseColor = CounterColor(rawValue: colorRaw) ?? .blue

        switch mode {
        case .add:
            guard let created = store.addCounter(
                name: cleanName,
                group: folder?.name ?? "",
                goal: goal,
                symbol: symbol,
                color: baseColor,
                notes: notes,
                stepValues: steps,
                resetReminder: resetReminder
            ), let index = store.counters.firstIndex(where: { $0.id == created.id }) else {
                return
            }
            store.counters[index].folderID = folder?.id
            store.counters[index].group = folder?.name ?? ""
            store.counters[index].colorName = colorRaw
            store.counters[index].folderColorName = resolvedFolderColor
            store.counters[index].isPinned = isPinned
            store.counters[index].isLocked = isLocked
            store.counters[index].automaticResetEnabled = automaticResetEnabled && resetReminder != .none
            store.counters[index].resetHour = components.hour ?? 0
            store.counters[index].resetMinute = components.minute ?? 0
            store.counters[index].resetWeekday = resetWeekday
            store.counters[index].resetDayOfMonth = resetDayOfMonth
            store.counters[index].carryExcessOnReset = carryExcessOnReset
            store.counters[index].resetNotificationEnabled = resetNotificationEnabled && resetReminder != .none
            store.counters[index].milestones = milestones
            store.scheduleResetNotification(for: store.counters[index])

        case .edit(var counter):
            counter.name = cleanName
            counter.folderID = folder?.id
            counter.group = folder?.name ?? ""
            counter.goal = goal
            counter.symbol = symbol
            counter.colorName = colorRaw
            counter.folderColorName = resolvedFolderColor
            counter.notes = notes
            counter.stepValues = steps
            counter.resetReminder = resetReminder
            counter.automaticResetEnabled = automaticResetEnabled && resetReminder != .none
            counter.resetHour = components.hour ?? 0
            counter.resetMinute = components.minute ?? 0
            counter.resetWeekday = resetWeekday
            counter.resetDayOfMonth = resetDayOfMonth
            counter.carryExcessOnReset = carryExcessOnReset
            counter.resetNotificationEnabled = resetNotificationEnabled && resetReminder != .none
            counter.isPinned = isPinned
            counter.isLocked = isLocked
            counter.milestones = milestones
            store.updateCounter(counter)
        }
        dismiss()
    }
}
