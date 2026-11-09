import Foundation
import Photos
import Testing
@testable import CleanPhotoLogic

@MainActor
struct PhotoSortOrderTests {
    @Test func newestIsDefaultAndSwitchKeepsGroupIdentityAndSelection() {
        let queue = SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        var old = SimilarGroup(assets: [PhotoAsset(asset: FixtureAsset("0")), PhotoAsset(asset: FixtureAsset("1"))])
        old.selectedForDelete = ["0"]
        let new = SimilarGroup(assets: [PhotoAsset(asset: FixtureAsset("30")), PhotoAsset(asset: FixtureAsset("31"))])
        queue.groups = [old, new]
        #expect(queue.sortOrder == .newestFirst)
        queue.setSortOrder(.newestFirst)
        #expect(queue.groups.map(\.id) == [new.id, old.id])
        queue.setSortOrder(.oldestFirst)
        #expect(queue.groups.map(\.id) == [old.id, new.id])
        #expect(queue.selectedAssets.map(\.id) == ["0"])
    }

    @Test func cursorCanStartAtOppositeEndWithoutLosingClusterBoundary() {
        var cursor = SimilarityScanCursor(fetchResult: FixtureFetchResult(["0", "1", "30", "31"]), reversed: true)
        let first = cursor.nextCluster(assetBudget: 240)
        #expect(first.assets.map(\.id) == ["31", "30"])
        let second = cursor.nextCluster(assetBudget: 240)
        #expect(second.assets.map(\.id) == ["1", "0"])
        #expect(cursor.isExhausted)
    }

    @Test func serviceRestartsScanningAtOtherEndAfterSortChange() async {
        // Production fetches newest first. Keep this fixture in the same order.
        let service = SimilarityService(fetchResult: FixtureFetchResult(["31", "30", "1", "0"]), verifier: { assets in
            ([SimilarGroup(assets: assets)], false)
        }, loadCache: { [:] }, saveCache: { _ in })
        let newest = await service.nextPage(groupLimit: 1, assetBudget: 240, sortOrder: .newestFirst)
        #expect(newest.groups.first?.assets.map(\.id) == ["31", "30"])
        let oldest = await service.nextPage(groupLimit: 1, assetBudget: 240, sortOrder: .oldestFirst)
        #expect(oldest.groups.first?.assets.map(\.id) == ["0", "1"])
    }
    @Test func sortChangeDiscardsPageAlreadyInFlight() async {
        var gate: CheckedContinuation<Void, Never>?
        var orders: [PhotoSortOrder] = []
        let queue = SimilarPhotoQueue(scanPage: { request in
            orders.append(request.sortOrder)
            if orders.count == 1 {
                await withCheckedContinuation { gate = $0 }
                return SimilarScanPage(groups: [SimilarGroup(assets: [PhotoAsset(asset: FixtureAsset("30")), PhotoAsset(asset: FixtureAsset("31"))])], hasMore: false)
            }
            return SimilarScanPage(groups: [SimilarGroup(assets: [PhotoAsset(asset: FixtureAsset("0")), PhotoAsset(asset: FixtureAsset("1"))])], hasMore: false)
        })
        queue.setActive(true)
        let deadline = ContinuousClock.now + .seconds(2)
        while gate == nil, ContinuousClock.now < deadline { await Task.yield() }
        #expect(gate != nil)
        queue.setSortOrder(.oldestFirst)
        gate?.resume()
        while queue.groups.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
        #expect(orders == [.newestFirst, .oldestFirst])
        #expect(queue.groups.first?.assets.map(\.id) == ["0", "1"])
        queue.setActive(false)
    }

}
