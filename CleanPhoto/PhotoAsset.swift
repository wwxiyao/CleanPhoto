import Photos
import CoreLocation

nonisolated struct PhotoAsset: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let creationDate: Date?
    let location: CLLocation?
    let pixelWidth: Int
    let pixelHeight: Int

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.creationDate = asset.creationDate
        self.location = asset.location
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
    }

    var aspectRatio: Double {
        guard pixelHeight > 0 else { return 0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    var longerSide: Int {
        max(pixelWidth, pixelHeight)
    }
}
