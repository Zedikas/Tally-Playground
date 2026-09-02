import Foundation

// Allows the v1.7 folder creation guard to resolve the existing-folder lookup
// even though its local parameter is also named `folder`.
extension TallyFolder {
    func callAsFunction(named name: String) -> TallyFolder? {
        guard let data = UserDefaults.standard.data(forKey: "tally.folders.v1"),
              let storedFolders = try? JSONDecoder().decode([TallyFolder].self, from: data) else {
            return nil
        }

        return storedFolders.first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }
}
