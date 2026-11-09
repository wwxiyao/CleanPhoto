import CoreGraphics
import Photos
import Testing
@testable import CleanPhotoLogic

struct PhotoDetailTests {
    @Test func similarPreviewContainsOnlyItsOwnGroupAndOpensTappedPhoto() {
        let a = PhotoAsset(asset: FixtureAsset("0"))
        let b = PhotoAsset(asset: FixtureAsset("1"))
        let c = PhotoAsset(asset: FixtureAsset("2"))
        let session = PhotoDetailSession(group: SimilarGroup(assets: [b, c]), opening: c)
        #expect(session.assets.map(\.id) == ["1", "2"])
        #expect(!session.assets.contains(a))
        #expect(session.initialIndex == 1)
    }

    @Test func zoomFitsWidePhotoAndAllowsInspectingPixels() {
        let fit = PhotoDetailGeometry.fittedSize(image: CGSize(width: 4000, height: 2000), viewport: CGSize(width: 400, height: 800))
        #expect(fit == CGSize(width: 400, height: 200))
        #expect(PhotoDetailGeometry.maximumZoom(image: CGSize(width: 4000, height: 2000), fitted: fit) == 10)
        #expect(PhotoDetailGeometry.fittedSize(image: .zero, viewport: .zero) == .zero)
    }
    @Test func batchPreviewDoesNotChangeOrderOrOpenAtFirstPhoto() {
        let photos = (0..<10).map { PhotoAsset(asset: FixtureAsset(String($0))) }
        let session = PhotoDetailSession(assets: photos, opening: photos[6])
        #expect(session.assets.map(\.id) == photos.map(\.id))
        #expect(session.initialIndex == 6)
    }

    @Test func originalIsDeferredUntilZoomAndOnlyRequestedOnce() {
        var state = PhotoDetailLoadingState()
        #expect(!state.originalRequested)
        let firstRequest = state.requestOriginal()
        let duplicateRequest = state.requestOriginal()
        #expect(firstRequest)
        #expect(!duplicateRequest)
        state = PhotoDetailLoadingState()
        #expect(!state.originalRequested)
        let preview = PhotoDetailLoadingState.previewSize(source: CGSize(width: 8000, height: 6000))
        #expect(preview == CGSize(width: 1600, height: 1200))
    }

    @Test func pagingPreparesNextPhotoBeforeCurrentPageChanges() {
        #expect(PhotoDetailPagingWindow.indices(current: 0, count: 8) == Set([0, 1]))
        #expect(PhotoDetailPagingWindow.indices(current: 3, count: 8) == Set([2, 3, 4]))
        #expect(PhotoDetailPagingWindow.indices(current: 7, count: 8) == Set([6, 7]))
        #expect(PhotoDetailPagingWindow.indices(current: 0, count: 0).isEmpty)
    }

    @Test func detailHeaderCountsOnlySelectionsInsideCurrentGroup() {
        let photos = (0..<8).map { PhotoAsset(asset: FixtureAsset(String($0))) }
        let session = PhotoDetailSession(assets: photos, opening: photos[2])
        #expect(session.heading(index: 2, selectedIDs: ["0", "3", "99"]) == "3-8 · 已选 2 张")
        #expect(session.heading(index: 3, selectedIDs: ["3"]) == "4-8 · 已选 1 张")
    }

}
