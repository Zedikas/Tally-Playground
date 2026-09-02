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
        }
    }

    private func activateAppServices() {
        store.performScheduledResets()
        store.rescheduleAllResetNotifications()
    }
}
