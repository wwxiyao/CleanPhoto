import CoreGraphics
import Foundation

nonisolated struct PhotoDetailSession: Identifiable {
    let id = UUID()
    let assets: [PhotoAsset]
    let initialIndex: Int

    func heading(index: Int, selectedIDs: Set<String>) -> String {
        let selected = assets.filter { selectedIDs.contains($0.id) }.count
        return "\(index + 1)-\(assets.count) · 已选 \(selected) 张"
    }

    init(group: SimilarGroup, opening asset: PhotoAsset) {
        self.init(assets: group.assets, opening: asset)
    }

    init(assets: [PhotoAsset], opening asset: PhotoAsset) {
        var seen: Set<String> = []
        var photos = assets.filter { seen.insert($0.id).inserted }
        if !photos.contains(where: { $0.id == asset.id }) { photos.append(asset) }
        self.assets = photos
        initialIndex = photos.firstIndex(where: { $0.id == asset.id }) ?? 0
    }
}

nonisolated enum PhotoDetailGeometry {
    static func fittedSize(image: CGSize, viewport: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale = min(viewport.width / image.width, viewport.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    static func maximumZoom(image: CGSize, fitted: CGSize) -> CGFloat {
        guard fitted.width > 0, fitted.height > 0 else { return 3 }
        return max(3, min(12, max(image.width / fitted.width, image.height / fitted.height)))
    }
}

nonisolated struct PhotoDetailLoadingState {
    private(set) var originalRequested = false

    mutating func requestOriginal() -> Bool {
        guard !originalRequested else { return false }
        originalRequested = true
        return true
    }

    static func previewSize(source: CGSize) -> CGSize {
        let width = max(1, source.width)
        let height = max(1, source.height)
        let scale = min(1, 1600 / max(width, height))
        return CGSize(width: width * scale, height: height * scale)
    }
}

nonisolated enum PhotoDetailPagingWindow {
    static func indices(current: Int, count: Int) -> Set<Int> {
        guard count > 0, current >= 0, current < count else { return [] }
        return Set(max(0, current - 1)...min(count - 1, current + 1))
    }
}
