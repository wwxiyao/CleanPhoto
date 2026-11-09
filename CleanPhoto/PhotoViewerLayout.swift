import Foundation
import CoreGraphics

enum PhotoViewerLayout {
    static func sizeWithAccessories(photoSize: CGSize, availableSize: CGSize, accessoryHeight: CGFloat) -> CGSize {
        fittedSize(photoSize: photoSize,
                   availableSize: CGSize(width: availableSize.width,
                                         height: max(0, availableSize.height - accessoryHeight)))
    }

    static func fittedSize(photoSize: CGSize, availableSize: CGSize) -> CGSize {
        guard photoSize.width > 0, photoSize.height > 0,
              availableSize.width > 0, availableSize.height > 0 else { return .zero }
        let scale = min(availableSize.width / photoSize.width, availableSize.height / photoSize.height)
        return CGSize(width: photoSize.width * scale, height: photoSize.height * scale)
    }
}

enum PhotoSwipeDecision {
    static let activationDistance: CGFloat = 150

    case keep
    case pendingDelete

    static func resolve(translation: CGSize) -> Self? {
        guard let intent = intent(translation: translation),
              max(abs(translation.width), abs(translation.height)) > activationDistance else { return nil }
        return intent
    }

    static func intent(translation: CGSize) -> Self? {
        if abs(translation.height) > abs(translation.width), translation.height < 0 {
            return .pendingDelete
        }
        if abs(translation.width) >= abs(translation.height), translation.width < 0 {
            return .keep
        }
        return nil
    }
}

struct PhotoSwipeFeedback {
    let decision: PhotoSwipeDecision
    let progress: Double
    let isReady: Bool

    static func current(translation: CGSize) -> Self? {
        let startDistance: CGFloat = 24
        let distance = max(abs(translation.width), abs(translation.height))
        guard distance > startDistance, let decision = PhotoSwipeDecision.intent(translation: translation) else { return nil }
        let progress = min(1, (distance - startDistance) / (PhotoSwipeDecision.activationDistance - startDistance))
        return Self(decision: decision, progress: Double(progress), isReady: PhotoSwipeDecision.resolve(translation: translation) != nil)
    }
}

/// A pinch consumes the current drag, even if the photo returns to fit before lift-off.
struct PhotoInlineInteraction {
    private(set) var canReview = false

    mutating func beginDrag(zoomScale: CGFloat, touches: Int) {
        canReview = zoomScale <= 1.01 && touches == 1
    }

    mutating func beginZoom() { canReview = false }

    mutating func endDrag(translation: CGSize) -> PhotoSwipeDecision? {
        defer { canReview = false }
        return canReview ? PhotoSwipeDecision.resolve(translation: translation) : nil
    }
}
