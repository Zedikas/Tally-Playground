import Foundation

extension TallyFolder {
    /// Lets the drop target resolve a dragged folder payload even when its local
    /// `folder` parameter shadows the helper method in CountersView.
    func callAsFunction(from payload: String) -> TallyFolder? {
        guard payload.hasPrefix("folder:"),
              let sourceID = UUID(uuidString: String(payload.dropFirst("folder:".count))) else {
            return nil
        }
        var reference = self
        reference.id = sourceID
        return reference
    }
}
