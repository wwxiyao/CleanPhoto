import SwiftUI
import Photos

struct SwipeCardView: View {
    let asset: PhotoAsset
    let onSwipeUp: () -> Void
    let onSwipeLeft: () -> Void
    
    @State private var offset: CGSize = .zero
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .shadow(radius: 5)
            
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                ProgressView()
            }
            
            // Visual indicators for swipe direction
            VStack {
                if offset.height < -50 {
                    Image(systemName: "trash")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                        .padding()
                        .background(Circle().fill(.white.opacity(0.8)))
                        .transition(.scale)
                }
                Spacer()
                if offset.width < -50 {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                        .padding()
                        .background(Circle().fill(.white.opacity(0.8)))
                        .transition(.scale)
                }
            }
            .padding(40)
        }
        .offset(offset)
        .rotationEffect(.degrees(Double(offset.width / 20)))
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    offset = gesture.translation
                }
                .onEnded { gesture in
                    handleDragEnded(gesture)
                }
        )
        .task {
            image = await requestImage()
        }
    }
    
    private func handleDragEnded(_ gesture: DragGesture) {
        let horizontalThreshold: CGFloat = -150
        let verticalThreshold: CGFloat = -150
        
        if gesture.translation.height < verticalThreshold {
            // Swipe Up -> Delete
            withAnimation(.spring()) {
                offset = CGSize(width: 0, height: -1000)
            }
            onSwipeUp()
        } else if gesture.translation.width < horizontalThreshold {
            // Swipe Left -> Keep
            withAnimation(.spring()) {
                offset = CGSize(width: -1000, height: 0)
            }
            onSwipeLeft()
        } else {
            // Reset
            withAnimation(.spring()) {
                offset = .zero
            }
        }
    }
    
    private func requestImage() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestImage(
                for: asset.asset,
                targetSize: CGSize(width: 1000, height: 1000),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
