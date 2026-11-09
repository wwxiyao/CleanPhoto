import Foundation

nonisolated struct SimilarityPageRequest {
    let groupLimit: Int
    let photoBudget: Int
    let featureBudget: Int
    var sortOrder: PhotoSortOrder = .newestFirst
}

nonisolated struct SimilarGroup: Identifiable {
    let id: UUID
    let assets: [PhotoAsset]
    var selectedForDelete: Set<String> = []

    init(id: UUID = UUID(), assets: [PhotoAsset], selectedForDelete: Set<String> = []) {
        self.id = id
        self.assets = assets
        self.selectedForDelete = selectedForDelete
    }

    var assetsToDelete: [PhotoAsset] {
        assets.filter { selectedForDelete.contains($0.id) }
    }
}

nonisolated struct SimilarScanPage {
    let groups: [SimilarGroup]
    let hasMore: Bool
    let inspectedAssetCount: Int?
    let featureRequestCount: Int
    let hasBufferedGroups: Bool

    init(groups: [SimilarGroup], hasMore: Bool, inspectedAssetCount: Int? = nil, featureRequestCount: Int = 0, hasBufferedGroups: Bool = false) {
        self.groups = groups
        self.hasMore = hasMore
        self.inspectedAssetCount = inspectedAssetCount
        self.featureRequestCount = featureRequestCount
        self.hasBufferedGroups = hasBufferedGroups
    }
}
