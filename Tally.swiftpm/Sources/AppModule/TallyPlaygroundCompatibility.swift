import Foundation

#if !TALLY_FULL_SIGNING && !TALLY_APPDB_EXTENSIONS
@MainActor
final class TallyFullSigningBridge {
    static let shared = TallyFullSigningBridge()
    private init() {}

    func startLiveActivity(for session: TallySession, store: TallyStore) async {}
    func updateLiveActivities(from store: TallyStore) async {}
    func endLiveActivity(sessionID: UUID, store: TallyStore) async {}
}
#endif
