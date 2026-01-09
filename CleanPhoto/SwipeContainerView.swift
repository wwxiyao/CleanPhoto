import SwiftUI

struct SwipeContainerView: View {
    let assets: [PhotoAsset]
    let onSwipeUp: (PhotoAsset) -> Void
    let onSwipeLeft: (PhotoAsset) -> Void
    let onFinished: () -> Void
    
    @State private var currentIndex = 0
    
    var body: some View {
        ZStack {
            if currentIndex < assets.count {
                // Show a background card for stack effect if there's more
                if currentIndex + 1 < assets.count {
                    SwipeCardView(
                        asset: assets[currentIndex + 1],
                        onSwipeUp: {},
                        onSwipeLeft: {}
                    )
                    .scaleEffect(0.95)
                    .offset(y: 10)
                    .opacity(0.8)
                    .disabled(true)
                }
                
                // The current active card
                SwipeCardView(
                    asset: assets[currentIndex],
                    onSwipeUp: {
                        onSwipeUp(assets[currentIndex])
                        advance()
                    },
                    onSwipeLeft: {
                        onSwipeLeft(assets[currentIndex])
                        advance()
                    }
                )
                .id(assets[currentIndex].id) // Ensure view identity changes
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    Text("Batch Complete!")
                        .font(.title2.bold())
                    Button("Review Selection") {
                        onFinished()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }
    
    private func advance() {
        withAnimation {
            currentIndex += 1
        }
    }
}
