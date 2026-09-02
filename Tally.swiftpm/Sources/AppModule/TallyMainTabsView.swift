import SwiftUI

struct TallyMainTabsView: View {
    private enum Tab: Hashable {
        case counters
        case sessions
        case stats
        case history
        case settings
    }

    @EnvironmentObject private var store: TallyStore
    @AppStorage(StoredAccentColor.presetKey) private var accentColorRaw = TallyAccentColor.blue.rawValue
    @AppStorage(StoredAccentColor.customKey) private var customAccentHex = "FF1883"

    @State private var selectedTab: Tab = .counters
    @State private var showingOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            CountersView()
                .tag(Tab.counters)
                .tabItem {
                    Label("Counters", systemImage: "number.circle.fill")
                }

            SessionsView()
                .tag(Tab.sessions)
                .tabItem {
                    Label("Sessions", systemImage: "timer")
                }

            StatsView()
                .tag(Tab.stats)
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.xaxis")
                }

            HistoryView()
                .tag(Tab.history)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            SettingsView()
                .tag(Tab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(StoredAccentColor.resolve(accentColorRaw, customHex: customAccentHex))
        .background {
            if store.theme == .oled {
                Color.black.ignoresSafeArea()
            }
        }
        .task {
            store.ensureFoldersMigrated()
            store.performScheduledResets()
            store.rescheduleAllResetNotifications()
            if !store.preferences.onboardingCompleted {
                showingOnboarding = true
            }
        }
        .sheet(isPresented: $showingOnboarding) {
            TallyOnboardingView()
                .environmentObject(store)
        }
    }
}
