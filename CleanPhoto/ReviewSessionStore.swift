import Foundation

struct ReviewSessionSnapshot: Codable {
    var version = 1
    let processedIDs: Set<String>
    let batchIDs: [String]
    let pendingDeleteIDs: Set<String>
    let decisionHistory: [String]
    let isReviewingBatch: Bool
}

@MainActor
final class ReviewSessionStore {
    private let defaults: UserDefaults
    private let key = "CleanPhoto.reviewSession.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ReviewSessionSnapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(ReviewSessionSnapshot.self, from: data),
              snapshot.version == 1 else { return nil }
        return snapshot
    }

    func save(_ snapshot: ReviewSessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
