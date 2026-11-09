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
    var height: CGFloat? = 110
    var cornerRadius: CGFloat = 10
    var scaleMode: ThumbnailScaleMode = .fill
    var highQuality: Bool = false

    var displayWidth: CGFloat? = nil
    @Environment(\.displayScale) private var displayScale
    @State private var loadedAssetID: String?

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID
    @State private var isDownloadingOriginal = false

    private var thumbnailRequest: PhotoThumbnailRequest {
        PhotoThumbnailRequest(assetID: asset.id,
                              sourceSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                              displayWidth: displayWidth, displayScale: displayScale,
                              scaleMode: scaleMode, highQuality: highQuality)
    }

    private var requestContentMode: PHImageContentMode {
        switch scaleMode {
        case .fill:
            return .aspectFill
        case .fit:
            return .aspectFit
        }
    }

    var body: some View {
        let card = ZStack {
            Rectangle()
                .fill(Color(.secondarySystemBackground))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .modifier(ThumbnailScaleModifier(mode: scaleMode))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        Group {
            if let height {
                card.frame(height: height)
            } else {
                card.aspectRatio(max(asset.aspectRatio, 0.1), contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(alignment: .bottomTrailing) {
            if highQuality && isDownloadingOriginal {
                ProgressView()
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
                    .allowsHitTesting(false)
                    .accessibilityLabel("正在加载清晰照片")
            }
        }
        .task(id: thumbnailRequest) {
            if loadedAssetID != asset.id {
                image = nil
                loadedAssetID = asset.id
            }
            requestThumbnail()
        }
        .onDisappear { cancelRequest() }
    }

    private func requestThumbnail() {
        cancelRequest()

        let options = PHImageRequestOptions()
        options.deliveryMode = thumbnailRequest.deliveryMode
        options.resizeMode = thumbnailRequest.resizeMode
        options.isNetworkAccessAllowed = true

        isDownloadingOriginal = highQuality
        var localRequestID: PHImageRequestID = PHInvalidImageRequestID
        localRequestID = PHImageManager.default().requestImage(
            for: asset.asset,
            targetSize: thumbnailRequest.targetSize,
            contentMode: requestContentMode,
            options: options
        ) { image, info in
            DispatchQueue.main.async {
                guard localRequestID == requestID else { return }
                if let image {
                    self.image = image
                }

                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if highQuality {
                    self.isDownloadingOriginal = !isCancelled && isDegraded
                } else {
                    self.isDownloadingOriginal = false
                }
            }
        }
        requestID = localRequestID
    }

    private func cancelRequest() {
        guard requestID != PHInvalidImageRequestID else { return }
        PHImageManager.default().cancelImageRequest(requestID)
        requestID = PHInvalidImageRequestID
        isDownloadingOriginal = false
    }
}

private struct ThumbnailScaleModifier: ViewModifier {
    let mode: ThumbnailScaleMode

    func body(content: Content) -> some View {
        switch mode {
        case .fill:
            content.scaledToFill()
        case .fit:
            content.scaledToFit()
        }
    }
}

#Preview {
    PhotoGridView(assets: [])
}
