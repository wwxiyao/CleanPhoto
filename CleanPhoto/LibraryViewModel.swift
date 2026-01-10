import SwiftUI
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var accessState: LibraryAccessState
    @Published private(set) var assets: [PhotoAsset] = []
    @Published private(set) var isLoading = false

    @Published var isReviewingBatch = false
    @Published var isDeleting = false
    @Published var isShowingSimilar = false

    private let service: PhotoLibraryService
    let batchManager = BatchManager()

    init(service: PhotoLibraryService) {
        self.service = service
        self.accessState = LibraryAccessState(status: service.authorizationStatus())
    }

    func enterSimilarMode() {
        isShowingSimilar = true
    }

    func exitSimilarMode() {
        isShowingSimilar = false
    }

    func deleteSpecificAssets(_ assets: [PhotoAsset], completion: @escaping () -> Void) {
        guard !assets.isEmpty else {
            completion()
            return
        }
        
        isDeleting = true
        Task {
            do {
                let phAssets = assets.map { $0.asset }
                try await service.deleteAssets(phAssets)
                // Remove from local array to update UI immediately if needed
                let idsToDelete = Set(assets.map { $0.id })
                self.assets.removeAll { idsToDelete.contains($0.id) }
                await MainActor.run {
                    completion()
                }
            } catch {
                print("Deletion failed: \(error)")
            }
            isDeleting = false
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
        isLoading = true
        defer { isLoading = false }
        assets = await service.loadAssets()
        batchManager.setAssets(assets)
    }

    func reloadIfNeeded() {
        guard accessState.canRead, assets.isEmpty, !isLoading else { return }
        Task { await loadAssets() }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else { return }
        let previousState = accessState
        refreshAccessState()

        guard accessState.canRead, accessState != previousState else { return }
        Task { await loadAssets() }
    }

    func finishBatchInteraction() {
        isReviewingBatch = true
    }

    func recoverAsset(_ asset: PhotoAsset) {
        batchManager.recoverAsset(asset)
    }

    func skipBatch() {
        isReviewingBatch = false
        batchManager.nextBatch()
    }

    func startNextBatch() {
        isReviewingBatch = false
        batchManager.nextBatch()
    }

    func confirmDeletion() {
        guard !batchManager.pendingDeleteAssets.isEmpty else {
            startNextBatch()
            return
        }

        isDeleting = true
        Task {
            do {
                let assetsToDelete = batchManager.pendingDeleteAssets.map { $0.asset }
                try await service.deleteAssets(assetsToDelete)
                batchManager.clearPendingDeletes()
                startNextBatch()
            } catch {
                print("Deletion failed: \(error)")
                // In a real app, show an alert
            }
            isDeleting = false
        }
    }
}
