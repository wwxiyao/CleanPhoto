import Foundation

nonisolated enum PhotoSortOrder: String, CaseIterable {
    case newestFirst
    case oldestFirst

    var title: String { self == .newestFirst ? "最新在前" : "最早在前" }

    func arranged(_ groups: [SimilarGroup]) -> [SimilarGroup] {
        groups.map { group in
            SimilarGroup(id: group.id, assets: group.assets.sorted(by: precedes), selectedForDelete: group.selectedForDelete)
        }.sorted { lhs, rhs in
            guard let a = lhs.assets.first, let b = rhs.assets.first else { return !lhs.assets.isEmpty && rhs.assets.isEmpty }
            return precedes(a, b)
        }
    }

    private func precedes(_ lhs: PhotoAsset, _ rhs: PhotoAsset) -> Bool {
        switch (lhs.creationDate, rhs.creationDate) {
        case let (a?, b?) where a != b: return self == .newestFirst ? a > b : a < b
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.id < rhs.id
        }
    }
}
