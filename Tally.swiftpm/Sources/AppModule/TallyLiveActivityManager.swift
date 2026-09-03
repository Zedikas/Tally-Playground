import Foundation

@MainActor
final class TallyLiveActivityManager {
    static let shared = TallyLiveActivityManager()
    private init() {}

    // The single-target Swift Playground package has no widget extension target.
    // Keep the session integration point neutral so the main app remains fully
    // usable and a future App Store target can provide the ActivityKit backend.
    func startLiveActivity(for session: TallySession, store: TallyStore) async {}
    func updateLiveActivities(from store: TallyStore) async {}
    func endLiveActivity(sessionID: UUID, store: TallyStore) async {}
}
