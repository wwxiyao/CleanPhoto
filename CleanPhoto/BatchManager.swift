import Foundation
import Photos
import Combine

@MainActor
final class BatchManager: ObservableObject {
    @Published private(set) var currentBatch: [PhotoAsset] = []
    @Published private(set) var pendingDeleteAssets: Set<PhotoAsset> = []
    @Published private(set) var processedAssetIds: Set<String> = []
    
    private var allAssets: [PhotoAsset] = []
    private var decisionHistory: [String] = [] // Track order of decisions for undo
    private let batchSize = 10
    
    func setAssets(_ assets: [PhotoAsset]) {
        self.allAssets = assets
        self.processedAssetIds.removeAll()
        self.pendingDeleteAssets.removeAll()
        self.decisionHistory.removeAll()
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
        decisionHistory.removeAll()
    }
    
    func markAsDelete(_ asset: PhotoAsset) {
        pendingDeleteAssets.insert(asset)
        processedAssetIds.insert(asset.id)
        decisionHistory.append(asset.id)
        // Do not remove from currentBatch so we can swipe back
    }
    
    func markAsKeep(_ asset: PhotoAsset) {
        processedAssetIds.insert(asset.id)
        decisionHistory.append(asset.id)
        // Do not remove from currentBatch so we can swipe back
    }
    
    func undo() {
        guard let lastId = decisionHistory.popLast() else { return }
        
        processedAssetIds.remove(lastId)
        
        // If it was marked for delete, remove it from there too
        if let assetToRemove = pendingDeleteAssets.first(where: { $0.id == lastId }) {
            pendingDeleteAssets.remove(assetToRemove)
        }
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
