import SwiftUI
import UIKit

struct SwipeContainerView: View {
    let assets: [PhotoAsset]
    let onSwipeUp: (PhotoAsset) -> Void
    let onSwipeLeft: (PhotoAsset) -> Void
    var onUndo: (() -> Void)? = nil
    let onFinished: () -> Void
    
    @State private var currentIndex = 0
    
    var body: some View {
        GeometryReader { proxy in
            let cardWidth = min(proxy.size.width * 0.9, 420)
            let cardHeight = min(proxy.size.height * 0.72, 600)

            ZStack {
                // Render the next card first (at the bottom) so it pre-loads
                if currentIndex + 1 < assets.count {
                     SwipeCardView(
                        asset: assets[currentIndex + 1],
                        progressText: "\(currentIndex + 2)/\(assets.count)",
                        onSwipeUp: {}, // Helper card, no actions needed really but View requires it
                        onSwipeLeft: {},
                        onSwipeRight: nil
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    // Offset it slightly to look like a stack
                    .scaleEffect(0.95)
                    .offset(y: 10)
                    .opacity(0.6)
                    .disabled(true) // Disable interaction for the background card
                }
                
                if currentIndex < assets.count {
                    let progressText = "\(currentIndex + 1)/\(assets.count)"

                    // The current active card
                    SwipeCardView(
                        asset: assets[currentIndex],
                        progressText: progressText,
                        onSwipeUp: {
                            triggerHaptic(style: .medium)
                            onSwipeUp(assets[currentIndex])
                            advance()
                        },
                        onSwipeLeft: {
                            triggerHaptic(style: .light)
                            onSwipeLeft(assets[currentIndex])
                            advance()
                        },
                        onSwipeRight: currentIndex > 0 ? {
                            triggerHaptic(style: .light)
                            regress()
                        } : nil
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    .id(assets[currentIndex].id) // Ensure view identity changes
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        Text("本批次完成！")
                            .font(.title2.bold())
                        Button("检查已选项目") {
                            onFinished()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
    
    private func advance() {
        withAnimation {
            currentIndex += 1
        }
    }
    
    private func regress() {
        withAnimation {
            currentIndex -= 1
            onUndo?()
        }
    }
    
    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}
