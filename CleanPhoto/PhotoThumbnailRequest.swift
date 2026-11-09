import CoreGraphics
import Photos

nonisolated enum ThumbnailScaleMode: Hashable {
    case fill
    case fit
}

/// The request identity includes resolution so enlarging a thumbnail reloads it.
nonisolated struct PhotoThumbnailRequest: Hashable {
    let assetID: String
    let targetWidth: Int
    let targetHeight: Int
    let scaleMode: ThumbnailScaleMode
    let highQuality: Bool

    init(assetID: String, sourceSize: CGSize, displayWidth: CGFloat?, displayScale: CGFloat, scaleMode: ThumbnailScaleMode, highQuality: Bool) {
        self.assetID = assetID
        self.scaleMode = scaleMode
        self.highQuality = highQuality
        let sourceWidth = max(1, sourceSize.width)
        let sourceHeight = max(1, sourceSize.height)
        let requestedWidth = displayWidth.map { max(1, $0 * displayScale) }
            ?? (highQuality ? sourceWidth : (scaleMode == .fill ? 360 : 1200))
        let width = min(sourceWidth, requestedWidth)
        let height = scaleMode == .fill ? width : width * sourceHeight / sourceWidth
        let reduction = min(1, 2400 / max(width, height))
        targetWidth = max(1, Int(ceil(width * reduction)))
        targetHeight = max(1, Int(ceil(height * reduction)))
    }

    var targetSize: CGSize { CGSize(width: targetWidth, height: targetHeight) }
    var deliveryMode: PHImageRequestOptionsDeliveryMode { .opportunistic }
    var resizeMode: PHImageRequestOptionsResizeMode { .exact }
}
