import Photos

@MainActor
protocol PhotoLibraryProviding {
    func authorizationStatus() -> PHAuthorizationStatus
    func requestAuthorization() async -> PHAuthorizationStatus
    func loadAssets() async -> PHFetchResult<PHAsset>
    func deleteAssets(_ assets: [PHAsset]) async throws
    func setFavorite(_ favorite: Bool, for asset: PHAsset) async throws
}

@MainActor
final class PhotoLibraryService: PhotoLibraryProviding {
    func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    func loadAssets() async -> PHFetchResult<PHAsset> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let options = PHFetchOptions()
                // Start chronological browsing and similarity scanning with the newest photos.
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

                let result = PHAsset.fetchAssets(with: .image, options: options)
                continuation.resume(returning: result)
            }
        }
    }

    func deleteAssets(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    func setFavorite(_ favorite: Bool, for asset: PHAsset) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).isFavorite = favorite
        }
    }
}
