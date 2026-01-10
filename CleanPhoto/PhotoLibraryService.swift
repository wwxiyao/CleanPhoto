import Photos

final class PhotoLibraryService {
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
                // Sort by creation date ascending (Oldest first) to match typical cleaning flow
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

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
}
