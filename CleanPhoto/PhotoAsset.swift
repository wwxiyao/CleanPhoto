import Photos
import CoreLocation

struct PhotoAsset: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let creationDate: Date?
    let location: CLLocation?

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.creationDate = asset.creationDate
        self.location = asset.location
    }
}
