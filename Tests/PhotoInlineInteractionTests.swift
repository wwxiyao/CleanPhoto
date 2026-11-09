import CoreGraphics
import Testing
@testable import CleanPhotoLogic

@MainActor
struct PhotoInlineInteractionTests {
    @Test func ordinarySwipeStillClassifies() {
        var interaction = PhotoInlineInteraction()
        interaction.beginDrag(zoomScale: 1, touches: 1)
        #expect(interaction.endDrag(translation: CGSize(width: 0, height: -200)) == .pendingDelete)
    }

    @Test func zoomedDragCannotClassify() {
        var interaction = PhotoInlineInteraction()
        interaction.beginDrag(zoomScale: 3, touches: 1)
        #expect(interaction.endDrag(translation: CGSize(width: -200, height: 0)) == nil)
    }

    @Test func pinchCancelsSwipeEvenAfterReturningToFit() {
        var interaction = PhotoInlineInteraction()
        interaction.beginDrag(zoomScale: 1, touches: 1)
        interaction.beginZoom()
        #expect(!interaction.canReview)
        #expect(interaction.endDrag(translation: CGSize(width: 0, height: -200)) == nil)
        interaction.beginDrag(zoomScale: 1, touches: 1)
        #expect(interaction.endDrag(translation: CGSize(width: -200, height: 0)) == .keep)
    }

    @Test func twoFingerDragCannotClassify() {
        var interaction = PhotoInlineInteraction()
        interaction.beginDrag(zoomScale: 1, touches: 2)
        #expect(interaction.endDrag(translation: CGSize(width: 0, height: -200)) == nil)
    }
}
