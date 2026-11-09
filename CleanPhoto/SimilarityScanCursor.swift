import Photos

// A value checkpoint allows an interrupted page to resume without losing groups.
nonisolated struct SimilarityScanCursor {
    private let fetchResult: PHFetchResult<PHAsset>?
    private let reversed: Bool
    private var index = 0
    private var pendingCluster: [PhotoAsset] = []
    private var isLargeCluster = false

    init(fetchResult: PHFetchResult<PHAsset>?, reversed: Bool = false) {
        self.fetchResult = fetchResult
        self.reversed = reversed
    }

    var isExhausted: Bool {
        index >= (fetchResult?.count ?? 0) && pendingCluster.isEmpty
    }

    mutating func nextCluster(assetBudget: Int) -> (assets: [PhotoAsset], inspectedCount: Int, isLargeCluster: Bool) {
        guard let fetchResult, assetBudget > 0 else { return ([], 0, false) }
        var inspected = 0
        while index < fetchResult.count, inspected < assetBudget {
            let asset = PhotoAsset(asset: fetchResult.object(at: reversed ? fetchResult.count - 1 - index : index))
            index += 1
            inspected += 1
            if let last = pendingCluster.last {
                let closeInTime: Bool
                if let date = asset.creationDate, let lastDate = last.creationDate {
                    closeInTime = abs(date.timeIntervalSince(lastDate)) < 10
                } else {
                    closeInTime = false
                }
                if !closeInTime {
                    let finished = pendingCluster
                    let wasLarge = isLargeCluster
                    pendingCluster = [asset]
                    isLargeCluster = false
                    return (finished, inspected, wasLarge)
                }
            }
            pendingCluster.append(asset)
            // One look-ahead distinguishes an exact 80-photo cluster from a long sequence.
            if pendingCluster.count > 80 {
                let finished = Array(pendingCluster.prefix(80))
                pendingCluster.removeFirst(80)
                isLargeCluster = true
                return (finished, inspected, true)
            }
        }
        if index == fetchResult.count {
            let finished = pendingCluster
            let wasLarge = isLargeCluster
            pendingCluster.removeAll(keepingCapacity: true)
            isLargeCluster = false
            return (finished, inspected, wasLarge)
        }
        return ([], inspected, isLargeCluster)
    }
}
