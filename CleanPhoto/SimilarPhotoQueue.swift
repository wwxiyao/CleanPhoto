import Combine
import Foundation

nonisolated struct SimilarSearchLimits {
    var maximumPhotoInspections = 12_000
    var maximumFeatureRequests = 80
    var maximumDuration: Duration = .seconds(2)
    var maximumPages = 64
}

@MainActor
final class SimilarPhotoQueue: ObservableObject {
    @Published private(set) var sortOrder: PhotoSortOrder = .newestFirst
    private var sortRevision = 0
    @Published var groups: [SimilarGroup] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isExhausted = false
    @Published private(set) var hasCompletedSearch = false
    @Published private var refillScheduled = false

    var selectedAssets: [PhotoAsset] {
        var seen: Set<String> = []
        return groups.flatMap(\.assetsToDelete).filter { seen.insert($0.id).inserted }
    }

    var isPreparing: Bool { isLoading || refillScheduled }
    var shouldShowSearchPlaceholder: Bool { isPreparing || !hasCompletedSearch }

    private var targetCount = 10
    private let refillThreshold = 3
    private let photoBudget = 240
    private let loadPage: (SimilarityPageRequest) async -> SimilarScanPage
    private var seenSignatures: Set<String> = []
    private var deletedIDs: Set<String> = []
    private var refillTask: Task<Void, Never>?
    private var isActive = false
    private var pendingRefillDemand = false
    private var pendingRefillForce = false

    // Publish the first result immediately, then top up in small, bounded requests.
    private let limits: SimilarSearchLimits
    private let now: () -> ContinuousClock.Instant

    init(limits: SimilarSearchLimits = SimilarSearchLimits(), now: @escaping () -> ContinuousClock.Instant = { .now }, loadPage: @escaping (Int, Int) async -> SimilarScanPage) {
        self.limits = limits
        self.now = now
        self.loadPage = { request in await loadPage(request.groupLimit, request.photoBudget) }
    }

    init(limits: SimilarSearchLimits = SimilarSearchLimits(), now: @escaping () -> ContinuousClock.Instant = { .now }, scanPage: @escaping (SimilarityPageRequest) async -> SimilarScanPage) {
        self.limits = limits
        self.now = now
        loadPage = scanPage
    }

    func setSortOrder(_ order: PhotoSortOrder) {
        groups = order.arranged(groups)
        guard sortOrder != order else { return }
        sortOrder = order
        sortRevision += 1
        refillTask?.cancel()
        isExhausted = false
        hasCompletedSearch = false
        targetCount = max(10, groups.count + 10)
        requestRefill(force: true)
    }

    func setOverviewMode(_ overview: Bool) {
        targetCount = overview ? max(10, groups.count) : 10
    }

    func requestMoreForBrowsing(near groupID: UUID? = nil) {
        guard isActive, !isExhausted else { return }
        if let groupID {
            guard let index = groups.firstIndex(where: { $0.id == groupID }), groups.count - index <= refillThreshold else { return }
        }
        if groups.count >= targetCount { targetCount = groups.count + 10 }
        requestRefill(force: true)
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active { requestRefill() } else { refillTask?.cancel() }
    }

    func requestRefill(force: Bool = false) {
        guard isActive, !isExhausted, groups.count < targetCount,
              force || groups.count <= refillThreshold else { return }
        guard refillTask == nil else {
            pendingRefillDemand = true
            pendingRefillForce = pendingRefillForce || force
            return
        }
        refillScheduled = true
        refillTask = Task { [weak self] in
            guard let self else { return }
            await loadIfNeeded(force: force)
            refillTask = nil
            refillScheduled = false
            let requestedWhileLoading = pendingRefillDemand
            let requestedForce = pendingRefillForce
            pendingRefillDemand = false
            pendingRefillForce = false
            // If the app became active again during cancellation, resume once.
            if isActive, Task.isCancelled || requestedWhileLoading { requestRefill(force: requestedForce) }
        }
    }

    func loadIfNeeded(force: Bool = false) async {
        guard !isLoading, !isExhausted, !Task.isCancelled,
              groups.count < targetCount, force || groups.count <= refillThreshold else { return }
        isLoading = true
        refillScheduled = false
        defer { isLoading = false }
        let revision = sortRevision
        let started = now()
        var inspected = 0
        var featureRequests = 0
        var canDrainBuffer = false
        for _ in 0..<limits.maximumPages {
            guard groups.count < targetCount, !isExhausted, !Task.isCancelled else { break }
            let hasWorkBudget = inspected < limits.maximumPhotoInspections
                && featureRequests < limits.maximumFeatureRequests
                && now() - started < limits.maximumDuration
            guard hasWorkBudget || canDrainBuffer else { break }
            let limit = groups.isEmpty ? 1 : min(3, targetCount - groups.count)
            let budget = hasWorkBudget ? min(photoBudget, limits.maximumPhotoInspections - inspected) : 0
            let page = await loadPage(SimilarityPageRequest(groupLimit: limit, photoBudget: budget,
                                                          featureBudget: max(0, limits.maximumFeatureRequests - featureRequests),
                                                          sortOrder: sortOrder))
            guard !Task.isCancelled, revision == sortRevision else { return }
            inspected += page.inspectedAssetCount ?? budget
            featureRequests += page.featureRequestCount
            canDrainBuffer = page.hasBufferedGroups
            hasCompletedSearch = true
            for group in page.groups {
                let remaining = group.assets.filter { !deletedIDs.contains($0.id) }
                guard remaining.count > 1 else { continue }
                let signature = remaining.map(\.id).sorted().joined(separator: "|")
                guard seenSignatures.insert(signature).inserted else { continue }
                groups.append(SimilarGroup(id: group.id, assets: remaining))
            }
            groups = sortOrder.arranged(groups)
            isExhausted = !page.hasMore
            await Task.yield()
        }
    }

    func removeCurrentGroup() {
        guard let group = groups.first else { return }
        removeGroup(group.id)
    }

    func removeGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        requestRefill()
    }

    func skipCurrentGroup() {
        // A skipped group leaves this session's queue; swapping would cycle back.
        removeCurrentGroup()
    }

    func toggleSelection(_ assetID: String, in groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }),
              groups[index].assets.contains(where: { $0.id == assetID }) else { return }
        if groups[index].selectedForDelete.contains(assetID) {
            groups[index].selectedForDelete.remove(assetID)
        } else {
            groups[index].selectedForDelete.insert(assetID)
        }
    }

    func recordDeletedAssets(_ ids: Set<String>) {
        deletedIDs.formUnion(ids)
        groups = groups.compactMap { group in
            let remaining = group.assets.filter { !deletedIDs.contains($0.id) }
            guard remaining.count > 1 else { return nil }
            guard remaining.count != group.assets.count else { return group }
            var updated = SimilarGroup(id: group.id, assets: remaining)
            updated.selectedForDelete = group.selectedForDelete.subtracting(deletedIDs)
            return updated
        }
        requestRefill()
    }
}
