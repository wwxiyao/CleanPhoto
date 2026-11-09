import Combine
import Foundation
import Photos
import Testing
@testable import CleanPhotoLogic

// The Photos boundary is faked; all session behavior uses the production classes.
final class FixtureAsset: PHAsset, @unchecked Sendable {
    private let identifier: String
    private let favoriteFlag: Bool
    init(_ identifier: String, favorite: Bool = false) {
        self.identifier = identifier
        self.favoriteFlag = favorite
        super.init()
    }
    override var localIdentifier: String { identifier }
    override var creationDate: Date? { Date(timeIntervalSince1970: Double(identifier) ?? 0) }
    override var pixelWidth: Int { 100 }
    override var pixelHeight: Int { 100 }
    override var isFavorite: Bool { favoriteFlag }
    override var hash: Int { identifier.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        (object as? FixtureAsset)?.identifier == identifier
    }
}

final class FixtureFetchResult: PHFetchResult<PHAsset>, @unchecked Sendable {
    private let items: [PHAsset]
    init(_ ids: [String]) { items = ids.map { FixtureAsset($0) }; super.init() }
    override var count: Int { items.count }
    override func object(at index: Int) -> PHAsset { items[index] }
}

@MainActor
final class ControlledPhotoService: PhotoLibraryProviding {
    var ids = (0..<15).map(String.init)
    var deletedIDs: [[String]] = []
    var pending: CheckedContinuation<Void, Error>?
    func authorizationStatus() -> PHAuthorizationStatus { .authorized }
    func requestAuthorization() async -> PHAuthorizationStatus { .authorized }
    func loadAssets() async -> PHFetchResult<PHAsset> { FixtureFetchResult(ids) }
    func deleteAssets(_ assets: [PHAsset]) async throws {
        let submitted = assets.map(\.localIdentifier)
        deletedIDs.append(submitted)
        try await withCheckedThrowingContinuation { pending = $0 }
        ids.removeAll { submitted.contains($0) }
    }
    func setFavorite(_ favorite: Bool, for asset: PHAsset) async throws {}
    func finish(_ result: Result<Void, Error>) {
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }
}

@Suite(.serialized) @MainActor
struct SessionTests {
    private func makeStore() -> ReviewSessionStore {
        ReviewSessionStore(defaults: UserDefaults(suiteName: "CleanPhotoTests.\(UUID().uuidString)")!)
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        return condition()
    }

    @Test func reloadRetainsDecisionsAndBatchOrder() {
        let manager = BatchManager(sessionStore: makeStore())
        let photos = FixtureFetchResult((0..<15).map(String.init))
        manager.setAssets(photos)
        let originalIDs = manager.currentBatch.map(\.id)
        let deleted = manager.currentBatch[0]
        manager.markAsDelete(deleted)
        manager.markAsKeep(manager.currentBatch[1])
        manager.setAssets(photos)
        #expect(manager.currentBatch.map(\.id) == originalIDs)
        #expect(manager.processedAssetIds.count == 2)
        #expect(manager.pendingDeleteAssets.map(\.id) == [deleted.id])
    }

    @Test func keepingBatchDoesNotCarryDeletesToNextBatch() {
        let manager = BatchManager(sessionStore: makeStore())
        manager.setAssets(FixtureFetchResult((0..<15).map(String.init)))
        let firstBatch = manager.currentBatch
        for asset in firstBatch { manager.markAsDelete(asset) }
        manager.nextBatch()
        #expect(manager.pendingDeleteAssets.isEmpty)
        #expect(Set(manager.currentBatch.map(\.id)).isDisjoint(with: firstBatch.map(\.id)))
    }

