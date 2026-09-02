import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct TallyCosmeticSnapshot: Codable, Equatable {
    var accentColorRaw: String
    var customAccentHex: String
    var alternateIconName: String?

    init(
        accentColorRaw: String = TallyAccentColor.blue.rawValue,
        customAccentHex: String = "FF1883",
        alternateIconName: String? = nil
    ) {
        self.accentColorRaw = accentColorRaw
        self.customAccentHex = TallyStoredColor.normalizedHex(customAccentHex)
        self.alternateIconName = alternateIconName
    }
}

struct TallyPortableBackupEnvelope: Codable {
    var format: String = "tally-full-backup"
    var formatVersion: Int = 1
    var data: TallyBackup
    var cosmetics: TallyCosmeticSnapshot
}

struct TallyPortableBackupPreview: Identifiable {
    let id = UUID()
    let url: URL
    let version: String
    let exportedAt: Date
    let revision: Int
    let counterCount: Int
    let activeCounterCount: Int
    let archivedCounterCount: Int
    let folderCount: Int
    let historyCount: Int
    let sessionCount: Int
    let themeTitle: String
    let accentTitle: String
    let iconTitle: String
    let includesCosmetics: Bool
}

@MainActor
enum TallyPortableBackupManager {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    static func exportURL(from store: TallyStore) -> URL? {
        let backup = TallyBackup(
            version: "2.0",
            revision: store.preferences.syncRevision,
            counters: store.counters,
            folders: store.folders,
            history: store.history,
            theme: store.theme,
            sessions: store.sessions,
            preferences: store.preferences
        )

        let envelope = TallyPortableBackupEnvelope(
            data: backup,
            cosmetics: currentCosmetics()
        )

        guard let data = try? encoder.encode(envelope) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tally_Full_Backup_\(timestamp()).json")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func preview(from url: URL) throws -> TallyPortableBackupPreview {
        let decoded = try decode(url)
        let backup = decoded.backup
        let cosmetics = decoded.cosmetics

        return TallyPortableBackupPreview(
            url: url,
            version: backup.version,
            exportedAt: backup.exportedAt,
            revision: backup.revision,
            counterCount: backup.counters.count,
            activeCounterCount: backup.counters.filter { !$0.isArchived }.count,
            archivedCounterCount: backup.counters.filter(\.isArchived).count,
            folderCount: backup.folders.count,
            historyCount: backup.history.count,
            sessionCount: backup.sessions.count,
            themeTitle: backup.theme.title,
            accentTitle: accentTitle(cosmetics?.accentColorRaw),
            iconTitle: iconTitle(cosmetics?.alternateIconName),
            includesCosmetics: cosmetics != nil
        )
    }

    static func importBackup(
        from url: URL,
        into store: TallyStore,
        mode: ImportMode
    ) throws {
        let decoded = try decode(url)

        switch mode {
        case .mergeData:
            let coreURL = try writeTemporaryCoreBackup(decoded.backup)
            defer { try? FileManager.default.removeItem(at: coreURL) }
            try store.importBackup(from: coreURL, replaceExisting: false)

        case .replaceEverything:
            let coreURL = try writeTemporaryCoreBackup(decoded.backup)
            defer { try? FileManager.default.removeItem(at: coreURL) }
            try store.importBackup(from: coreURL, replaceExisting: true)
            if let cosmetics = decoded.cosmetics {
                apply(cosmetics, store: store)
            }

        case .appearanceOnly:
            store.registerUndoSnapshot(label: "Restore Appearance")
            store.theme = decoded.backup.theme

            var preferences = store.preferences
            preferences.hapticsEnabled = decoded.backup.preferences.hapticsEnabled
            preferences.reducedAnimations = decoded.backup.preferences.reducedAnimations
            preferences.collapsedFolderIDs = decoded.backup.preferences.collapsedFolderIDs
            store.preferences = preferences

            if let cosmetics = decoded.cosmetics {
                apply(cosmetics, store: store)
            }
        }
    }

    enum ImportMode {
        case mergeData
        case replaceEverything
        case appearanceOnly
    }

    private static func decode(_ url: URL) throws -> (backup: TallyBackup, cosmetics: TallyCosmeticSnapshot?) {
        let data = try Data(contentsOf: url)

        if let envelope = try? decoder.decode(TallyPortableBackupEnvelope.self, from: data) {
            return (envelope.data, envelope.cosmetics)
        }

        let legacy = try decoder.decode(TallyBackup.self, from: data)
        return (legacy, nil)
    }

    private static func writeTemporaryCoreBackup(_ backup: TallyBackup) throws -> URL {
        let data = try encoder.encode(backup)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tally_Core_Import_\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func currentCosmetics() -> TallyCosmeticSnapshot {
        let defaults = UserDefaults.standard
        let accent = defaults.string(forKey: StoredAccentColor.presetKey)
            ?? TallyAccentColor.blue.rawValue
        let custom = defaults.string(forKey: StoredAccentColor.customKey)
            ?? "FF1883"

        #if canImport(UIKit)
        let icon = UIApplication.shared.alternateIconName
        #else
        let icon: String? = nil
        #endif

        return TallyCosmeticSnapshot(
            accentColorRaw: accent,
            customAccentHex: custom,
            alternateIconName: icon
        )
    }

    private static func apply(_ cosmetics: TallyCosmeticSnapshot, store: TallyStore) {
        UserDefaults.standard.set(cosmetics.accentColorRaw, forKey: StoredAccentColor.presetKey)
        UserDefaults.standard.set(
            TallyStoredColor.normalizedHex(cosmetics.customAccentHex),
            forKey: StoredAccentColor.customKey
        )

        #if canImport(UIKit)
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != cosmetics.alternateIconName else {
            return
        }

        UIApplication.shared.setAlternateIconName(cosmetics.alternateIconName)
        #endif
    }

    private static func accentTitle(_ raw: String?) -> String {
        guard let raw else { return "Not included" }
        if raw == StoredAccentColor.customValue { return "Custom" }
        return TallyAccentColor(rawValue: raw)?.title ?? raw.capitalized
    }

    private static func iconTitle(_ iconName: String?) -> String {
        guard let iconName else { return "Classic Blue" }
        return TallyIcon.allCases.first(where: { $0.iconName == iconName })?.title ?? iconName
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}
