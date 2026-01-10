import SwiftUI

struct SwipeContainerView: View {
    let assets: [PhotoAsset]
    let onSwipeUp: (PhotoAsset) -> Void
    let onSwipeLeft: (PhotoAsset) -> Void
    let onFinished: () -> Void
    
    @State private var currentIndex = 0
    
    var body: some View {
        GeometryReader { proxy in
            let cardWidth = min(proxy.size.width * 0.9, 420)
            let cardHeight = min(proxy.size.height * 0.72, 600)

            ZStack {
                if currentIndex < assets.count {
                    let progressText = "\(currentIndex + 1)/\(assets.count)"

                    // The current active card
                    SwipeCardView(
                        asset: assets[currentIndex],
                        progressText: progressText,
                        onSwipeUp: {
                            onSwipeUp(assets[currentIndex])
                            advance()
                        },
                        onSwipeLeft: {
                            onSwipeLeft(assets[currentIndex])
                            advance()
                        }
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
}
