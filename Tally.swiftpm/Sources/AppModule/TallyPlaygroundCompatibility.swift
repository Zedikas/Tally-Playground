import Foundation

#if !TALLY_FULL_SIGNING && !TALLY_APPDB_EXTENSIONS
/// Playground-safe replacement for the extension/live-activity bridge used by the full app target.
/// The core Tally app remains functional; features that require a separately signed extension are no-ops here.
@MainActor
final class TallyFullSigningBridge {
    static let shared = TallyFullSigningBridge()

    private init() {}

    func startLiveActivity(for session: TallySession, store: TallyStore) async {
        // Live Activities require the full-signing extension target and are unavailable in this package.
    }

    func updateLiveActivities(from store: TallyStore) async {
        // No-op in the Swift Playground target.
    }

    func endLiveActivity(sessionID: UUID, store: TallyStore) async {
        // No-op in the Swift Playground target.
    }
}
#endif
