import Foundation
import Photos
import Combine

@MainActor
final class BatchManager: ObservableObject {
    @Published private(set) var currentBatch: [PhotoAsset] = []
    @Published private(set) var pendingDeleteAssets: Set<PhotoAsset> = []
    @Published private(set) var processedAssetIds: Set<String> = []
    
    private var allAssets: [PhotoAsset] = []
    private let batchSize = 10
    
    func setAssets(_ assets: [PhotoAsset]) {
        self.allAssets = assets
        self.processedAssetIds.removeAll()
        self.pendingDeleteAssets.removeAll()
        nextBatch()
    }
    
    var hasMorePhotos: Bool {
        unprocessedAssets.count > 0
    }
    
    private var unprocessedAssets: [PhotoAsset] {
        allAssets.filter { !processedAssetIds.contains($0.id) }
    }
    
    func nextBatch() {
        let available = unprocessedAssets
        guard !available.isEmpty else {
            currentBatch = []
            return
        }
        
        // Randomly pick up to 10 assets
        let count = min(available.count, batchSize)
        let randomSelection = available.shuffled().prefix(count)
        
        // Sort the selection by creation date (chronological)
        currentBatch = randomSelection.sorted { (a, b) -> Bool in
            guard let dateA = a.creationDate, let dateB = b.creationDate else { return false }
            return dateA < dateB
        }
    }
    
    func markAsDelete(_ asset: PhotoAsset) {
        pendingDeleteAssets.insert(asset)
        processedAssetIds.insert(asset.id)
        currentBatch.removeAll { $0.id == asset.id }
    }
    
    func markAsKeep(_ asset: PhotoAsset) {
        processedAssetIds.insert(asset.id)
        currentBatch.removeAll { $0.id == asset.id }
    }
    
    func recoverAsset(_ asset: PhotoAsset) {
        pendingDeleteAssets.remove(asset)
        // Note: For now, we don't put it back in the current batch immediately 
        // as the user is usually on the review screen when recovering.
        // It will just not be deleted.
    }
    
    func clearPendingDeletes() {
        pendingDeleteAssets.removeAll()
    }
}
