import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var store: TallyStore
    @State private var showingChangelog = false
    @State private var showingOnboarding = false

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) build \(build)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Customization") {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            title: "Appearance",
                            subtitle: "Theme, accent presets, and custom color",
                            systemImage: "paintbrush.fill"
                        )
                    }

                    NavigationLink {
                        AppIconSettingsView()
                    } label: {
                        SettingsNavigationRow(
                            title: "App Icon",
                            subtitle: "Choose from the complete Tally icon family",
                            systemImage: "app.badge.fill"
                        )
                    }
                }

                Section("Behavior") {
                    Toggle(isOn: $store.preferences.hapticsEnabled) {
                        Label("Haptic Feedback", systemImage: "waveform.path")
                    }
                    Toggle(isOn: $store.preferences.reducedAnimations) {
                        Label("Reduce Tally Animations", systemImage: "figure.walk.motion")
                    }
                    Button {
                        showingOnboarding = true
                    } label: {
                        Label("Show Welcome Guide", systemImage: "sparkles.rectangle.stack")
                    }
                }

                Section("Data & Sync") {
                    NavigationLink {
                        SyncCenterView()
                    } label: {
                        SettingsNavigationRow(
                            title: "Sync Center",
                            subtitle: "Full backups, appearance restore, Android interchange, and diagnostics",
                            systemImage: "arrow.triangle.2.circlepath.icloud",
                            value: "r\(store.preferences.syncRevision)"
                        )
                    }
                }

                Section("Counter Management") {
                    NavigationLink {
                        ArchivedCountersView()
                    } label: {
                        SettingsNavigationRow(
                            title: "Archived Counters",
                            subtitle: "Restore or permanently remove counters",
                            systemImage: "archivebox.fill",
                            value: "\(store.archivedCounters.count)"
                        )
                    }
                    LabeledContent("Pinned Counters", value: "\(store.activeCounters.filter(\.isPinned).count)")
                    LabeledContent("Locked Counters", value: "\(store.activeCounters.filter(\.isLocked).count)")
                    LabeledContent("Folders", value: "\(store.folders.count)")
                }

                Section("Installation Compatibility") {
                    NavigationLink {
                        AppDBCompatibilityView()
                    } label: {
                        SettingsNavigationRow(
                            title: "AppDB-safe Mode",
                            subtitle: "See which features avoid restricted signing entitlements",
                            systemImage: "checkmark.shield.fill"
                        )
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: versionText)
                    LabeledContent("Data Schema", value: "2.0")
                    Button("Changelog") {
                        showingChangelog = true
                    }
                }
            }
            .tallyOLEDBackground()
            .navigationTitle("Settings")
            .sheet(isPresented: $showingChangelog) {
                ChangelogView()
            }
            .sheet(isPresented: $showingOnboarding) {
                TallyOnboardingView()
                    .environmentObject(store)
            }
        }
    }
}

struct SyncCenterView: View {
    @EnvironmentObject private var store: TallyStore
    @State private var exportURL: URL?
    @State private var showingImporter = false
    @State private var importMessage: String?
    @State private var importPreview: TallyPortableBackupPreview?

    private static let tallySyncType = UTType(filenameExtension: "tallysync") ?? .data

