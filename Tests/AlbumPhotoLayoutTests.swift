import CoreGraphics
import Testing
@testable import CleanPhotoLogic

struct AlbumPhotoLayoutTests {
    @Test func landscapeAndPortraitHaveSeparateSingleColumnHeights() {
        #expect(AlbumPhotoLayout.tileSize(width: 400, columns: 1, aspectRatio: 2) == CGSize(width: 400, height: 200))
        #expect(AlbumPhotoLayout.tileSize(width: 400, columns: 1, aspectRatio: 0.5) == CGSize(width: 400, height: 800))
    }

    @Test func threeColumnsPreserveLandscapeAspectRatio() {
        let size = AlbumPhotoLayout.tileSize(width: 398, columns: 3, aspectRatio: 2)
        #expect(size == CGSize(width: 130, height: 65))
        #expect(size.width * 3 + 8 == 398)
    }
    @Test func threeColumnsPreservePortraitHeadAndFeet() {
        let size = AlbumPhotoLayout.tileSize(width: 398, columns: 3, aspectRatio: 0.5)
        #expect(size == CGSize(width: 130, height: 260))
    }

    @Test func unknownRatioUsesSafeSquareFallback() {
        #expect(AlbumPhotoLayout.tileSize(width: 398, columns: 3, aspectRatio: 0) == CGSize(width: 130, height: 130))
    }
}
