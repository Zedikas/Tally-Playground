import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum TallyStoredColor {
    static let customPrefix = "custom:"

    static func preset(_ raw: String) -> CounterColor? { CounterColor(rawValue: raw) }

    static func customHex(_ raw: String) -> String? {
        guard raw.hasPrefix(customPrefix) else { return nil }
        let hex = String(raw.dropFirst(customPrefix.count)).uppercased()
        return Color(hex: hex) == nil ? nil : hex
    }

    static func raw(customHex: String) -> String { customPrefix + normalizedHex(customHex) }

    static func normalizedHex(_ value: String) -> String {
        let clean = value.uppercased().filter { $0.isHexDigit }
        return clean.count == 6 ? clean : "0A84FF"
    }

    static func color(_ raw: String, fallback: CounterColor = .blue) -> Color {
        if let hex = customHex(raw), let color = Color(hex: hex) { return color }
        switch preset(raw) ?? fallback {
        case .blue: return Color(hex: "0A84FF") ?? .blue
        case .purple: return Color(hex: "9000FF") ?? .purple
        case .pink: return Color(hex: "FF7EFF") ?? .pink
        case .green: return Color(hex: "30D158") ?? .green
        case .orange: return Color(hex: "FF9F0A") ?? .orange
        case .red: return Color(hex: "FF453A") ?? .red
        case .teal: return Color(hex: "64D2FF") ?? .teal
        case .gray: return Color(hex: "8E8E93") ?? .gray
        }
    }

    static func title(_ raw: String, fallback: CounterColor = .blue) -> String {
        if let preset = preset(raw) { return preset.title }
        if let hex = customHex(raw) { return "#\(hex)" }
        return fallback.title
    }

    #if canImport(UIKit)
    static func swatchImage(_ color: Color, selected: Bool) -> UIImage {
        let size = CGSize(width: 22, height: 22)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            UIColor(color).setFill()
            context.cgContext.fillEllipse(in: rect)
            if selected {
                UIColor.white.setStroke()
                context.cgContext.setLineWidth(2)
                context.cgContext.strokeEllipse(in: rect.insetBy(dx: 2, dy: 2))
                context.cgContext.setLineWidth(2.2)
                context.cgContext.setLineCap(.round)
                context.cgContext.move(to: CGPoint(x: 7, y: 11))
                context.cgContext.addLine(to: CGPoint(x: 10, y: 14))
                context.cgContext.addLine(to: CGPoint(x: 16, y: 7))
                context.cgContext.strokePath()
            }
        }.withRenderingMode(.alwaysOriginal)
    }
    #endif
}

struct StoredColorMenu: View {
    let title: String
    let systemImage: String
    @Binding var rawValue: String
    @Binding var customColor: Color
    @Binding var showingCustomPicker: Bool

    private var resolved: Color { TallyStoredColor.color(rawValue) }

    var body: some View {
        Menu {
            ForEach(CounterColor.allCases) { option in
                Button { rawValue = option.rawValue } label: {
                    #if canImport(UIKit)
                    Label {
                        Text(option.title)
                    } icon: {
                        Image(uiImage: TallyStoredColor.swatchImage(TallyStoredColor.color(option.rawValue), selected: rawValue == option.rawValue))
                            .renderingMode(.original)
                    }
                    #else
                    Text(option.title)
                    #endif
                }
            }
            Divider()
            Button {
                customColor = resolved
                showingCustomPicker = true
            } label: {
                Label("Custom Color…", systemImage: "paintpalette.fill")
            }
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: systemImage).foregroundStyle(resolved)
                Text(TallyStoredColor.title(rawValue)).foregroundStyle(resolved)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(resolved)
            }
        }
    }
}

struct CustomStoredColorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var rawValue: String
    @Binding var color: Color

    var body: some View {
        NavigationStack {
            Form {
                Section("Custom Color") {
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                    HStack {
                        Circle().fill(color).frame(width: 30, height: 30)
                        Text("#\(color.hexString())").font(.system(.body, design: .monospaced))
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Color") {
                        rawValue = TallyStoredColor.raw(customHex: color.hexString())
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

extension TallyStore {
    private var folderColorDefaultsKey: String { "tally.folderColors.v161" }

    private func storedFolderColors() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: folderColorDefaultsKey),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }

    func folderColorRaw(for group: String) -> String {
        if let folder = folder(named: group) { return folder.colorRaw }
        if let stored = storedFolderColors()[group] { return stored }
        return activeCounters.first(where: { $0.displayGroup == group })?.folderColorName ?? CounterColor.gray.rawValue
    }

    func updateFolderColor(group: String, rawValue: String) {
        var values = storedFolderColors()
        values[group] = rawValue
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: folderColorDefaultsKey) }
        var folderValues = folders
        if let index = folderValues.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(group) == .orderedSame }) {
            folderValues[index].colorRaw = rawValue
            folders = folderValues
        }
        for index in counters.indices where counters[index].displayGroup == group {
            counters[index].folderColorName = rawValue
            counters[index].updatedAt = Date()
        }
    }
}

struct TallySurfaceModifier: ViewModifier {
    @EnvironmentObject private var store: TallyStore
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(store.theme == .oled ? .hidden : .automatic)
            .background(store.theme == .oled ? Color.black : Color.clear)
    }
}

extension View {
    func tallyOLEDBackground() -> some View { modifier(TallySurfaceModifier()) }
}