    @Test func deleteLockPreventsNavigationAndRecovery() async {
        let service = ControlledPhotoService()
        let model = LibraryViewModel(service: service, batchManager: BatchManager(sessionStore: makeStore()))
        model.batchManager.setAssets(FixtureFetchResult((0..<15).map(String.init)))
        let firstBatch = model.batchManager.currentBatch.map(\.id)
        let photo = model.batchManager.currentBatch[0]
        model.batchManager.markAsDelete(photo)
        model.isReviewingBatch = true
        model.confirmDeletion()
        model.recoverAsset(photo)
        model.skipBatch()
        model.startNextBatch()
        model.enterSimilarMode()
        model.restartReview()
        model.confirmDeletion()
        #expect(model.batchManager.pendingDeleteAssets.contains(photo))
        #expect(model.batchManager.currentBatch.map(\.id) == firstBatch)
        #expect(model.isReviewingBatch)
        #expect(!model.isShowingSimilar)
        let started = await waitUntil { service.pending != nil }
        #expect(started)
        #expect(service.deletedIDs.count == 1)
        service.finish(.failure(NSError(domain: "Test", code: 1)))
        let finished = await waitUntil { !model.isDeleting }
        #expect(finished)
    }

    @Test func newManagerRestoresPositionAndSelections() {
        let suite = "CleanPhotoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = BatchManager(sessionStore: ReviewSessionStore(defaults: defaults))
        let photos = FixtureFetchResult((0..<15).map(String.init))
        first.setAssets(photos)
        let ids = first.currentBatch.map(\.id)
        first.markAsDelete(first.currentBatch[0])
        first.markAsKeep(first.currentBatch[1])

        let restored = BatchManager(sessionStore: ReviewSessionStore(defaults: UserDefaults(suiteName: suite)!))
        restored.setAssets(photos)
        #expect(restored.currentBatch.map(\.id) == ids)
        #expect(restored.currentIndex == 2)
        #expect(Set(restored.pendingDeleteAssets.map(\.id)) == [ids[0]])
        #expect(restored.processedAssetIds.contains(ids[1]))
    }

    @Test func reviewPageAndRecoveredSelectionSurviveRestart() {
        let store = makeStore()
        let first = BatchManager(sessionStore: store)
        let photos = FixtureFetchResult((0..<12).map(String.init))
        first.setAssets(photos)
        for asset in first.currentBatch { first.markAsDelete(asset) }
        first.isReviewingBatch = true
        first.recoverAsset(first.currentBatch[0])
        let restored = BatchManager(sessionStore: store)
        restored.setAssets(photos)
        #expect(restored.isReviewingBatch)
        #expect(restored.currentIndex == 10)
        #expect(restored.pendingDeleteAssets.count == 9)
        #expect(!restored.pendingDeleteAssets.contains(restored.currentBatch[0]))
    }

    @Test func removedPhotoDoesNotShiftResumePastAnUnseenPhoto() {
        let store = makeStore()
        let first = BatchManager(sessionStore: store)
        first.setAssets(FixtureFetchResult(["0", "1", "2", "3"]))
        first.markAsKeep(first.currentBatch[0])
        first.markAsDelete(first.currentBatch[1])
        let restored = BatchManager(sessionStore: store)
        restored.setAssets(FixtureFetchResult(["1", "2", "3"]))
        #expect(restored.currentIndex == 1)
        #expect(restored.currentBatch[restored.currentIndex].id == "2")
        #expect(restored.processedAssetIds == ["1"])
    }

    @Test func keepingWholeBatchPersistsWithoutOldDeletes() {
        let store = makeStore()
        let first = BatchManager(sessionStore: store)
        let photos = FixtureFetchResult((0..<15).map(String.init))
        first.setAssets(photos)
        for asset in first.currentBatch { first.markAsDelete(asset) }
        first.nextBatch()
        let restored = BatchManager(sessionStore: store)
        restored.setAssets(photos)
        #expect(restored.currentBatch.count == 5)
        #expect(restored.currentIndex == 0)
        #expect(restored.pendingDeleteAssets.isEmpty)
        #expect(restored.processedAssetIds.count == 10)
    }