    var body: some View {
        List {
            Section("Complete iOS Backup") {
                Button {
                    exportURL = TallyPortableBackupManager.exportURL(from: store)
                } label: {
                    Label("Create Full JSON Backup", systemImage: "externaldrive.fill")
                }

                Text("Includes counters, folders, presets, sessions, history, ordering, theme, accent color, custom accent HEX, app icon choice, collapsed folders, haptics, and animation preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("iOS ↔ Android Sync Package") {
                Button {
                    exportURL = store.exportSyncPackageURL()
                } label: {
                    Label("Create Sync Package", systemImage: "arrow.left.arrow.right.circle.fill")
                }

                Text("The .tallysync package remains focused on shared counter, folder, session, history, and theme data so it stays compatible with Android.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Import") {
                Button {
                    showingImporter = true
                } label: {
                    Label("Preview & Import Backup", systemImage: "doc.text.magnifyingglass")
                }

                Text("New full backups can restore appearance separately, merge data without changing your current look, or replace everything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Exports") {
                Button {
                    exportURL = store.exportCSVURL()
                } label: {
                    Label("Export History CSV", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    exportURL = store.exportSessionsCSVURL()
                } label: {
                    Label("Export Sessions CSV", systemImage: "timer")
                }

                Button {
                    exportURL = store.exportDiagnosticsURL()
                } label: {
                    Label("Export Diagnostics", systemImage: "stethoscope")
                }
            }

            if let exportURL {
                Section("Ready to Share") {
                    ShareLink(item: exportURL) {
                        Label("Share \(exportURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                    }
                }
            }

            if let importMessage {
                Section("Last Import") {
                    Text(importMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sync Identity") {
                LabeledContent("Device", value: String(store.preferences.deviceID.uuidString.prefix(8)))
                LabeledContent("Revision", value: "\(store.preferences.syncRevision)")
                LabeledContent(
                    "Last Sync",
                    value: store.preferences.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
                )
            }
        }
        .tallyOLEDBackground()
        .navigationTitle("Sync Center")
        .sheet(item: $importPreview) { preview in
            BackupImportPreviewView(preview: preview) { mode in
                do {
                    try TallyPortableBackupManager.importBackup(
                        from: preview.url,
                        into: store,
                        mode: mode
                    )

                    switch mode {
                    case .mergeData:
                        importMessage = "Backup data merged. Your current appearance was preserved."
                    case .replaceEverything:
                        importMessage = preview.includesCosmetics
                            ? "Backup restored, including cosmetic settings."
                            : "Legacy backup restored. It did not contain accent or app icon settings."
                    case .appearanceOnly:
                        importMessage = "Appearance restored without changing counters or history."
                    }
                    importPreview = nil
                } catch {
                    importMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json, Self.tallySyncType],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let source = urls.first else {
                importMessage = "No backup file selected."
                return
            }

            do {
                let scoped = source.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        source.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: source)
                let fileExtension = source.pathExtension.isEmpty ? "json" : source.pathExtension
                let local = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Tally_Import_\(UUID().uuidString).\(fileExtension)")
                try data.write(to: local, options: .atomic)
                importPreview = try TallyPortableBackupManager.preview(from: local)
                importMessage = nil
            } catch {
                importMessage = "Preview failed: \(error.localizedDescription)"
            }

        case .failure(let error):
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

struct BackupImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let preview: TallyPortableBackupPreview
    let onImport: (TallyPortableBackupManager.ImportMode) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Backup Details") {
                    LabeledContent("Version", value: preview.version)
                    LabeledContent("Revision", value: "\(preview.revision)")
                    LabeledContent(
                        "Exported",
                        value: preview.exportedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    LabeledContent("Theme", value: preview.themeTitle)
                    LabeledContent("Accent", value: preview.accentTitle)
                    LabeledContent("App Icon", value: preview.iconTitle)
                }

                Section("Contents") {
                    LabeledContent("Counters", value: "\(preview.counterCount)")
                    LabeledContent("Active", value: "\(preview.activeCounterCount)")
                    LabeledContent("Archived", value: "\(preview.archivedCounterCount)")
                    LabeledContent("Folders", value: "\(preview.folderCount)")
                    LabeledContent("History", value: "\(preview.historyCount)")
                    LabeledContent("Sessions", value: "\(preview.sessionCount)")
                }

                Section("Import Options") {
                    Button {
                        onImport(.mergeData)
                        dismiss()
                    } label: {
                        Label("Merge Data Only", systemImage: "plus.square.on.square")
                    }

                    if preview.includesCosmetics {
                        Button {
                            onImport(.appearanceOnly)
                            dismiss()
                        } label: {
                            Label("Restore Appearance Only", systemImage: "paintbrush.pointed.fill")
                        }
                    }

                    Button(role: .destructive) {
                        onImport(.replaceEverything)
                        dismiss()
                    } label: {
                        Label("Replace Everything", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .navigationTitle("Import Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var store: TallyStore
    @AppStorage(StoredAccentColor.presetKey) private var accentRaw = TallyAccentColor.blue.rawValue
    @AppStorage(StoredAccentColor.customKey) private var customHex = "FF1883"
    @State private var customColor = Color.pink

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ZStack {
            if store.theme == .oled {
                Color.black.ignoresSafeArea()
            } else if store.theme == .dark {
                Color(red: 0.055, green: 0.055, blue: 0.065)
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Appearance", selection: $store.theme) {
                        Text("Default").tag(TallyTheme.system)
                        Text("Light").tag(TallyTheme.light)
                        Text("Dark").tag(TallyTheme.dark)
                        Text("OLED").tag(TallyTheme.oled)
                    }
                    .pickerStyle(.segmented)
                    .padding(14)
                    .background(
                        store.theme == .oled ? Color(white: 0.035) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 22)
                    )
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))

                    Text("Accent Theme")
                        .font(.title2.weight(.heavy))

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(TallyAccentColor.allCases) { accent in
                            Button {
                                accentRaw = accent.rawValue
                            } label: {
                                VStack(spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(accent.color.opacity(0.25))
                                            .frame(width: 54, height: 54)
                                        Circle()
                                            .fill(accent.color)
                                            .frame(width: 34, height: 34)
                                        if accentRaw == accent.rawValue {
                                            Image(systemName: "checkmark")
                                                .fontWeight(.black)
                                                .foregroundStyle(.white)
                                        }
                                    }

                                    Text(accent.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(accent.color)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    store.theme == .oled ? Color(white: 0.035) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 20)
                                )
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Custom Theme Color")
                                    .font(.headline)
                                Text("Use any color instead of a preset.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ColorPicker("", selection: $customColor, supportsOpacity: false)
                                .labelsHidden()
                        }

                        HStack {
                            Circle()
                                .fill(customColor)
                                .frame(width: 34, height: 34)
                            Text("#\(customHex.uppercased())")
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("Use Custom") {
                                customHex = customColor.hexString()
                                accentRaw = StoredAccentColor.customValue
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(18)
                    .background(
                        store.theme == .oled ? Color(white: 0.035) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 22)
                    )
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                }
                .padding()
            }
        }
        .navigationTitle("Appearance")
        .onAppear {
            customColor = Color(hex: customHex) ?? .pink
        }
        .onChange(of: customColor) { _, value in
            customHex = value.hexString()
        }
    }
}

struct AppIconSettingsView: View {
    @EnvironmentObject private var store: TallyStore
    @State private var iconMessage: String?

    var body: some View {
        List {
            Section("Tally Icon Family") {
                ForEach(TallyIcon.allCases) { icon in
                    Button {
                        setIcon(icon)
                    } label: {
                        HStack(spacing: 16) {
                            iconPreview(icon)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(icon.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(icon.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if icon.isSelected {
                                Image(systemName: "checkmark")
                                    .font(.title3.weight(.heavy))
                                    .foregroundStyle(icon.tint)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let iconMessage {
                Section {
                    Text(iconMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tallyOLEDBackground()
        .navigationTitle("App Icon")
    }

    @ViewBuilder
    private func iconPreview(_ icon: TallyIcon) -> some View {
        #if canImport(UIKit)
        if let path = Bundle.main.path(forResource: icon.previewName, ofType: "png"),
           let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        } else if let image = UIImage(named: icon.previewName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(icon.tint.gradient)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "number")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                )
        }
        #else
        RoundedRectangle(cornerRadius: 15)
            .fill(icon.tint)
            .frame(width: 64, height: 64)
        #endif
    }

    private func setIcon(_ icon: TallyIcon) {
        #if canImport(UIKit)
        guard UIApplication.shared.supportsAlternateIcons else {
            iconMessage = "This install method does not support alternate icons."
            return
        }

        UIApplication.shared.setAlternateIconName(icon.iconName) { error in
            iconMessage = error?.localizedDescription ?? "Icon changed to \(icon.title)."
        }
        #endif
    }
}

struct AppDBCompatibilityView: View {
    @EnvironmentObject private var store: TallyStore
    @State private var notificationMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("AppDB-safe Build", systemImage: "checkmark.shield.fill")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.green)
                    Text("The default unsigned IPA contains only the main application target. This avoids extension and cloud entitlements that limited signing profiles may strip or reject.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Capabilities") {
                ForEach(TallySigningCapability.all) { capability in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: capability.systemImage)
                            .font(.title3)
                            .frame(width: 28)
                            .foregroundStyle(capability.availableInAppDBBuild ? .green : .orange)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(capability.title)
                                .font(.headline)
                            Text(capability.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(
                            systemName: capability.availableInAppDBBuild
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(capability.availableInAppDBBuild ? .green : .orange)
                    }
                }
            }

            Section("Local Notifications") {
                Button {
                    Task {
                        let granted = await store.requestResetNotificationAuthorization()
                        notificationMessage = granted
                            ? "Notification permission granted."
                            : "Notification permission was not granted."
                    }
                } label: {
                    Label("Request Notification Permission", systemImage: "bell.badge.fill")
                }

                if let notificationMessage {
                    Text(notificationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tallyOLEDBackground()
        .navigationTitle("Compatibility")
    }
}

struct ArchivedCountersView: View {
    @EnvironmentObject private var store: TallyStore
    @State private var searchText = ""

    private var filtered: [TallyCounter] {
        searchText.isEmpty
            ? store.archivedCounters
            : store.archivedCounters.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.displayGroup.localizedCaseInsensitiveContains(searchText)
            }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "Archive Empty",
                    systemImage: "archivebox",
                    description: Text("Archived counters will appear here.")
                )
            } else {
                ForEach(filtered) { counter in
                    ArchivedCounterRow(counter: counter)
                }
            }
        }
        .tallyOLEDBackground()
        .navigationTitle("Archive")
        .searchable(text: $searchText, prompt: "Search archive")
    }
}

struct ArchivedCounterRow: View {
    @EnvironmentObject private var store: TallyStore
    let counter: TallyCounter
    @State private var showingDelete = false

    private var color: Color {
        TallyStoredColor.color(counter.colorName, fallback: .gray)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: counter.symbol)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading) {
                Text(counter.name)
                    .font(.headline)
                Text("\(counter.displayGroup) • value \(counter.value)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    store.restoreCounter(counter)
                }
                Button("Delete Forever", systemImage: "trash", role: .destructive) {
                    showingDelete = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .confirmationDialog("Delete \(counter.name) forever?", isPresented: $showingDelete) {
            Button("Delete", role: .destructive) {
                store.permanentlyDeleteCounter(counter)
            }
        }
    }
}

struct SettingsNavigationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

struct TallyIcon: Identifiable, CaseIterable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String?
    let previewName: String
    let tint: Color

    var isSelected: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.alternateIconName == iconName
            || (UIApplication.shared.alternateIconName == nil && iconName == nil)
        #else
        return iconName == nil
        #endif
    }

    static let allCases: [TallyIcon] = [
        .init(id: "primary", title: "Classic Blue", subtitle: "The original polished Tally counter", iconName: nil, previewName: "TallyIconClassicBlue", tint: .blue),
        .init(id: "neon", title: "Neon Dark", subtitle: "Electric blue for OLED screens", iconName: "NeonDark", previewName: "TallyIconNeonDark", tint: .blue),
        .init(id: "glass", title: "Glass", subtitle: "Transparent blue glass with bright edge highlights", iconName: "Glass", previewName: "TallyIconGlass", tint: .cyan),
        .init(id: "pearl", title: "Pearl", subtitle: "Matte ivory with dark metallic details", iconName: "Pearl", previewName: "TallyIconPearl", tint: .gray),
        .init(id: "amber", title: "Amber", subtitle: "Warm golden counter", iconName: "Amber", previewName: "TallyIconAmber", tint: .orange),
        .init(id: "green", title: "Tech Green", subtitle: "Neon productivity", iconName: "TechGreen", previewName: "TallyIconTechGreen", tint: .green),
        .init(id: "purple", title: "Cosmic Purple", subtitle: "Deep violet glow", iconName: "CosmicPurple", previewName: "TallyIconCosmicPurple", tint: .purple),
        .init(id: "synth", title: "Synthwave", subtitle: "Pink, purple, and cyan", iconName: "Synthwave", previewName: "TallyIconSynthwave", tint: .pink)
    ]
}

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tally v2.0")
                            .font(.title2.weight(.heavy))
                        Text("A major AppDB-safe foundation update with stable folders, complete cosmetic backups, advanced sessions, reset scheduling, and native-feeling organization.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("v2.0") {
                    ChangelogRow(title: "Pinned in Place", detail: "Pinned counters remain inside their folder and sort to the top. Unfiled pins stay at the top of Unfiled.")
                    ChangelogRow(title: "Stable Folder IDs", detail: "Folder relationships no longer depend on names, making rename, import, and sync safer.")
                    ChangelogRow(title: "Complete Cosmetic Backups", detail: "Full JSON backups now include accent colors, custom HEX values, app icon choice, theme, and behavior preferences.")
                    ChangelogRow(title: "Drag Reordering", detail: "Move counters between folders, move them to Unfiled, reorder inside folders, and reorder folders themselves.")
                    ChangelogRow(title: "Advanced Sessions", detail: "Pause, resume, restart, and set optional session duration goals.")
                    ChangelogRow(title: "Scheduled Resets", detail: "Choose time, weekday or month day, carry excess values, and receive local reminders.")
                    ChangelogRow(title: "AppDB-safe Architecture", detail: "Restricted extension and iCloud capabilities are separated from the unsigned main-app build.")
                }
            }
            .navigationTitle("Changelog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ChangelogRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
