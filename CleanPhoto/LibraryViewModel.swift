import SwiftUI
import Combine
import Photos
import OSLog

struct AppAlertState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct FavoriteButtonState: Equatable {
    let isFavorite: Bool
    let isSaving: Bool
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var accessState: LibraryAccessState
    @Published private(set) var assets: PHFetchResult<PHAsset>? = nil
    @Published private(set) var isLoading = false

    var isReviewingBatch: Bool {
        get { batchManager.isReviewingBatch }
        set {
            guard !isDeleting else { return }
            batchManager.isReviewingBatch = newValue
        }
    }
    @Published private(set) var isDeleting = false
    @Published var isShowingSimilar = false
    @Published var activeAlert: AppAlertState?
    @Published private var favoriteOverrides: [String: Bool] = [:]
    @Published private var favoriteUpdates: [String: Bool] = [:]

    private let service: any PhotoLibraryProviding
    let batchManager: BatchManager
    private var batchObservation: AnyCancellable?
    private let favoriteLog = Logger(subsystem: "wxynjx.CleanPhoto", category: "Favorites")
    private var similarSession: SimilarPhotoQueue?

    init(service: any PhotoLibraryProviding, batchManager: BatchManager? = nil) {
        self.service = service
        let batchManager = batchManager ?? BatchManager()
        self.batchManager = batchManager
        self.accessState = LibraryAccessState(status: service.authorizationStatus())
        batchObservation = batchManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func enterSimilarMode() {
        guard accessState.canRead, assets != nil, !isLoading, !isDeleting else { return }
        isShowingSimilar = true
    }

    func similarPhotoSession(create: () -> SimilarPhotoQueue) -> SimilarPhotoQueue {
        if let similarSession { return similarSession }
        let session = create()
        similarSession = session
        return session
    }

    func isFavorite(_ asset: PhotoAsset) -> Bool {
        favoriteOverrides[asset.id] ?? asset.asset.isFavorite
    }

    func isUpdatingFavorite(_ asset: PhotoAsset) -> Bool {
        favoriteUpdates[asset.id] != nil
    }

    var currentFavoriteState: FavoriteButtonState {
        let index = batchManager.currentIndex
        guard batchManager.currentBatch.indices.contains(index) else {
            return FavoriteButtonState(isFavorite: false, isSaving: false)
        }
        let asset = batchManager.currentBatch[index]
        return FavoriteButtonState(
            isFavorite: favoriteUpdates[asset.id] ?? isFavorite(asset),
            isSaving: favoriteUpdates[asset.id] != nil
        )
    }

    func toggleFavorite(_ asset: PhotoAsset) {
        guard accessState.canRead, !isDeleting, favoriteUpdates[asset.id] == nil else { return }
        let newValue = !isFavorite(asset)
        favoriteLog.debug("Favorite update requested")
        favoriteUpdates[asset.id] = newValue
        Task {
            defer { favoriteUpdates.removeValue(forKey: asset.id) }
            do {
                try await service.setFavorite(newValue, for: asset.asset)
                favoriteOverrides[asset.id] = newValue
                favoriteLog.info("Favorite update saved")
            } catch {
                favoriteLog.error("Favorite update failed, code: \((error as NSError).code)")
                activeAlert = AppAlertState(title: "收藏更新失败", message: (error as NSError).localizedDescription)
            }
        }
    }

    func exitSimilarMode() {
        guard !isDeleting else { return }
        similarSession?.setActive(false)
        isShowingSimilar = false
    }

    func deleteSpecificAssets(_ assets: [PhotoAsset], completion: @escaping () -> Void) {
        guard !isDeleting else { return }
        guard !assets.isEmpty else {
            completion()
            return
        }
        isDeleting = true
        let phAssets = assets.map { $0.asset }
        Task {
            defer { isDeleting = false }
            do {
                try await service.deleteAssets(phAssets)
                similarSession?.recordDeletedAssets(Set(assets.map(\.id)))
                await reloadAssets(preservingSession: true)
                completion()
            } catch {
                presentDeleteError(error)
            }
        }
    }

    func refreshAccessState() {
        accessState = LibraryAccessState(status: service.authorizationStatus())
    }

    func requestPermissionAndLoad() {
        Task {
            let status = await service.requestAuthorization()
            accessState = LibraryAccessState(status: status)

            guard accessState.canRead else { return }
            await loadAssets()
        }
    }

    func loadAssets() async {
        guard !isDeleting, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await reloadAssets(preservingSession: false)
    }

    func reloadIfNeeded() {
        guard accessState.canRead, assets == nil, !isLoading else { return }
        Task { await loadAssets() }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active, !isDeleting else { return }
        let previousState = accessState
        refreshAccessState()

        guard accessState.canRead, accessState != previousState else { return }
        similarSession?.setActive(false)
        similarSession = nil
        isShowingSimilar = false
        Task { await loadAssets() }
    }

    func finishBatchInteraction() {
        guard !isDeleting else { return }
        isReviewingBatch = true
    }

    func recoverAsset(_ asset: PhotoAsset) {
        guard !isDeleting else { return }
        batchManager.recoverAsset(asset)
    }

    func skipBatch() {
        startNextBatch()
    }

    func startNextBatch() {
        guard !isDeleting else { return }
        batchManager.nextBatch()
    }

    func restartReview() {
        guard !isDeleting else { return }
        batchManager.restart()
    }

    func confirmDeletion() {
        guard !isDeleting else { return }
        guard !batchManager.pendingDeleteAssets.isEmpty else {
            startNextBatch()
            return
        }
        isDeleting = true
        let assetsToDelete = batchManager.pendingDeleteAssets.map { $0.asset }
        Task {
            defer { isDeleting = false }
            do {
                try await service.deleteAssets(assetsToDelete)
                similarSession?.recordDeletedAssets(Set(assetsToDelete.map(\.localIdentifier)))
                batchManager.clearPendingDeletes()
                await reloadAssets(preservingSession: true)
                batchManager.nextBatch()
            } catch {
                presentDeleteError(error)
            }
        }
    }

    private func reloadAssets(preservingSession: Bool) async {
        let result = await service.loadAssets()
        assets = result
        if preservingSession {
            batchManager.refreshAssetsPreservingSession(result)
        } else {
            batchManager.setAssets(result)
        }
    }

    private func presentDeleteError(_ error: Error) {
        let message = (error as NSError).localizedDescription
        activeAlert = AppAlertState(
            title: "删除失败",
            message: message.isEmpty ? "请稍后重试。" : message
        )
    }
}
