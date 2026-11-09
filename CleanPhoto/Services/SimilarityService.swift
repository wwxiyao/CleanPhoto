import Photos
import Vision
#if canImport(UIKit)
import UIKit
#else
import AppKit
private typealias UIImage = NSImage
#endif
import OSLog

actor SimilarityService {
    private let similarityThreshold: Float = 0.5
    private let maxFeaturePrintConcurrency = 6
    private let fetchResult: PHFetchResult<PHAsset>?
    private var sortOrder: PhotoSortOrder?
    private var cursor: SimilarityScanCursor
    private var bufferedGroups: [SimilarGroup] = []
    private var featurePrints: [String: VNFeaturePrintObservation] = [:]
    private var cacheLoaded = false
    private var cacheDirty = false
    private var isPaging = false
    private var featureRequestsThisPage = 0
    private var cacheSaveTask: Task<Void, Never>?
    private var saveGeneration = 0
    private let log = Logger(subsystem: "wxynjx.CleanPhoto", category: "SimilarPhotos")
    private let verifier: (@Sendable ([PhotoAsset]) async -> (groups: [SimilarGroup], cacheDirty: Bool))?
    private let cacheLoader: (@Sendable () async -> [String: VNFeaturePrintObservation])?
    private let cacheSaver: (@Sendable ([String: VNFeaturePrintObservation]) async -> Void)?

    init(
        fetchResult: PHFetchResult<PHAsset>?,
        verifier: (@Sendable ([PhotoAsset]) async -> (groups: [SimilarGroup], cacheDirty: Bool))? = nil,
        loadCache: (@Sendable () async -> [String: VNFeaturePrintObservation])? = nil,
        saveCache: (@Sendable ([String: VNFeaturePrintObservation]) async -> Void)? = nil
    ) {
        self.fetchResult = fetchResult
        cursor = SimilarityScanCursor(fetchResult: fetchResult)
        self.verifier = verifier
        cacheLoader = loadCache
        cacheSaver = saveCache
    }

    // Pull-based: no producer task runs while the consumer has enough groups.
    func nextPage(groupLimit: Int, assetBudget: Int, featureBudget: Int = 80, sortOrder: PhotoSortOrder? = nil) async -> SimilarScanPage {
        let started = Date()
        guard !isPaging, !Task.isCancelled else {
            return SimilarScanPage(groups: [], hasMore: true)
        }
        if let sortOrder, self.sortOrder != sortOrder {
            self.sortOrder = sortOrder
            cursor = SimilarityScanCursor(fetchResult: fetchResult, reversed: sortOrder == .oldestFirst)
            bufferedGroups.removeAll()
        }
        isPaging = true
        featureRequestsThisPage = 0
        defer { isPaging = false }
        cacheSaveTask?.cancel()
        saveGeneration += 1
        if !cacheLoaded {
            if let cacheLoader {
                featurePrints = await cacheLoader()
            } else {
                featurePrints = await SimilarityCacheManager.shared.load()
            }
            cacheLoaded = true
        }
        let checkpoint = cursor
        let bufferedCheckpoint = bufferedGroups
        let limit = min(10, max(1, groupLimit))
        let budget = min(240, max(0, assetBudget))
        let featureLimit = min(80, max(0, featureBudget))
        var groups: [SimilarGroup] = []
        var inspected = 0
        var pagePrints = featurePrints

        while groups.count < limit, !Task.isCancelled {
            if !bufferedGroups.isEmpty {
                let count = min(limit - groups.count, bufferedGroups.count)
                groups.append(contentsOf: bufferedGroups.prefix(count))
                bufferedGroups.removeFirst(count)
                continue
            }
            guard !cursor.isExhausted, inspected < budget else { break }
            let clusterCheckpoint = cursor
            let cluster = cursor.nextCluster(assetBudget: budget - inspected)
            inspected += cluster.inspectedCount
            if cluster.assets.count > 1 {
                let candidates = SimilarityClusterSegmentation.segments(cluster.assets, isLargeCluster: cluster.isLargeCluster).flatMap { $0 }
                let missing = candidates.filter { pagePrints[$0.id] == nil }
                if verifier == nil, featureRequestsThisPage + missing.count > featureLimit {
                    if featureRequestsThisPage == 0, featureLimit > 0 {
                        let generated = await generateFeaturePrints(for: Array(missing.prefix(featureLimit)))
                        for (id, observation) in generated { pagePrints[id] = observation }
                        cacheDirty = cacheDirty || !generated.isEmpty
                    }
                    cursor = clusterCheckpoint
                    break
                }
                let result: (groups: [SimilarGroup], cacheDirty: Bool)
                if let verifier {
                    result = await verifier(cluster.assets)
                } else {
                    result = await processCluster(cluster.assets, isLargeCluster: cluster.isLargeCluster, featurePrints: &pagePrints)
                }
                cacheDirty = cacheDirty || result.cacheDirty
                bufferedGroups.append(contentsOf: result.groups)
            }
            await Task.yield()
        }
        featurePrints = pagePrints
        scheduleCacheSave()
        if Task.isCancelled {
            cursor = checkpoint
            bufferedGroups = bufferedCheckpoint
            return SimilarScanPage(groups: [], hasMore: true)
        }
        log.info("Similar page ready: groups=\(groups.count), inspected=\(inspected), featureRequests=\(self.featureRequestsThisPage), seconds=\(Date().timeIntervalSince(started))")
        return SimilarScanPage(groups: groups, hasMore: !cursor.isExhausted || !bufferedGroups.isEmpty,
                               inspectedAssetCount: inspected, featureRequestCount: featureRequestsThisPage,
                               hasBufferedGroups: !bufferedGroups.isEmpty)
    }

    private func scheduleCacheSave() {
        guard cacheDirty else { return }
        cacheSaveTask?.cancel()
        saveGeneration += 1
        let generation = saveGeneration
        cacheSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(750)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            await persistCache(generation: generation)
        }
    }

    private func persistCache(generation: Int) async {
        guard !Task.isCancelled, generation == saveGeneration else { return }
        let snapshot = featurePrints
        if let cacheSaver {
            await cacheSaver(snapshot)
        } else {
            await SimilarityCacheManager.shared.save(prints: snapshot)
        }
        guard generation == saveGeneration else { return }
        cacheDirty = false
        cacheSaveTask = nil
    }

    private func processCluster(
        _ cluster: [PhotoAsset],
        isLargeCluster: Bool,
        featurePrints: inout [String: VNFeaturePrintObservation]
    ) async -> (groups: [SimilarGroup], cacheDirty: Bool) {
        let verification = await verifyVisualSimilarity(for: cluster, isLargeCluster: isLargeCluster, featurePrints: &featurePrints)
        guard !verification.groups.isEmpty else {
            return ([], verification.cacheDirty)
        }

        let filtered = await asyncFilter(verification.groups) { group in
            !(await IgnoredGroupsService.shared.isIgnored(assets: group.assets))
        }
        return (filtered, verification.cacheDirty)
    }

    private func verifyVisualSimilarity(
        for cluster: [PhotoAsset],
        isLargeCluster: Bool,
        featurePrints: inout [String: VNFeaturePrintObservation]
    ) async -> (groups: [SimilarGroup], cacheDirty: Bool) {
        var allGroups: [SimilarGroup] = []
        var cacheDirty = false

        for subCluster in SimilarityClusterSegmentation.segments(cluster, isLargeCluster: isLargeCluster) where subCluster.count > 1 {
            if Task.isCancelled { break }

            let missingAssets = subCluster.filter { featurePrints[$0.id] == nil }
            if !missingAssets.isEmpty {
                let generated = await generateFeaturePrints(for: missingAssets)
                if !generated.isEmpty {
                    cacheDirty = true
                    for (id, printObservation) in generated {
                        featurePrints[id] = printObservation
                    }
                }
            }

            allGroups.append(contentsOf: groupVisuallySimilarAssets(in: subCluster, featurePrints: featurePrints))
        }

        return (allGroups, cacheDirty)
    }

    private func groupVisuallySimilarAssets(
        in cluster: [PhotoAsset],
        featurePrints: [String: VNFeaturePrintObservation]
    ) -> [SimilarGroup] {
        var verifiedGroups: [SimilarGroup] = []
        var groupedIDs: Set<String> = []

        for i in 0..<cluster.count {
            let assetA = cluster[i]
            if groupedIDs.contains(assetA.id) { continue }
            guard let printA = featurePrints[assetA.id] else { continue }

            var groupAssets: [PhotoAsset] = [assetA]

            for j in (i + 1)..<cluster.count {
                let assetB = cluster[j]
                if groupedIDs.contains(assetB.id) { continue }
                if !shouldCompareAssets(assetA, assetB) { continue }
                guard let printB = featurePrints[assetB.id] else { continue }

                var distance: Float = .greatestFiniteMagnitude
                do {
                    try printA.computeDistance(&distance, to: printB)
                    if distance < similarityThreshold {
                        groupAssets.append(assetB)
                    }
                } catch {
                    continue
                }
            }

            if groupAssets.count > 1 {
                for asset in groupAssets {
                    groupedIDs.insert(asset.id)
                }
                verifiedGroups.append(SimilarGroup(assets: groupAssets, selectedForDelete: []))
            }
        }

        return verifiedGroups
    }

    private func shouldCompareAssets(_ lhs: PhotoAsset, _ rhs: PhotoAsset) -> Bool {
        let ratioDiff = abs(lhs.aspectRatio - rhs.aspectRatio)
        if ratioDiff > 0.2 {
            return false
        }

        let smallerSide = max(1, min(lhs.longerSide, rhs.longerSide))
        let largerSide = max(lhs.longerSide, rhs.longerSide)
        let scaleRatio = Double(largerSide) / Double(smallerSide)
        return scaleRatio <= 2.5
    }

    private func generateFeaturePrints(
        for assets: [PhotoAsset]
    ) async -> [String: VNFeaturePrintObservation] {
        guard !assets.isEmpty else { return [:] }
        featureRequestsThisPage += assets.count

        var iterator = assets.makeIterator()
        var generated: [String: VNFeaturePrintObservation] = [:]

        await withTaskGroup(of: (String, VNFeaturePrintObservation)?.self) { group in
            for _ in 0..<min(maxFeaturePrintConcurrency, assets.count) {
                guard let next = iterator.next() else { break }
                group.addTask { [self] in
                    guard !Task.isCancelled else { return nil }
                    guard let featurePrint = await generateFeaturePrint(for: next) else { return nil }
                    return (next.id, featurePrint)
                }
            }

            while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let (id, featurePrint) = result {
                    generated[id] = featurePrint
                }

                if let next = iterator.next() {
                    group.addTask { [self] in
                        guard !Task.isCancelled else { return nil }
                        guard let featurePrint = await generateFeaturePrint(for: next) else { return nil }
                        return (next.id, featurePrint)
                    }
                }
            }
        }

        return generated
    }

    private func generateFeaturePrint(for asset: PhotoAsset) async -> VNFeaturePrintObservation? {
        let pending = FeatureImageRequest()
        let image: UIImage? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard pending.install(continuation) else { return }
                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat
                options.resizeMode = .exact
                options.isNetworkAccessAllowed = true
                options.isSynchronous = false

                let requestID = PHImageManager.default().requestImage(
                    for: asset.asset,
                    targetSize: CGSize(width: 512, height: 512),
                    contentMode: .aspectFit,
                    options: options
                ) { image, _ in
                    pending.finish(image)
                }
                pending.setRequestID(requestID)
            }
        } onCancel: {
            pending.cancel()
        }
        guard !Task.isCancelled else { return nil }
        #if canImport(UIKit)
        let cgImage = image?.cgImage
        #else
        let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
        guard let cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        #if targetEnvironment(simulator)
        request.usesCPUOnly = true
        #endif
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first
        } catch {
            return nil
        }
    }

    private func asyncFilter<T>(_ array: [T], predicate: (T) async throws -> Bool) async rethrows -> [T] {
        var result: [T] = []
        for item in array {
            if try await predicate(item) {
                result.append(item)
            }
        }
        return result
    }
}

// Photos requests outlive their Swift task unless cancellation is bridged explicitly.
nonisolated private final class FeatureImageRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var cancelled = false
    private var completed = false

    func install(_ continuation: CheckedContinuation<UIImage?, Never>) -> Bool {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(returning: nil)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func setRequestID(_ id: PHImageRequestID) {
        lock.lock()
        requestID = id
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { PHImageManager.default().cancelImageRequest(id) }
    }

    func finish(_ image: UIImage?) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: image)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let id = requestID
        lock.unlock()
        if id != PHInvalidImageRequestID { PHImageManager.default().cancelImageRequest(id) }
        finish(nil)
    }
}
