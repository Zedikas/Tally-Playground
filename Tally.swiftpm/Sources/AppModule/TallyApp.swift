import SwiftUI

@main
struct TallyApp: App {
    @StateObject private var store = TallyStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TallyMainTabsView()
                .environmentObject(store)
                .preferredColorScheme(store.theme.colorScheme)
                .onAppear {
                    activateAppServices()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    activateAppServices()
                }
                .onChange(of: store.counters) { _, _ in
                    #if TALLY_FULL_SIGNING || TALLY_APPDB_EXTENSIONS
                    TallyFullSigningBridge.shared.publishWidgetSnapshot(from: store)
                    #endif
                }
                .onChange(of: store.sessions) { _, _ in
                    #if TALLY_FULL_SIGNING || TALLY_APPDB_EXTENSIONS
                    Task { await TallyFullSigningBridge.shared.updateLiveActivities(from: store) }
                    #endif
                }
        }
    }

    private func activateAppServices() {
        store.performScheduledResets()
        store.rescheduleAllResetNotifications()

        #if TALLY_FULL_SIGNING || TALLY_APPDB_EXTENSIONS
        _ = TallyFullSigningBridge.shared.consumePendingExtensionActions(into: store)
        TallyFullSigningBridge.shared.publishWidgetSnapshot(from: store)
        Task { await TallyFullSigningBridge.shared.updateLiveActivities(from: store) }
        #endif

        #if TALLY_FULL_SIGNING
        let shouldSync = store.preferences.lastSyncAt.map {
            Date().timeIntervalSince($0) > 300
        } ?? true
        if shouldSync {
            Task {
                try? await TallyCloudAutoSyncCoordinator.shared.synchronize(store: store)
                await MainActor.run {
                    TallyFullSigningBridge.shared.publishWidgetSnapshot(from: store)
                }
            }
        }
        #endif
    }
}
