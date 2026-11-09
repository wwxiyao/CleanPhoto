import Foundation
import Testing
@testable import CleanPhotoLogic

private actor ScanProbe {
    var calls = 0
    var blockFirst = false
    var entered = false
    var release: CheckedContinuation<Void, Never>?
    var cacheWrites = 0
    var holdCache = false
    var releaseCache: CheckedContinuation<Void, Never>?

    func configure(blockFirst: Bool = false, holdCache: Bool = false) {
        self.blockFirst = blockFirst
        self.holdCache = holdCache
    }

    func verify(_ assets: [PhotoAsset]) async -> (groups: [SimilarGroup], cacheDirty: Bool) {
        calls += 1
        entered = true
        if blockFirst, calls == 1 {
            await withCheckedContinuation { release = $0 }
        }
        return (stride(from: 0, to: assets.count - 1, by: 2).map {
            SimilarGroup(assets: [assets[$0], assets[$0 + 1]])
        }, true)
    }

    func unblock() { release?.resume(); release = nil }
    func writeCache() async {
        cacheWrites += 1
        if holdCache { await withCheckedContinuation { releaseCache = $0 } }
    }
    func unblockCache() { releaseCache?.resume(); releaseCache = nil }
}

@MainActor
struct SimilarityServiceTests {
    private func service(_ ids: [String], probe: ScanProbe) -> SimilarityService {
        SimilarityService(
            fetchResult: FixtureFetchResult(ids),
            verifier: { await probe.verify($0) },
            loadCache: { [:] },
            saveCache: { _ in await probe.writeCache() }
        )
    }

    @Test func firstPageDoesNotScanLaterClustersOrWaitForCacheWrite() async {
        let probe = ScanProbe()
        await probe.configure(holdCache: true)
        let scanner = service(["0", "1", "20", "21", "40", "41"], probe: probe)
        let first = await scanner.nextPage(groupLimit: 1, assetBudget: 240)
        #expect(first.groups.count == 1)
        #expect(first.hasMore)
        #expect(await probe.calls == 1)
        #expect(await probe.cacheWrites == 0)
        // Allow any eventual debounced cache write to finish without touching disk.
        await probe.configure(holdCache: false)
    }

    @Test func overflowResultsAreBufferedWithoutReprocessingCluster() async {
        let probe = ScanProbe()
        let scanner = service((0..<20).map(String.init), probe: probe)
        var seen: Set<String> = []
        for _ in 0..<10 {
            let page = await scanner.nextPage(groupLimit: 1, assetBudget: 240)
            #expect(page.groups.count == 1)
            let ids = Set(page.groups[0].assets.map(\.id))
            #expect(seen.isDisjoint(with: ids))
            seen.formUnion(ids)
        }
        #expect(seen.count == 20)
        #expect(await probe.calls == 1)
        let done = await scanner.nextPage(groupLimit: 1, assetBudget: 240)
        #expect(!done.hasMore)
    }

    @Test func cancelledPageRestoresCursorAndDoesNotLoseResults() async {
        let probe = ScanProbe()
        await probe.configure(blockFirst: true)
        let scanner = service(["0", "1", "20", "21"], probe: probe)
        let task = Task { await scanner.nextPage(groupLimit: 1, assetBudget: 240) }
        while !(await probe.entered) { await Task.yield() }
        task.cancel()
        await probe.unblock()
        let cancelled = await task.value
        #expect(cancelled.groups.isEmpty)
        let retry = await scanner.nextPage(groupLimit: 1, assetBudget: 240)
        #expect(retry.groups.first?.assets.map(\.id) == ["0", "1"])
        let next = await scanner.nextPage(groupLimit: 1, assetBudget: 240)
        #expect(next.groups.first?.assets.map(\.id) == ["20", "21"])
    }

    @Test func photoWindowEndsWithoutClaimingWholeLibraryIsExhausted() async {
        let probe = ScanProbe()
        let scanner = service(["0", "20", "40", "60", "80", "100"], probe: probe)
        let first = await scanner.nextPage(groupLimit: 1, assetBudget: 2)
        #expect(first.groups.isEmpty)
        #expect(first.hasMore)
        #expect(await probe.calls == 0)
    }
}
