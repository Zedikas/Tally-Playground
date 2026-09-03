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
                    NavigationLink { AppearanceSettingsView() } label: {
                        SettingsNavigationRow(title: "Appearance", subtitle: "Theme, accent presets, and custom color", systemImage: "paintbrush.fill")
                    }
                    NavigationLink { AppIconSettingsView() } label: {
                        SettingsNavigationRow(title: "App Icon", subtitle: "Choose from the complete Tally icon family", systemImage: "app.badge.fill")
                    }
                }

                Section("Behavior") {
                    Toggle(isOn: $store.preferences.hapticsEnabled) {
                        Label("Haptic Feedback", systemImage: "waveform.path")
                    }
                    Toggle(isOn: $store.preferences.reducedAnimations) {
                        Label("Reduce Tally Animations", systemImage: "figure.walk.motion")
                    }
                    Button { showingOnboarding = true } label: {
                        Label("Show Welcome Guide", systemImage: "sparkles.rectangle.stack")
                    }
                }

                Section("Data & Sync") {
                    NavigationLink { SyncCenterView() } label: {
                        SettingsNavigationRow(
                            title: "Sync Center",
                            subtitle: "Full backups, appearance restore, Android interchange, and diagnostics",
                            systemImage: "arrow.triangle.2.circlepath.icloud",
                            value: "r\(store.preferences.syncRevision)"
                        )
                    }
                }

                Section("Counter Management") {
                    NavigationLink { ArchivedCountersView() } label: {
                        SettingsNavigationRow(title: "Archived Counters", subtitle: "Restore or permanently remove counters", systemImage: "archivebox.fill", value: "\(store.archivedCounters.count)")
                    }
                    LabeledContent("Pinned Counters", value: "\(store.activeCounters.filter(\.isPinned).count)")
                    LabeledContent("Locked Counters", value: "\(store.activeCounters.filter(\.isLocked).count)")
                    LabeledContent("Folders", value: "\(store.folders.count)")
                }

                Section("About") {
                    LabeledContent("Version", value: versionText)
                    LabeledContent("Data Schema", value: "2.0")
                    Button("Changelog") { showingChangelog = true }
                }
            }
            .tallyOLEDBackground()
            .navigationTitle("Settings")
            .sheet(isPresented: $showingChangelog) { ChangelogView() }
            .sheet(isPresented: $showingOnboarding) {
                TallyOnboardingView().environmentObject(store)
            }
        }
    }
}

