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
    
    func setAssets(_ fetchResult: PHFetchResult<PHAsset>) {
        self.fetchResult = fetchResult
        self.processedAssetIds.removeAll()
        self.pendingDeleteAssets.removeAll()
        self.decisionHistory.removeAll()
        nextBatch()
    }
    
    var hasMorePhotos: Bool {
        guard let fetchResult = fetchResult else { return false }
        return processedAssetIds.count < fetchResult.count
    }
    
    func nextBatch() {
        guard let fetchResult = fetchResult else {
            currentBatch = []
            return
        }
        
        var candidates: [PhotoAsset] = []
        var triedIndicesInThisRun: Set<Int> = []
        let totalCount = fetchResult.count
        
        // Safety: If we have processed almost everything, random sampling is inefficient.
        // If remaining < 50, just linear scan.
        let remainingEstimate = totalCount - processedAssetIds.count
        
        if remainingEstimate < 50 {
             // Linear scan to find remaining
             for i in 0..<totalCount {
                 if candidates.count >= batchSize { break }
                 let asset = fetchResult.object(at: i)
                 if !processedAssetIds.contains(asset.localIdentifier) {
                     candidates.append(PhotoAsset(asset: asset))
                 }
             }
        } else {
            // Random sampling
            // Try up to 4x batch size attempts to find unmatched items to avoid infinite loops
            // if our estimate is wrong or collision rate is high.
            let maxAttempts = batchSize * 10
            var attempts = 0
            
            while candidates.count < batchSize && attempts < maxAttempts {
                attempts += 1
                let index = Int.random(in: 0..<totalCount)
                
                if triedIndicesInThisRun.contains(index) { continue }
                triedIndicesInThisRun.insert(index)
                
                let asset = fetchResult.object(at: index)
                if !processedAssetIds.contains(asset.localIdentifier) {
                    candidates.append(PhotoAsset(asset: asset))
                }
            }
        }
        
        // Sort the random selection by creation date (chronological)
        currentBatch = candidates.sorted { (a, b) -> Bool in
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
