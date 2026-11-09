import Foundation
import Testing
@testable import CleanPhotoLogic

@MainActor
struct SimilarPhotoQueueTests {
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        return condition()
    }

    private func group(_ index: Int) -> SimilarGroup {
        SimilarGroup(assets: [PhotoAsset(asset: FixtureAsset("\(index * 2)")), PhotoAsset(asset: FixtureAsset("\(index * 2 + 1)"))])
    }

    @Test func stopsWhenQueueHasEnoughAndRefillsAtLowWatermark() async {
        var requests: [Int] = []
        var offset = 0
        let queue = SimilarPhotoQueue { limit, _ in
            requests.append(limit)
            let groups = (offset..<(offset + limit)).map(group)
            offset += limit
            return SimilarScanPage(groups: groups, hasMore: true)
        }
        await queue.loadIfNeeded()
        #expect(queue.groups.count == 10)
        await queue.loadIfNeeded()
        #expect(requests == [1, 3, 3, 3])
        for _ in 0..<7 { queue.removeCurrentGroup() }
        await queue.loadIfNeeded()
        #expect(requests == [1, 3, 3, 3, 3, 3, 1])
        #expect(queue.groups.count == 10)
    }

    @Test func noMatchesSearchesBoundedWindowsRatherThanStoppingAfterFirst240Photos() async {
        var calls = 0
        let queue = SimilarPhotoQueue(limits: SimilarSearchLimits(maximumPhotoInspections: 960)) { _, budget in
            calls += 1
            #expect(budget == 240)
            return SimilarScanPage(groups: [], hasMore: true)
        }
        await queue.loadIfNeeded()
        #expect(calls == 4)
        #expect(!queue.isExhausted)
        #expect(!queue.isLoading)
    }

    @Test func exhaustedQueueNeverRequestsMore() async {
        var calls = 0
        let queue = SimilarPhotoQueue { _, _ in
            calls += 1
            return SimilarScanPage(groups: [], hasMore: false)
        }
        await queue.loadIfNeeded()
        await queue.loadIfNeeded()
        #expect(calls == 1)
        #expect(queue.isExhausted)
    }

    @Test func duplicateGroupsDoNotComeBackAfterConsumption() async {
        let repeated = group(1)
        let queue = SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [repeated, repeated], hasMore: true) }
        await queue.loadIfNeeded()
        #expect(queue.groups.count == 1)
        queue.removeCurrentGroup()
        await queue.loadIfNeeded()
        #expect(queue.groups.isEmpty)
    }

    @Test func deletedPhotoIsExcludedFromFutureResults() async {
        let repeated = group(1)
        let queue = SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [repeated], hasMore: true) }
        queue.recordDeletedAssets([repeated.assets[0].id])
        await queue.loadIfNeeded()
        #expect(queue.groups.isEmpty)
    }

    @Test func cursorStopsAtPhotoBudgetAndResumesCluster() {
        var cursor = SimilarityScanCursor(fetchResult: FixtureFetchResult(["0", "1", "2", "20", "21"]))
        let first = cursor.nextCluster(assetBudget: 2)
        #expect(first.inspectedCount == 2)
        #expect(first.assets.isEmpty)
        let second = cursor.nextCluster(assetBudget: 2)
        #expect(second.assets.map(\.id) == ["0", "1", "2"])
        #expect(second.inspectedCount == 2)
        let last = cursor.nextCluster(assetBudget: 2)
        #expect(last.assets.map(\.id) == ["20", "21"])
        #expect(cursor.isExhausted)
    }

    @Test func denseBurstHasBoundedClustersAndNoMissingPhotos() {
        var cursor = SimilarityScanCursor(fetchResult: FixtureFetchResult((0..<200).map(String.init)))
        var ids: [String] = []
        while !cursor.isExhausted {
            let chunk = cursor.nextCluster(assetBudget: 240)
            #expect(chunk.assets.count <= 80)
            ids.append(contentsOf: chunk.assets.map(\.id))
        }
        #expect(ids == (0..<200).map(String.init))
    }

    @Test func simultaneousRequestsDoNotStartTwoScans() async {
        var calls = 0
        var gate: CheckedContinuation<Void, Never>?
        let queue = SimilarPhotoQueue { _, _ in
            calls += 1
            await withCheckedContinuation { gate = $0 }
            return SimilarScanPage(groups: [], hasMore: false)
        }
        let first = Task { await queue.loadIfNeeded() }
        let started = await waitUntil { gate != nil }
        #expect(started)
        await queue.loadIfNeeded()
        #expect(calls == 1)
        gate?.resume()
        await first.value
    }

    @Test func cancelledPageDoesNotChangeQueueOrMarkItExhausted() async {
        let result = group(1)
        let queue = SimilarPhotoQueue { _, _ in
            while !Task.isCancelled { await Task.yield() }
            return SimilarScanPage(groups: [result], hasMore: false)
        }
        let scan = Task { await queue.loadIfNeeded() }
        let started = await waitUntil { queue.isLoading }
        #expect(started)
        scan.cancel()
        await scan.value
        #expect(queue.groups.isEmpty)
        #expect(!queue.isExhausted)
        #expect(!queue.isLoading)
    }

    @Test func leavingPageCancelsActiveWorkAndDoesNotStartMore() async {
        var calls = 0
        let queue = SimilarPhotoQueue { _, _ in
            calls += 1
            while !Task.isCancelled { await Task.yield() }
            return SimilarScanPage(groups: [], hasMore: true)
        }
        queue.setActive(true)
        let started = await waitUntil { queue.isLoading }
        #expect(started)
        queue.setActive(false)
        let stopped = await waitUntil { !queue.isLoading }
        #expect(stopped)
        queue.requestRefill(force: true)
        #expect(calls == 1)
    }

    @Test func photoDeletedDuringRefillDoesNotReappear() async {
        let removed = group(1)
        let kept = group(2)
        var gate: CheckedContinuation<Void, Never>?
        let queue = SimilarPhotoQueue { _, _ in
            await withCheckedContinuation { gate = $0 }
            return SimilarScanPage(groups: [removed, kept], hasMore: false)
        }
        let load = Task { await queue.loadIfNeeded() }
        let started = await waitUntil { gate != nil }
        #expect(started)
        queue.recordDeletedAssets(Set(removed.assets.map(\.id)))
        gate?.resume()
        await load.value
        #expect(queue.groups.count == 1)
        #expect(Set(queue.groups[0].assets.map(\.id)) == Set(kept.assets.map(\.id)))
    }

    @Test func newQueueShowsSearchUntilFirstRequestCompletes() {
        let queue = SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        #expect(queue.shouldShowSearchPlaceholder)
        #expect(!queue.hasCompletedSearch)
    }

    @Test func firstGroupIsPublishedBeforeWaitingForTheRestOfTheQueue() async {
        let first = group(1)
        var calls = 0
        var gate: CheckedContinuation<Void, Never>?
        let queue = SimilarPhotoQueue { limit, _ in
            calls += 1
            if calls == 1 {
                #expect(limit == 1)
                return SimilarScanPage(groups: [first], hasMore: true)
            }
            await withCheckedContinuation { gate = $0 }
            return SimilarScanPage(groups: [], hasMore: false)
        }
        let load = Task { await queue.loadIfNeeded() }
        let published = await waitUntil { gate != nil }
        #expect(published)
        #expect(queue.groups.count == 1)
        #expect(queue.isLoading)
        gate?.resume()
        await load.value
    }

    @Test func skippingNeverCyclesBackToAlreadySkippedGroups() async {
        let initial = (0..<10).map(group)
        let queue = SimilarPhotoQueue { limit, _ in
            SimilarScanPage(groups: Array(initial.prefix(limit)), hasMore: false)
        }
        // All groups are preloaded to isolate navigation from scanning.
        queue.groups = initial
        var visited: Set<Set<String>> = []
        while let current = queue.groups.first {
            let ids = Set(current.assets.map(\.id))
            #expect(visited.insert(ids).inserted)
            queue.skipCurrentGroup()
        }
        #expect(visited.count == initial.count)
    }

    @Test func deletingPhotoPreservesOtherGroupIdentityAndSelection() async {
        let first = group(1)
        var second = group(2)
        second.selectedForDelete = [second.assets[0].id]
        let queue = SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        queue.groups = [first, second]
        queue.recordDeletedAssets([first.assets[0].id])
        #expect(queue.groups.count == 1)
        #expect(queue.groups[0].id == second.id)
        #expect(queue.groups[0].selectedForDelete == second.selectedForDelete)
    }

    @Test func staleSelectionActionCannotChangeTheNextGroup() {
        let first = group(1)
        let second = group(2)
        let queue = SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        queue.groups = [first, second]
        queue.skipCurrentGroup()
        queue.toggleSelection(first.assets[0].id, in: first.id)
        #expect(queue.groups[0].selectedForDelete.isEmpty)
    }

    @Test func completedEmptySearchIsDifferentFromNotHavingStarted() async {
        let queue = SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        #expect(queue.shouldShowSearchPlaceholder)
        await queue.loadIfNeeded()
        #expect(queue.hasCompletedSearch)
        #expect(queue.isExhausted)
        #expect(!queue.shouldShowSearchPlaceholder)
    }

    @Test func returningToSimilarModeReusesCursorQueueAndSkippedHistory() {
        let defaults = UserDefaults(suiteName: "SimilaritySessionTests.\(UUID().uuidString)")!
        let model = LibraryViewModel(service: ControlledPhotoService(), batchManager: BatchManager(sessionStore: ReviewSessionStore(defaults: defaults)))
        var creations = 0
        let first = model.similarPhotoSession {
            creations += 1
            return SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        }
        let initial = [group(1), group(2)]
        first.groups = initial
        first.skipCurrentGroup()
        model.exitSimilarMode()
        model.enterSimilarMode()
        let resumed = model.similarPhotoSession {
            creations += 1
            return SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        }
        #expect(creations == 1)
        #expect(first === resumed)
        #expect(resumed.groups.first?.id == initial[1].id)
    }

    @Test func skippingLastVisibleGroupDuringRefillDoesNotLoseDemand() async {
        let first = group(1)
        let later = group(2)
        var calls = 0
        var gate: CheckedContinuation<Void, Never>?
        let queue = SimilarPhotoQueue(limits: SimilarSearchLimits(maximumPages: 4)) { _, _ in
            calls += 1
            if calls == 1 { return SimilarScanPage(groups: [first], hasMore: true) }
            if calls == 2 { await withCheckedContinuation { gate = $0 } }
            if calls <= 4 { return SimilarScanPage(groups: [], hasMore: true) }
            return SimilarScanPage(groups: [later], hasMore: false)
        }
        queue.setActive(true)
        let waiting = await waitUntil { gate != nil }
        #expect(waiting)
        queue.skipCurrentGroup()
        gate?.resume()
        let refilled = await waitUntil { !queue.groups.isEmpty && !queue.isLoading }
        #expect(refilled)
        #expect(calls == 5)
        #expect(queue.groups.first?.id == later.id)
        queue.setActive(false)
    }

    @Test func similarModeCannotCaptureAnUnloadedPhotoLibrary() async {
        let defaults = UserDefaults(suiteName: "SimilaritySessionTests.\(UUID().uuidString)")!
        let model = LibraryViewModel(service: ControlledPhotoService(), batchManager: BatchManager(sessionStore: ReviewSessionStore(defaults: defaults)))
        model.enterSimilarMode()
        #expect(!model.isShowingSimilar)
        await model.loadAssets()
        model.enterSimilarMode()
        #expect(model.isShowingSimilar)
    }

    @Test func normalBatchDeletionAlsoRemovesPhotosFromCachedSimilarQueue() async {
        let defaults = UserDefaults(suiteName: "SimilaritySessionTests.\(UUID().uuidString)")!
        let service = ControlledPhotoService()
        let model = LibraryViewModel(service: service, batchManager: BatchManager(sessionStore: ReviewSessionStore(defaults: defaults)))
        await model.loadAssets()
        let cached = model.similarPhotoSession {
            SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        }
        cached.groups = [group(0)]
        model.batchManager.markAsDelete(model.batchManager.currentBatch[0])
        model.confirmDeletion()
        let started = await waitUntil { service.pending != nil }
        #expect(started)
        service.finish(.success(()))
        let finished = await waitUntil { !model.isDeleting }
        #expect(finished)
        #expect(cached.groups.isEmpty)
    }

    @Test func longSequenceRetainsSegmentationHintAcrossBoundedChunks() {
        let ids = (0..<161).map(String.init)
        var cursor = SimilarityScanCursor(fetchResult: FixtureFetchResult(ids))
        let first = cursor.nextCluster(assetBudget: 240)
        let second = cursor.nextCluster(assetBudget: 240)
        let last = cursor.nextCluster(assetBudget: 240)
        #expect(first.assets.count == 80)
        #expect(second.assets.count == 80)
        #expect(first.isLargeCluster)
        #expect(second.isLargeCluster)
        #expect(last.isLargeCluster)
    }

    @Test func exactly80PhotosAreNotMistakenForAnOversizedSequence() {
        var cursor = SimilarityScanCursor(fetchResult: FixtureFetchResult((0..<80).map(String.init)))
        let chunk = cursor.nextCluster(assetBudget: 240)
        #expect(chunk.assets.count == 80)
        #expect(!chunk.isLargeCluster)
    }

    @Test func largeSequenceRestoresOriginalTighterTimeSegmentation() {
        let ids = ["0", "1"] + (2..<80).map { String(($0 - 1) * 3 + 1) }
        let photos = ids.map { PhotoAsset(asset: FixtureAsset($0)) }
        let segments = SimilarityClusterSegmentation.segments(photos, isLargeCluster: true)
        #expect(segments.count == 1)
        #expect(segments.first?.map(\.id) == ["0", "1"])
    }

    @Test func cheapSearchDoesNotPauseBeforeResultBeyondOld960PhotoLimit() async {
        let found = group(99)
        var calls = 0
        let queue = SimilarPhotoQueue { _, _ in
            calls += 1
            if calls < 8 { return SimilarScanPage(groups: [], hasMore: true) }
            return SimilarScanPage(groups: [found], hasMore: false)
        }
        await queue.loadIfNeeded()
        #expect(calls == 8)
        #expect(queue.groups.first?.id == found.id)
    }

    @Test func expensiveFeatureWorkStopsButBufferedResultsCanStillBeShown() async {
        var requests: [SimilarityPageRequest] = []
        let first = group(1)
        let buffered = group(2)
        let queue = SimilarPhotoQueue(scanPage: { request in
            requests.append(request)
            if requests.count == 1 {
                return SimilarScanPage(groups: [first], hasMore: true, inspectedAssetCount: 80, featureRequestCount: 80, hasBufferedGroups: true)
            }
            return SimilarScanPage(groups: [buffered], hasMore: true, inspectedAssetCount: 0)
        })
        await queue.loadIfNeeded()
        #expect(requests.count == 2)
        #expect(requests[1].photoBudget == 0)
        #expect(requests[1].featureBudget == 0)
        #expect(queue.groups.count == 2)
    }

    @Test func elapsedTimePausesFurtherWork() async {
        var time = ContinuousClock.now
        var calls = 0
        let queue = SimilarPhotoQueue(now: { time }) { _, _ in
            calls += 1
            time += .seconds(3)
            return SimilarScanPage(groups: [], hasMore: true, inspectedAssetCount: 240)
        }
        await queue.loadIfNeeded()
        #expect(calls == 1)
        #expect(!queue.isExhausted)
    }

    @Test func galleryCanAppendOnDemandWithoutRemovingEarlierGroups() async {
        var offset = 0
        let queue = SimilarPhotoQueue { limit, _ in
            let result = (offset..<(offset + limit)).map { group(1000 - $0) }
            offset += limit
            return SimilarScanPage(groups: result, hasMore: true)
        }
        queue.setOverviewMode(true)
        queue.setActive(true)
        let initialReady = await waitUntil { queue.groups.count == 10 && !queue.isLoading }
        #expect(initialReady)
        let originalIDs = queue.groups.map(\.id)
        queue.requestMoreForBrowsing(near: queue.groups.last!.id)
        let moreReady = await waitUntil { queue.groups.count == 20 && !queue.isLoading }
        #expect(moreReady)
        #expect(Array(queue.groups.prefix(10)).map(\.id) == originalIDs)
        queue.setActive(false)
    }

    @Test func removingSpecificGalleryGroupDoesNotRemoveFirstGroup() {
        let queue = SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        let first = group(1)
        let second = group(2)
        queue.groups = [first, second]
        queue.removeGroup(second.id)
        #expect(queue.groups.map(\.id) == [first.id])
    }
}
