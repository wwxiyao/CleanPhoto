import CoreGraphics

nonisolated enum AlbumPhotoLayout {
    static func tileSize(width: CGFloat, columns: Int, aspectRatio: CGFloat) -> CGSize {
        let width = max(1, width)
        let tileWidth = columns == 1 ? width : max(1, (width - 8) / 3)
        let ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
        return CGSize(width: tileWidth, height: tileWidth / ratio)
    }
}
