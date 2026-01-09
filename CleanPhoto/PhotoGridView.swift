import Photos
import SwiftUI
import UIKit

struct PhotoGridView: View {
    let assets: [PhotoAsset]

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(assets) { asset in
                    PhotoThumbnailView(asset: asset)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

struct PhotoThumbnailView: View {
    let asset: PhotoAsset

    @State private var image: UIImage?
    private let targetSize = CGSize(width: 240, height: 240)

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemBackground))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(height: 110)
        .clipped()
        .cornerRadius(10)
        .task(id: asset.id) {
            image = await requestThumbnail()
        }
    }

    private func requestThumbnail() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset.asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

#Preview {
    PhotoGridView(assets: [])
}
