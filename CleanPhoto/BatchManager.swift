import Foundation
import Photos
import Combine

@MainActor
final class BatchManager: ObservableObject {
    @Published private(set) var currentBatch: [PhotoAsset] = []
    @Published private(set) var pendingDeleteAssets: Set<PhotoAsset> = []
    @Published private(set) var processedAssetIds: Set<String> = []
    
    private var fetchResult: PHFetchResult<PHAsset>?
    private var decisionHistory: [String] = [] // Track order of decisions for undo
    private let batchSize = 10
    
    // We iterate through the fetch result. Since we skip processed ones, we just need to find the next N.
    // However, if we process random ones (which we don't anymore, we do chronological), we can just move forward.
    // But since `processedAssetIds` might persist or be non-contiguous if we implemented "skip" differently,
    // we should just scan. To optimize, we can keep an index if we assume we always move forward.
    // For now, let's just scan from 0? No, that's O(N) every time.
    // Let's keep `lastScannedIndex`.
    private var lastScannedIndex = 0
    
    func setAssets(_ fetchResult: PHFetchResult<PHAsset>) {
        self.fetchResult = fetchResult
        self.processedAssetIds.removeAll()
        self.pendingDeleteAssets.removeAll()
        self.decisionHistory.removeAll()
        self.lastScannedIndex = 0
        nextBatch()
    }
    
    var hasMorePhotos: Bool {
        guard let fetchResult = fetchResult else { return false }
        // Simple check: are there assets we haven't seen?
        // This is an approximation if we rely on lastScannedIndex.
        return lastScannedIndex < fetchResult.count
    }
    
    func nextBatch() {
        guard let fetchResult = fetchResult else {
            currentBatch = []
            return
        }
        
        var newBatch: [PhotoAsset] = []
        var index = lastScannedIndex
        
        while newBatch.count < batchSize && index < fetchResult.count {
            let asset = fetchResult.object(at: index)
            index += 1
            
            if !processedAssetIds.contains(asset.localIdentifier) {
                newBatch.append(PhotoAsset(asset: asset))
            }
        }
        
        lastScannedIndex = index
        currentBatch = newBatch
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