    @Test func completedSessionStaysCompletedUntilExplicitRestart() {
        let store = makeStore()
        let first = BatchManager(sessionStore: store)
        let photos = FixtureFetchResult(["0", "1"])
        first.setAssets(photos)
        for asset in first.currentBatch { first.markAsKeep(asset) }
        first.nextBatch()
        let restored = BatchManager(sessionStore: store)
        restored.setAssets(photos)
        #expect(restored.currentBatch.isEmpty)
        #expect(!restored.hasMorePhotos)
        restored.restart()
        #expect(restored.currentBatch.count == 2)
        #expect(restored.processedAssetIds.isEmpty)
        #expect(restored.currentIndex == 0)
    }

    @Test func corruptSnapshotFallsBackToFreshBatch() {
        let suite = "CleanPhotoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("broken".utf8), forKey: "CleanPhoto.reviewSession.v1")
        let manager = BatchManager(sessionStore: ReviewSessionStore(defaults: defaults))
        manager.setAssets(FixtureFetchResult(["0", "1"]))
        #expect(manager.currentBatch.count == 2)
        #expect(manager.currentIndex == 0)
    }

    @Test func failedDeletionKeepsSelectionForRetryAndRestart() async {
        let store = makeStore()
        let service = ControlledPhotoService()
        let manager = BatchManager(sessionStore: store)
        let model = LibraryViewModel(service: service, batchManager: manager)
        await model.loadAssets()
        let asset = manager.currentBatch[0]
        manager.markAsDelete(asset)
        model.isReviewingBatch = true
        model.confirmDeletion()
        let started = await waitUntil { service.pending != nil }
        #expect(started)
        service.finish(.failure(NSError(domain: "Test", code: 2)))
        let finished = await waitUntil { !model.isDeleting }
        #expect(finished)
        #expect(model.activeAlert != nil)
        #expect(manager.pendingDeleteAssets.contains(asset))
        #expect(model.isReviewingBatch)
        let restored = BatchManager(sessionStore: store)
        restored.setAssets(await service.loadAssets())
        #expect(restored.pendingDeleteAssets.map(\.id) == [asset.id])
        #expect(restored.isReviewingBatch)
    }

    @Test func successfulDeletionAdvancesAndDoesNotReappearAfterRestart() async {
        let store = makeStore()
        let service = ControlledPhotoService()
        let manager = BatchManager(sessionStore: store)
        let model = LibraryViewModel(service: service, batchManager: manager)
        await model.loadAssets()
        let batch = manager.currentBatch
        manager.markAsDelete(batch[0])
        for asset in batch.dropFirst() { manager.markAsKeep(asset) }
        model.isReviewingBatch = true
        model.confirmDeletion()
        model.confirmDeletion()
        let started = await waitUntil { service.pending != nil }
        #expect(started)
        #expect(service.deletedIDs == [[batch[0].id]])
        service.finish(.success(()))
        let finished = await waitUntil { !model.isDeleting }
        #expect(finished)
        #expect(!model.isReviewingBatch)
        #expect(manager.pendingDeleteAssets.isEmpty)
        #expect(manager.currentBatch.count == 5)
        let restored = BatchManager(sessionStore: store)
        restored.setAssets(await service.loadAssets())
        #expect(restored.currentBatch.map(\.id) == manager.currentBatch.map(\.id))
        #expect(restored.pendingDeleteAssets.isEmpty)
        #expect(restored.currentIndex == 0)
    }

    @Test func batchChangesNotifyRootViewModel() {
        let manager = BatchManager(sessionStore: makeStore())
        manager.setAssets(FixtureFetchResult(["0", "1"]))
        let model = LibraryViewModel(service: ControlledPhotoService(), batchManager: manager)
        var notifications = 0
        let token = model.objectWillChange.sink { notifications += 1 }
        manager.markAsDelete(manager.currentBatch[0])
        #expect(notifications > 0)
        notifications = 0
        manager.recoverAsset(manager.currentBatch[0])
        #expect(notifications > 0)
        withExtendedLifetime(token) {}
    }
}
