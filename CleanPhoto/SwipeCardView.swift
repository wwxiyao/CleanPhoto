import SwiftUI
import Photos
import CoreLocation
import ImageIO

struct SwipeCardView: View {
    let asset: PhotoAsset
    let onSwipeUp: () -> Void
    let onSwipeLeft: () -> Void
    let viewModel: LibraryViewModel
    let onOpen: (UIImage?) -> Void

    @State private var offset: CGSize = .zero
    @StateObject private var loader = PhotoDetailImageLoader()
    @State private var metadata: PhotoMetadata?

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let size = PhotoViewerLayout.sizeWithAccessories(
                    photoSize: CGSize(width: max(asset.pixelWidth, 1), height: max(asset.pixelHeight, 1)),
                    availableSize: proxy.size,
                    accessoryHeight: 52
                )
                VStack(spacing: 8) {
                    photoContent
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        }
                    HStack {
                        Spacer(minLength: 0)
                        PhotoFavoriteButton(asset: asset, viewModel: viewModel, showsTitle: size.width >= 110)
                    }
                    .frame(height: 44)
                }
                .frame(width: size.width)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .clipped()
            .contentShape(Rectangle())
            .padding(.horizontal, 6)

            if let metadata {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(metadata.dateText ?? "未记录日期")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                    }
                    Label(metadata.locationText ?? "未记录位置", systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private var photoContent: some View {
        ZStack {
            if let image = loader.image {
                InlineZoomablePhoto(image: image, onZoom: { loader.loadOriginal(asset) },
                    onChanged: { offset = $0 }, onEnded: handleReviewEnded,
                    onOpen: { onOpen(loader.image) })
                .overlay(alignment: .bottom) {
                    if loader.loadingOriginal {
                        ProgressView(loader.progress > 0 ? "正在下载原图 \(Int(loader.progress * 100))%" : "正在加载细节…")
                            .font(.caption)
                            .padding(10)
                            .background(.thinMaterial, in: Capsule())
                            .padding(8)
                            .allowsHitTesting(false)
                    } else if let error = loader.error {
                        Button(error + " · 重试") { loader.retryOriginal(asset) }
                            .font(.caption)
                            .padding(10)
                            .background(.thinMaterial, in: Capsule())
                            .padding(8)
                    }
                }
            } else if let error = loader.error {
                VStack(spacing: 12) {
                    Text(error).font(.caption)
                    Button("重试") { loader.load(asset) }
                }
            } else {
                ProgressView()
            }

            if let feedback = PhotoSwipeFeedback.current(translation: offset) {
                swipeFeedback(feedback)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAction(named: "放大查看照片") { onOpen(loader.image) }
        .task(id: asset.id) {
            offset = .zero
            metadata = nil
            loader.load(asset)

            await loadMetadata()
        }
        .onDisappear {
            loader.clear()
        }
    }

    private func swipeFeedback(_ feedback: PhotoSwipeFeedback) -> some View {
        let isDelete = feedback.decision == .pendingDelete
        let tint = isDelete ? AppPalette.danger : AppPalette.success
        let title = isDelete ? "待删除" : "保留"
        let instruction = feedback.isReady
            ? (isDelete ? "松手加入待删除" : "松手保留")
            : (isDelete ? "继续上滑" : "继续左滑")

        return GeometryReader { proxy in
            ZStack {
                tint.opacity(0.2 + feedback.progress * 0.25)
                Color.black.opacity(0.15)
                VStack(spacing: 10) {
                    if proxy.size.height >= 160 {
                        Image(systemName: isDelete ? "trash.fill" : "checkmark.circle.fill")
                            .font(.system(size: 38, weight: .semibold))
                    }
                    Text(title)
                        .font(.system(size: proxy.size.height < 160 ? 24 : 36, weight: .bold))
                    if proxy.size.height >= 100 {
                        Text(instruction)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 4)
                .padding(.horizontal, 16)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func handleReviewEnded(_ decision: PhotoSwipeDecision?) {
        offset = .zero
        switch decision {
        case .pendingDelete: onSwipeUp()
        case .keep: onSwipeLeft()
        case nil: break
        }
    }

    private func loadMetadata() async {
        let dateText = asset.creationDate.map { Self.dateFormatter.string(from: $0) }
        metadata = PhotoMetadata(
            dateText: dateText,
            locationText: asset.location == nil ? nil : "正在读取位置…",
            deviceText: nil
        )

        if let location = asset.location {
            let name = await resolveLocationName(location)
            guard !Task.isCancelled else { return }
            metadata?.locationText = name ?? "暂时无法解析位置"
        }

    }

    private func resolveLocationName(_ location: CLLocation) async -> String? {
        let cacheKey = Self.locationCacheKey(for: location)
        let cached = await SwipeMetadataCache.shared.cachedLocationName(for: cacheKey)
        if cached.hit {
            return cached.value
        }

        let geocoder = CLGeocoder()
        let resolved: String?
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN"))
            guard let placemark = placemarks.first else {
                await SwipeMetadataCache.shared.storeLocationName(nil, for: cacheKey)
                return nil
            }
            let city = placemark.locality ?? placemark.administrativeArea
            let district = placemark.subLocality
            let components = [city, district == city ? nil : district].compactMap { $0 }
            resolved = components.isEmpty ? placemark.country : components.joined(separator: " · ")
        } catch {
            resolved = nil
        }

        await SwipeMetadataCache.shared.storeLocationName(resolved, for: cacheKey)
        return resolved
    }

    private static func locationCacheKey(for location: CLLocation) -> String {
        String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

actor SwipeMetadataCache {
    static let shared = SwipeMetadataCache()

    private enum CachedValue {
        case value(String)
        case missing
    }

    private var locationNames: [String: CachedValue] = [:]
    private var deviceModels: [String: CachedValue] = [:]

    func cachedLocationName(for key: String) -> (hit: Bool, value: String?) {
        guard let cached = locationNames[key] else { return (false, nil) }
        switch cached {
        case .value(let value):
            return (true, value)
        case .missing:
            return (true, nil)
        }
    }

    func storeLocationName(_ value: String?, for key: String) {
        if let value {
            locationNames[key] = .value(value)
        } else {
            locationNames[key] = .missing
        }
    }

    func deviceModel(for asset: PhotoAsset) async -> String? {
        let cached = cachedDeviceModel(for: asset.id)
        if cached.hit {
            return cached.value
        }

        let resolved: String? = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false

            var didResume = false
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset.asset,
                options: options
            ) { data, _, _, _ in
                guard !didResume else { return }
                didResume = true
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }

                Task.detached(priority: .userInitiated) {
                    let text = PhotoDeviceMetadata.text(from: data)
                    continuation.resume(returning: text)
                }
            }
        }

        storeDeviceModel(resolved, for: asset.id)
        return resolved
    }

    func cachedDeviceModel(for assetID: String) -> (hit: Bool, value: String?) {
        guard let cached = deviceModels[assetID] else { return (false, nil) }
        switch cached {
        case .value(let value):
            return (true, value)
        case .missing:
            return (true, nil)
        }
    }

    func storeDeviceModel(_ value: String?, for assetID: String) {
        if let value {
            deviceModels[assetID] = .value(value)
        } else {
            deviceModels[assetID] = .missing
        }
    }
}

/// Reuses the viewer's native zoom surface in place; controls remain outside it.
private struct InlineZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    let onZoom: () -> Void
    let onChanged: (CGSize) -> Void
    let onEnded: (PhotoSwipeDecision?) -> Void
    let onOpen: () -> Void

    func makeUIView(context: Context) -> PhotoZoomScrollView {
        let view = PhotoZoomScrollView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PhotoZoomScrollView, context: Context) {
        view.onZoom = onZoom
        view.onReviewChanged = onChanged
        view.onReviewEnded = onEnded
        view.onOpen = onOpen
        view.display(image)
    }
}
