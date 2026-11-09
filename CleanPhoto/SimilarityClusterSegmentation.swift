import Foundation

nonisolated enum SimilarityClusterSegmentation {
    static func segments(_ cluster: [PhotoAsset], isLargeCluster: Bool) -> [[PhotoAsset]] {
        let maximumCount = 80
        guard isLargeCluster || cluster.count > maximumCount else { return [cluster] }
        var segments: [[PhotoAsset]] = []
        var current: [PhotoAsset] = []
        for asset in cluster {
            guard let date = asset.creationDate else {
                if current.count > 1 { segments.append(current) }
                current.removeAll(keepingCapacity: true)
                continue
            }
            guard let lastDate = current.last?.creationDate else {
                current = [asset]
                continue
            }
            if abs(date.timeIntervalSince(lastDate)) <= 2.5, current.count < maximumCount {
                current.append(asset)
            } else {
                if current.count > 1 { segments.append(current) }
                current = [asset]
            }
        }
        if current.count > 1 { segments.append(current) }
        if !segments.isEmpty { return segments }
        // Preserve the original fallback when there are no tighter segments.
        return stride(from: 0, to: cluster.count, by: maximumCount).compactMap { start in
            let chunk = Array(cluster[start..<min(start + maximumCount, cluster.count)])
            return chunk.count > 1 ? chunk : nil
        }
    }
}
