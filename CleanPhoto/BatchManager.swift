import Foundation
import Photos
import Combine

@MainActor
final class BatchManager: ObservableObject {
    @Published private(set) var currentBatch: [PhotoAsset] = []
    @Published private(set) var pendingDeleteAssets: Set<PhotoAsset> = []
    @Published private(set) var processedAssetIds: Set<String> = []
    @Published var isReviewingBatch = false {
        didSet { persistSession() }
    }
    @Published private(set) var currentIndex = 0
    
    private var fetchResult: PHFetchResult<PHAsset>?
    private var decisionHistory: [String] = [] // Preserve the current position across launches.
    private let batchSize = 10
    private let sessionStore: ReviewSessionStore

    init(sessionStore: ReviewSessionStore? = nil) {
        self.sessionStore = sessionStore ?? ReviewSessionStore()
    }
    
    func setAssets(_ fetchResult: PHFetchResult<PHAsset>) {
        self.fetchResult = fetchResult
        if let snapshot = sessionStore.load() {
            let available = availableAssets(in: fetchResult)
            let validIDs = Set(available.keys)
            processedAssetIds = snapshot.processedIDs.intersection(validIDs)
            currentBatch = snapshot.batchIDs.compactMap { available[$0] }
            let batchIDs = Set(currentBatch.map(\.id))
            decisionHistory = snapshot.decisionHistory.filter { batchIDs.contains($0) }
            pendingDeleteAssets = Set(currentBatch.filter { snapshot.pendingDeleteIDs.contains($0.id) })
            currentIndex = decisionHistory.count
            isReviewingBatch = snapshot.isReviewingBatch && !currentBatch.isEmpty
            if currentBatch.isEmpty {
                nextBatch()
            } else {
                persistSession()
            }
        } else {
            nextBatch()
        }
    }

    func restart() {
        processedAssetIds.removeAll()
        pendingDeleteAssets.removeAll()
        decisionHistory.removeAll()
        nextBatch()
    }

    func refreshAssetsPreservingSession(_ fetchResult: PHFetchResult<PHAsset>) {
        self.fetchResult = fetchResult

        let validAssetIDs = Set((0..<fetchResult.count).map { fetchResult.object(at: $0).localIdentifier })
        processedAssetIds = processedAssetIds.intersection(validAssetIDs)
        pendingDeleteAssets = Set(pendingDeleteAssets.filter { validAssetIDs.contains($0.id) })
        decisionHistory = decisionHistory.filter { validAssetIDs.contains($0) }
        currentBatch = currentBatch.filter { validAssetIDs.contains($0.id) }
        currentIndex = decisionHistory.count
        persistSession()
    }
    
    var hasMorePhotos: Bool {
        guard let fetchResult = fetchResult else { return false }
        return processedAssetIds.count < fetchResult.count
    }
    
    func nextBatch() {
        pendingDeleteAssets.removeAll()
        decisionHistory.removeAll()
        currentIndex = 0
        isReviewingBatch = false
        guard let fetchResult = fetchResult else {
            currentBatch = []
            return
        }
        
        var candidates: [PhotoAsset] = []
        var selectedAssetIDs: Set<String> = []
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
                 let assetID = asset.localIdentifier
                 if !processedAssetIds.contains(assetID), selectedAssetIDs.insert(assetID).inserted {
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
                let assetID = asset.localIdentifier
                if !processedAssetIds.contains(assetID), selectedAssetIDs.insert(assetID).inserted {
                    candidates.append(PhotoAsset(asset: asset))
                }
            }
        }

        // If random sampling failed to fill the batch, top up linearly to keep stable batch sizes.
        if candidates.count < batchSize {
            for index in 0..<totalCount {
                if candidates.count >= batchSize { break }
                let asset = fetchResult.object(at: index)
                let assetID = asset.localIdentifier
                if !processedAssetIds.contains(assetID), selectedAssetIDs.insert(assetID).inserted {
                    candidates.append(PhotoAsset(asset: asset))
                }
            }
        }
        
        // Stable sort: creation date first, fallback to id for nil dates.
        currentBatch = candidates.sorted { a, b in
            switch (a.creationDate, b.creationDate) {
            case let (dateA?, dateB?):
                if dateA == dateB {
                    return a.id < b.id
                }
                return dateA < dateB
            case (nil, nil):
                return a.id < b.id
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            }
        }
        
        decisionHistory.removeAll()
        persistSession()
    }
    
    func markAsDelete(_ asset: PhotoAsset) {
        guard currentIndex < currentBatch.count, currentBatch[currentIndex].id == asset.id else { return }
        pendingDeleteAssets.insert(asset)
        processedAssetIds.insert(asset.id)
        decisionHistory.append(asset.id)
        currentIndex = decisionHistory.count
        persistSession()
        // Do not remove from currentBatch so we can swipe back
    }
    
    func markAsKeep(_ asset: PhotoAsset) {
        guard currentIndex < currentBatch.count, currentBatch[currentIndex].id == asset.id else { return }
        processedAssetIds.insert(asset.id)
        decisionHistory.append(asset.id)
        currentIndex = decisionHistory.count
        persistSession()
        // Do not remove from currentBatch so we can swipe back
    }
    
    func recoverAsset(_ asset: PhotoAsset) {
        pendingDeleteAssets.remove(asset)
        persistSession()
        // Note: For now, we don't put it back in the current batch immediately 
        // as the user is usually on the review screen when recovering.
        // It will just not be deleted.
    }
    
    func clearPendingDeletes() {
        pendingDeleteAssets.removeAll()
        persistSession()
    }

    private func availableAssets(in result: PHFetchResult<PHAsset>) -> [String: PhotoAsset] {
        var available: [String: PhotoAsset] = [:]
        for index in 0..<result.count {
            let photo = PhotoAsset(asset: result.object(at: index))
            available[photo.id] = photo
        }
        return available
    }

    private func persistSession() {
        // Do not replace a saved session before the first authorized fetch finishes.
        guard fetchResult != nil else { return }
        sessionStore.save(ReviewSessionSnapshot(
            processedIDs: processedAssetIds,
            batchIDs: currentBatch.map(\.id),
            pendingDeleteIDs: Set(pendingDeleteAssets.map(\.id)),
            decisionHistory: decisionHistory,
            isReviewingBatch: isReviewingBatch
        ))
    }
}
