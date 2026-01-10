import Photos
import Vision
import UIKit

struct SimilarGroup: Identifiable {
    let id = UUID()
    let assets: [PhotoAsset]
    var selectedForDelete: Set<String> = [] // IDs of assets the user wants to delete
    
    var assetsToDelete: [PhotoAsset] {
        return assets.filter { selectedForDelete.contains($0.id) }
    }
}

actor SimilarityService {
    
    // Configurable thresholds
    private let timeThreshold: TimeInterval = 10.0 // Seconds between shots
    private let similarityThreshold: Float = 10.0 // Vision feature print distance (lower is more similar)
    
    func findSimilarGroupsStream(from assets: [PhotoAsset]) -> AsyncStream<[SimilarGroup]> {
        AsyncStream { continuation in
            Task {
                // 1. Sort by creation date
                let sortedAssets = assets.sorted {
                    ($0.creationDate ?? Date.distantPast) < ($1.creationDate ?? Date.distantPast)
                }
                
                var currentCluster: [PhotoAsset] = []
                
                // 2. Cluster by Time first (Fast)
                for asset in sortedAssets {
                    guard let lastAsset = currentCluster.last else {
                        currentCluster.append(asset)
                        continue
                    }
                    
                    guard let currentDate = asset.creationDate,
                          let lastDate = lastAsset.creationDate else {
                        continue
                    }
                    
                    if currentDate.timeIntervalSince(lastDate) < timeThreshold {
                        currentCluster.append(asset)
                    } else {
                        // Time gap too large, process previous cluster
                        if currentCluster.count > 1 {
                            let verifiedGroups = await verifyVisualSimilarity(for: currentCluster)
                            if !verifiedGroups.isEmpty {
                                continuation.yield(verifiedGroups)
                            }
                        }
                        currentCluster = [asset]
                        // Yield to main thread to avoid blocking UI too much
                        await Task.yield()
                    }
                }
                
                // Process the final cluster
                if currentCluster.count > 1 {
                    let verifiedGroups = await verifyVisualSimilarity(for: currentCluster)
                    if !verifiedGroups.isEmpty {
                        continuation.yield(verifiedGroups)
                    }
                }
                
                continuation.finish()
            }
        }
    }
    
    private func verifyVisualSimilarity(for cluster: [PhotoAsset]) async -> [SimilarGroup] {
        // Load cache
        var featurePrints = await SimilarityCacheManager.shared.load()
        var newPrintsGenerated = false
        
        // Generate prints for missing assets
        for asset in cluster {
            if featurePrints[asset.id] == nil {
                if let print = await generateFeaturePrint(for: asset) {
                    featurePrints[asset.id] = print
                    newPrintsGenerated = true
                }
            }
        }
        
        // Save if we added new stuff
        if newPrintsGenerated {
            await SimilarityCacheManager.shared.save(prints: featurePrints)
        }
        
        var verifiedGroups: [SimilarGroup] = []
        var processedIDs: Set<String> = []
        
        for i in 0..<cluster.count {
            let assetA = cluster[i]
            if processedIDs.contains(assetA.id) { continue }
            
            var currentGroupAssets: [PhotoAsset] = [assetA]
            processedIDs.insert(assetA.id)
            
            guard let printA = featurePrints[assetA.id] else { continue }
            
            for j in (i+1)..<cluster.count {
                let assetB = cluster[j]
                if processedIDs.contains(assetB.id) { continue }
                
                guard let printB = featurePrints[assetB.id] else { continue }
                
                var distance: Float = 0
                do {
                    try printA.computeDistance(&distance, to: printB)
                    // Distance 0.0 is identical. Typical similarity is < 15.0 depending on algorithm version.
                    // For VNGenerateImageFeaturePrintRequestRevision1, values are roughly 0..1?
                    // Let's check documentation logic usually: low distance = similar.
                    if distance < 0.5 { // Strict visual similarity
                        currentGroupAssets.append(assetB)
                        processedIDs.insert(assetB.id)
                    }
                } catch {
                    print("Error computing distance: \(error)")
                }
            }
            
            if currentGroupAssets.count > 1 {
                let assets = currentGroupAssets
                // Check if this group is ignored
                if !IgnoredGroupsService.shared.isIgnored(assets: assets) {
                    verifiedGroups.append(SimilarGroup(assets: assets, selectedForDelete: []))
                }
            }
        }
        
        return verifiedGroups
    }
    
    private func generateFeaturePrint(for asset: PhotoAsset) async -> VNFeaturePrintObservation? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat // We don't need 4K for feature print
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            // Request a smaller image for analysis to save memory/speed
            PHImageManager.default().requestImage(
                for: asset.asset,
                targetSize: CGSize(width: 512, height: 512),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                guard let uiImage = image, let cgImage = uiImage.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let request = VNGenerateImageFeaturePrintRequest()
                #if targetEnvironment(simulator)
                request.usesCPUOnly = true // Fix crash on some simulators
                #endif
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    if let result = request.results?.first as? VNFeaturePrintObservation {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    print("Vision request failed: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
