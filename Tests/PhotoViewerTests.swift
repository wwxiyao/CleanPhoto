import Foundation
import Testing
@testable import CleanPhotoLogic

@MainActor
struct PhotoViewerTests {
    @Test func portraitPhotoUsesFullAvailableWidth() {
        let size = PhotoViewerLayout.fittedSize(photoSize: CGSize(width: 3000, height: 4000), availableSize: CGSize(width: 402, height: 650))
        #expect(size.width == 402)
        #expect(abs(size.height - 536) < 0.001)
    }

    @Test func landscapePhotoIsNotCroppedInPortrait() {
        let size = PhotoViewerLayout.fittedSize(photoSize: CGSize(width: 4000, height: 3000), availableSize: CGSize(width: 402, height: 650))
        #expect(size == CGSize(width: 402, height: 301.5))
    }

    @Test func landscapeViewerUsesAllAvailableHeight() {
        let size = PhotoViewerLayout.fittedSize(photoSize: CGSize(width: 4000, height: 3000), availableSize: CGSize(width: 600, height: 340))
        #expect(abs(size.width - 453.333333) < 0.001)
        #expect(size.height == 340)
    }

    @Test func largeScreenHasNoOld420PointWidthLimit() {
        let size = PhotoViewerLayout.fittedSize(photoSize: CGSize(width: 3000, height: 4000), availableSize: CGSize(width: 800, height: 1100))
        #expect(size.width == 800)
    }

    @Test func emptyGeometryProducesEmptySize() {
        #expect(PhotoViewerLayout.fittedSize(photoSize: .zero, availableSize: CGSize(width: 400, height: 600)) == .zero)
        #expect(PhotoViewerLayout.fittedSize(photoSize: CGSize(width: 400, height: 600), availableSize: .zero) == .zero)
    }

    @Test func rightSwipeDoesNothing() {
        #expect(PhotoSwipeDecision.resolve(translation: CGSize(width: 220, height: 0)) == nil)
    }

    @Test func leftSwipeKeepsAndUpSwipeSelectsForDeletion() {
        #expect(PhotoSwipeDecision.resolve(translation: CGSize(width: -220, height: 20)) == .keep)
        #expect(PhotoSwipeDecision.resolve(translation: CGSize(width: 20, height: -220)) == .pendingDelete)
        #expect(PhotoSwipeDecision.resolve(translation: CGSize(width: 50, height: 50)) == nil)
    }

    @Test func tinyMovementHasNoFeedback() {
        #expect(PhotoSwipeFeedback.current(translation: CGSize(width: 0, height: -15)) == nil)
        #expect(PhotoSwipeFeedback.current(translation: CGSize(width: 180, height: 0)) == nil)
    }

    @Test func upwardFeedbackBuildsBeforeDeletionIsTriggered() throws {
        let feedback = try #require(PhotoSwipeFeedback.current(translation: CGSize(width: 0, height: -80)))
        #expect(feedback.decision == .pendingDelete)
        #expect(feedback.progress > 0 && feedback.progress < 1)
        #expect(!feedback.isReady)
        #expect(PhotoSwipeDecision.resolve(translation: CGSize(width: 0, height: -80)) == nil)
    }

    @Test func feedbackUsesSameThresholdAndDirectionAsAction() throws {
        let translation = CGSize(width: -180, height: -90)
        let feedback = try #require(PhotoSwipeFeedback.current(translation: translation))
        #expect(feedback.decision == .keep)
        #expect(feedback.progress == 1)
        #expect(feedback.isReady)
        #expect(feedback.decision == PhotoSwipeDecision.resolve(translation: translation))
    }

    @Test func feedbackClearsWhenFingerReturnsAndCanChangeDirection() throws {
        let up = try #require(PhotoSwipeFeedback.current(translation: CGSize(width: -40, height: -90)))
        #expect(up.decision == .pendingDelete)
        let left = try #require(PhotoSwipeFeedback.current(translation: CGSize(width: -100, height: -40)))
        #expect(left.decision == .keep)
        #expect(PhotoSwipeFeedback.current(translation: .zero) == nil)
    }
}

@MainActor
struct PhotoAccessoryLayoutTests {
    @Test func tallPhotoLeavesRoomForButtonsBelowItsActualEdge() {
        let size = PhotoViewerLayout.sizeWithAccessories(photoSize: CGSize(width: 3000, height: 6000), availableSize: CGSize(width: 402, height: 650), accessoryHeight: 52)
        #expect(size == CGSize(width: 299, height: 598))
        #expect(size.height + 52 == 650)
    }

    @Test func landscapePhotoKeepsItsOwnWidthAndBottomEdge() {
        let size = PhotoViewerLayout.sizeWithAccessories(photoSize: CGSize(width: 4000, height: 2000), availableSize: CGSize(width: 402, height: 650), accessoryHeight: 74)
        #expect(size == CGSize(width: 402, height: 201))
    }
}
