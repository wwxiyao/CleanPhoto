import Foundation
import Photos
import Testing
@testable import CleanPhotoLogic

@MainActor
struct AlbumSelectionTests {
    private func group(_ ids: [String]) -> SimilarGroup {
        SimilarGroup(assets: ids.map { PhotoAsset(asset: FixtureAsset($0)) })
    }

    @Test func combinesSelectionsAcrossGroupsWithoutDuplicatePhotos() {
        var first = group(["0", "1", "2"])
        var second = group(["2", "3", "4"])
        first.selectedForDelete = ["0", "2"]
        second.selectedForDelete = ["2", "4"]
        let queue = SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        queue.groups = [first, second]
        #expect(Set(queue.selectedAssets.map(\.id)) == ["0", "2", "4"])
        #expect(queue.selectedAssets.count == 3)
    }

    @Test func retainingOneGroupRemovesItsSelectionsButNotOtherGroups() {
        var first = group(["0", "1"])
        var second = group(["2", "3"])
        first.selectedForDelete = ["0"]
        second.selectedForDelete = ["2"]
        let queue = SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        queue.groups = [first, second]
        queue.removeGroup(first.id)
        #expect(queue.selectedAssets.map(\.id) == ["2"])
    }

    @Test func groupHeadingTracksTotalAndSelectionWithinThatGroup() {
        let first = group((0..<12).map(String.init))
        let second = group(["30", "31"])
        let queue = SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        queue.groups = [first, second]
        let utc = TimeZone(secondsFromGMT: 0)!
        #expect(SimilarGroupHeading.summary(for: queue.groups[0], timeZone: utc) == "1970-01-01 · 共 12 张 · 已选 0 张")
        queue.toggleSelection("3", in: first.id)
        queue.toggleSelection("7", in: first.id)
        queue.toggleSelection("30", in: second.id)
        #expect(SimilarGroupHeading.summary(for: queue.groups[0], timeZone: utc) == "1970-01-01 · 共 12 张 · 已选 2 张")
        queue.toggleSelection("3", in: first.id)
        #expect(SimilarGroupHeading.summary(for: queue.groups[0], timeZone: utc) == "1970-01-01 · 共 12 张 · 已选 1 张")
    }

    @Test func combinedDeleteSubmitsOnceAndClearsSelectionsOnlyAfterSuccess() async {
        let defaults = UserDefaults(suiteName: "AlbumSelectionTests.\(UUID().uuidString)")!
        let service = ControlledPhotoService()
        let model = LibraryViewModel(service: service, batchManager: BatchManager(sessionStore: ReviewSessionStore(defaults: defaults)))
        await model.loadAssets()
        let queue = model.similarPhotoSession {
            SimilarPhotoQueue { _, _ in SimilarScanPage(groups: [], hasMore: false) }
        }
        var first = group(["0", "1", "2"])
        var second = group(["3", "4", "5"])
        first.selectedForDelete = ["0"]
        second.selectedForDelete = ["3"]
        queue.groups = [first, second]
        model.deleteSpecificAssets(queue.selectedAssets) {}
        let deadline = ContinuousClock.now + .seconds(2)
        while service.pending == nil, ContinuousClock.now < deadline { await Task.yield() }
        #expect(service.deletedIDs.count == 1)
        #expect(Set(service.deletedIDs.first ?? []) == ["0", "3"])
        #expect(queue.selectedAssets.count == 2)
        service.finish(.success(()))
        while model.isDeleting, ContinuousClock.now < deadline { await Task.yield() }
        #expect(!model.isDeleting)
        #expect(queue.groups.count == 2)
        #expect(queue.selectedAssets.isEmpty)
    }
}

@MainActor
struct ThumbnailQualityTests {
    @Test func threeColumnsAndOneColumnRequestDifferentPixelSizes() {
        let small = PhotoThumbnailRequest(assetID: "a", sourceSize: CGSize(width: 3000, height: 4000), displayWidth: 130, displayScale: 3, scaleMode: .fill, highQuality: true)
        let large = PhotoThumbnailRequest(assetID: "a", sourceSize: CGSize(width: 3000, height: 4000), displayWidth: 402, displayScale: 3, scaleMode: .fit, highQuality: true)
        #expect(small != large)
        #expect(small.targetSize.width == 390)
        #expect(large.targetSize.width == 1206)
        #expect(large.targetSize.height == 1608)
        #expect(large.deliveryMode == .opportunistic)
        #expect(large.resizeMode == .exact)
    }

    @Test func numericHeadingDoesNotDependOnDeviceDateStyle() {
        let date = Date(timeIntervalSince1970: 1_793_016_000)
        let value = SimilarGroupHeading.text(date: date, timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(value == "2026-10-26")
    }
}
