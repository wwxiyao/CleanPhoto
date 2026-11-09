import Foundation
import Photos
import Testing
@testable import CleanPhotoLogic

@MainActor
private final class FavoritePhotoService: PhotoLibraryProviding {
    var writes: [(id: String, value: Bool)] = []
    var shouldFail = false
    var holdWrite = false
    var pending: CheckedContinuation<Void, Error>?
    func authorizationStatus() -> PHAuthorizationStatus { .authorized }
    func requestAuthorization() async -> PHAuthorizationStatus { .authorized }
    func loadAssets() async -> PHFetchResult<PHAsset> { FixtureFetchResult(["0", "1"]) }
    func deleteAssets(_ assets: [PHAsset]) async throws {}
    func setFavorite(_ favorite: Bool, for asset: PHAsset) async throws {
        writes.append((asset.localIdentifier, favorite))
        if holdWrite { try await withCheckedThrowingContinuation { pending = $0 } }
        if shouldFail { throw NSError(domain: "FavoriteTest", code: 1) }
    }
}

@MainActor
struct FavoriteTests {
    private func model(_ service: FavoritePhotoService) -> LibraryViewModel {
        let defaults = UserDefaults(suiteName: "CleanPhotoFavoritesTests.\(UUID().uuidString)")!
        return LibraryViewModel(service: service, batchManager: BatchManager(sessionStore: ReviewSessionStore(defaults: defaults)))
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        return condition()
    }

    @Test func favoriteTogglesSystemValueWithoutAdvancingPhoto() async {
        let service = FavoritePhotoService()
        let model = model(service)
        await model.loadAssets()
        let photo = model.batchManager.currentBatch[0]
        model.toggleFavorite(photo)
        let firstFinished = await waitUntil { !model.isUpdatingFavorite(photo) }
        #expect(firstFinished)
        #expect(model.isFavorite(photo))
        #expect(model.batchManager.currentIndex == 0)
        #expect(model.batchManager.pendingDeleteAssets.isEmpty)
        model.toggleFavorite(photo)
        let secondFinished = await waitUntil { !model.isUpdatingFavorite(photo) }
        #expect(secondFinished)
        #expect(!model.isFavorite(photo))
        #expect(service.writes.map(\.value) == [true, false])
    }

    @Test func repeatedTapWhileSavingDoesNotSubmitTwice() async {
        let service = FavoritePhotoService()
        service.holdWrite = true
        let model = model(service)
        await model.loadAssets()
        let photo = model.batchManager.currentBatch[0]
        model.toggleFavorite(photo)
        model.toggleFavorite(photo)
        let started = await waitUntil { service.pending != nil }
        #expect(started)
        #expect(service.writes.count == 1)
        #expect(!model.isFavorite(photo))
        service.pending?.resume()
        let finished = await waitUntil { !model.isUpdatingFavorite(photo) }
        #expect(finished)
        #expect(model.isFavorite(photo))
    }

    @Test func failedFavoriteKeepsPreviousValueAndShowsError() async {
        let service = FavoritePhotoService()
        service.shouldFail = true
        let model = model(service)
        await model.loadAssets()
        let photo = model.batchManager.currentBatch[0]
        model.toggleFavorite(photo)
        let finished = await waitUntil { !model.isUpdatingFavorite(photo) }
        #expect(finished)
        #expect(!model.isFavorite(photo))
        #expect(model.activeAlert?.title == "收藏更新失败")
        #expect(model.batchManager.currentIndex == 0)
    }

    @Test func favoriteCompletionAfterSwipeUpdatesOriginalPhoto() async {
        let service = FavoritePhotoService()
        service.holdWrite = true
        let model = model(service)
        await model.loadAssets()
        let first = model.batchManager.currentBatch[0]
        let next = model.batchManager.currentBatch[1]
        model.toggleFavorite(first)
        model.batchManager.markAsKeep(first)
        let started = await waitUntil { service.pending != nil }
        #expect(started)
        service.pending?.resume()
        let finished = await waitUntil { !model.isUpdatingFavorite(first) }
        #expect(finished)
        #expect(model.isFavorite(first))
        #expect(!model.isFavorite(next))
        #expect(model.batchManager.currentIndex == 1)
    }

    @Test func existingSystemFavoriteStartsFilledAndCanBeRemoved() async {
        let service = FavoritePhotoService()
        let model = model(service)
        let photo = PhotoAsset(asset: FixtureAsset("existing", favorite: true))
        #expect(model.isFavorite(photo))
        model.toggleFavorite(photo)
        let finished = await waitUntil { !model.isUpdatingFavorite(photo) }
        #expect(finished)
        #expect(service.writes.map(\.value) == [false])
        #expect(!model.isFavorite(photo))
    }

    @Test func deletionInProgressPreventsFavoriteWrite() async {
        let service = FavoritePhotoService()
        let model = model(service)
        await model.loadAssets()
        let photo = model.batchManager.currentBatch[0]
        model.batchManager.markAsDelete(photo)
        model.confirmDeletion()
        model.toggleFavorite(photo)
        #expect(service.writes.isEmpty)
        let finished = await waitUntil { !model.isDeleting }
        #expect(finished)
    }

    @Test func buttonReflectsTapImmediatelyWhileSystemSaveIsPending() async {
        let service = FavoritePhotoService()
        service.holdWrite = true
        let model = model(service)
        await model.loadAssets()
        let photo = model.batchManager.currentBatch[0]
        #expect(!model.currentFavoriteState.isFavorite)
        model.toggleFavorite(photo)
        #expect(model.currentFavoriteState.isFavorite)
        #expect(model.currentFavoriteState.isSaving)
        let started = await waitUntil { service.pending != nil }
        #expect(started)
        service.pending?.resume()
        let finished = await waitUntil { !model.currentFavoriteState.isSaving }
        #expect(finished)
        #expect(model.currentFavoriteState.isFavorite)
    }

    @Test func buttonRollsBackIfSaveFails() async {
        let service = FavoritePhotoService()
        service.holdWrite = true
        service.shouldFail = true
        let model = model(service)
        await model.loadAssets()
        model.toggleFavorite(model.batchManager.currentBatch[0])
        #expect(model.currentFavoriteState.isFavorite)
        let started = await waitUntil { service.pending != nil }
        #expect(started)
        service.pending?.resume()
        let finished = await waitUntil { !model.currentFavoriteState.isSaving }
        #expect(finished)
        #expect(!model.currentFavoriteState.isFavorite)
        #expect(model.activeAlert != nil)
    }
}
