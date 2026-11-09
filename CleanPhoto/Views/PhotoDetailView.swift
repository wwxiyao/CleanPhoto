import Combine
import Photos
import OSLog
import SwiftUI
import UIKit

#if DEBUG
private let photoDetailLog = Logger(subsystem: "wxynjx.CleanPhoto", category: "PhotoDetail")
#endif

struct SimilarPhotoDetailView: View {
    let session: PhotoDetailSession
    @ObservedObject var queue: SimilarPhotoQueue
    let viewModel: LibraryViewModel

    var body: some View {
        PhotoDetailView(session: session, viewModel: viewModel, selectedIDs: Set(queue.selectedAssets.map(\.id))) { asset in
            let selected = queue.selectedAssets.contains { $0.id == asset.id }
            for group in queue.groups where group.assets.contains(where: { $0.id == asset.id }) {
                if group.selectedForDelete.contains(asset.id) != !selected {
                    queue.toggleSelection(asset.id, in: group.id)
                }
            }
        }
    }
}

struct PhotoDetailView: View {
    let session: PhotoDetailSession
    let viewModel: LibraryViewModel
    let selectedIDs: Set<String>
    let onToggle: ((PhotoAsset) -> Void)?
    let initialPreview: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var showsInformation = false
    @State private var index: Int
    @StateObject private var images: PhotoDetailImageStore

    init(session: PhotoDetailSession, viewModel: LibraryViewModel, selectedIDs: Set<String> = [], initialPreview: UIImage? = nil, onToggle: ((PhotoAsset) -> Void)? = nil) {
        self.session = session
        self.viewModel = viewModel
        self.selectedIDs = selectedIDs
        self.initialPreview = initialPreview
        self.onToggle = onToggle
        _index = State(initialValue: session.initialIndex)
        _images = StateObject(wrappedValue: PhotoDetailImageStore(assets: session.assets))
    }

    private var current: PhotoAsset { session.assets[index] }
    private var isSelected: Bool { selectedIDs.contains(current.id) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("关闭") { dismiss() }
                    .frame(minWidth: 44, minHeight: 44)
                    #if targetEnvironment(macCatalyst)
                    .keyboardShortcut(.cancelAction)
                    #endif
                Spacer()
                Button { showsInformation = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("照片信息")
            }
            .padding(.horizontal, 16)
            GeometryReader { proxy in
                let availableWidth = max(0, proxy.size.width - 24)
                let photoSize = PhotoViewerLayout.sizeWithAccessories(
                    photoSize: CGSize(width: max(1, current.pixelWidth), height: max(1, current.pixelHeight)),
                    availableSize: CGSize(width: availableWidth, height: proxy.size.height),
                    accessoryHeight: 80
                )
                VStack(spacing: 0) {
                    #if targetEnvironment(macCatalyst)
                    HStack(spacing: 18) {
                        Button { index -= 1 } label: {
                            Image(systemName: "chevron.left").frame(width: 32, height: 28)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .disabled(index == 0)
                        .help("上一张（←）")
                        pageIndicator
                        Button { index += 1 } label: {
                            Image(systemName: "chevron.right").frame(width: 32, height: 28)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .disabled(index == session.assets.count - 1)
                        .help("下一张（→）")
                    }
                    .frame(height: 28, alignment: .top)
                    #else
                    pageIndicator.frame(height: 28, alignment: .top)
                    #endif
                    TabView(selection: $index) {
                        ForEach(session.assets.indices, id: \.self) { page in
                            PhotoDetailPage(asset: session.assets[page], active: page == index,
                                            initialPreview: page == session.initialIndex ? initialPreview : nil,
                                            loader: images.loaders[page])
                                .tag(page)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: photoSize.height)
                    viewerFooter(photoWidth: photoSize.width, availableWidth: availableWidth)
                        .frame(width: availableWidth)
                }
                .frame(width: proxy.size.width)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .background(.black)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsInformation) {
            PhotoInformationView(asset: current)
                .presentationDetents([.medium, .large])
        }
        .onAppear { images.move(to: index) }
        .onChange(of: index) { old, page in
            #if DEBUG
            photoDetailLog.info("Detail page change: \(old) -> \(page)")
            #endif
            images.move(to: page)
        }
        .onDisappear { images.clear() }
    }

    private var pageIndicator: some View {
        Text(onToggle == nil ? "\(index + 1)-\(session.assets.count)"
             : session.heading(index: index, selectedIDs: selectedIDs))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func viewerFooter(photoWidth: CGFloat, availableWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text(SimilarGroupHeading.text(date: current.creationDate))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            PhotoFavoriteButton(asset: current, viewModel: viewModel, showsTitle: true)
            if let onToggle {
                Button { onToggle(current) } label: {
                    PhotoActionLabel(
                        title: "删除",
                        symbol: isSelected ? "checkmark.circle.fill" : "circle",
                        isActive: isSelected,
                        tint: AppPalette.danger
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "取消待删选择" : "选为待删除")
                .accessibilityValue(isSelected ? "已勾选待删除" : "未勾选")
            }
        }
        .padding(.horizontal, min(max(0, (availableWidth - photoWidth) / 2),
                                  max(0, (availableWidth - (onToggle == nil ? 200 : 310)) / 2)))
        .padding(.top, 8)
        .frame(height: 52, alignment: .top)
    }

}

/// Page identity is stable; the store owns a bounded window of prepared previews.
@MainActor
private final class PhotoDetailImageStore: ObservableObject {
    let loaders: [PhotoDetailImageLoader]
    private let assets: [PhotoAsset]
    private var settleTask: Task<Void, Never>?

    init(assets: [PhotoAsset]) {
        self.assets = assets
        loaders = assets.map { _ in PhotoDetailImageLoader() }
    }

    func move(to index: Int) {
        settleTask?.cancel()
        let window = PhotoDetailPagingWindow.indices(current: index, count: assets.count)
        for page in assets.indices {
            if window.contains(page) { loaders[page].loadIfNeeded(assets[page]) }
            else { loaders[page].clear() }
        }
        // Let the outgoing page finish sliding before reducing its resolution.
        settleTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            for page in window where page != index {
                loaders[page].releaseOriginalKeepingPreview(assets[page])
            }
        }
    }

    func clear() {
        settleTask?.cancel()
        settleTask = nil
        loaders.forEach { $0.clear() }
    }
}

private struct PhotoDetailPage: View {
    let asset: PhotoAsset
    let active: Bool
    let initialPreview: UIImage?
    @ObservedObject var loader: PhotoDetailImageLoader

    var body: some View {
        GeometryReader { proxy in
            let size = PhotoViewerLayout.fittedSize(
                photoSize: CGSize(width: max(1, asset.pixelWidth), height: max(1, asset.pixelHeight)),
                availableSize: CGSize(width: max(0, proxy.size.width - 24), height: proxy.size.height)
            )
            photoCanvas
                .frame(width: size.width, height: size.height)
                .clipped()
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .clipped()
    }

    private var photoCanvas: some View {
        ZStack {
            Color.black
            if let image = loader.image ?? (active ? initialPreview : nil) {
                ZoomablePhoto(image: image) {
                    if active { loader.loadOriginal(asset) }
                }
                .overlay(alignment: .bottom) {
                    if loader.loadingOriginal {
                        ProgressView(loader.progress > 0 ? "正在下载原图 \(Int(loader.progress * 100))%" : "正在加载细节…")
                            .padding(12)
                            .background(.thinMaterial, in: Capsule())
                            .padding(12)
                    } else if let error = loader.error {
                        Button(error + " · 重试") { loader.retryOriginal(asset) }
                            .font(.caption)
                            .padding(12)
                            .background(.thinMaterial, in: Capsule())
                            .padding(12)
                    }
                }
            } else if let error = loader.error {
                VStack(spacing: 16) {
                    Text(error).font(.subheadline)
                    Button("重试") { loader.load(asset) }
                        .buttonStyle(.bordered)
                }
            } else if active {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载照片…").font(.caption)
                }
            }
        }
    }
}

/// A light preview opens immediately. The original is requested only for detail zoom.
@MainActor
final class PhotoDetailImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var progress: Double = 0
    @Published private(set) var error: String?
    @Published private(set) var loadingOriginal = false
    private var requestID = PHInvalidImageRequestID
    private var generation = UUID()
    private var state = PhotoDetailLoadingState()
    private var activeAssetID: String?
    private var previewImage: UIImage?

    func loadIfNeeded(_ asset: PhotoAsset) {
        guard activeAssetID != asset.id else { return }
        load(asset)
    }

    func releaseOriginalKeepingPreview(_ asset: PhotoAsset) {
        guard activeAssetID == asset.id, state.originalRequested else { return }
        cancelRequest()
        state = PhotoDetailLoadingState()
        loadingOriginal = false
        error = nil
        if let previewImage { image = previewImage }
        else { request(asset, original: false) }
    }

    func load(_ asset: PhotoAsset) {
        clear()
        activeAssetID = asset.id
        request(asset, original: false)
    }

    func loadOriginal(_ asset: PhotoAsset) {
        guard activeAssetID == asset.id, state.requestOriginal() else { return }
        request(asset, original: true)
    }

    func retryOriginal(_ asset: PhotoAsset) {
        guard activeAssetID == asset.id else { return }
        state = PhotoDetailLoadingState()
        loadOriginal(asset)
    }

    private func request(_ asset: PhotoAsset, original: Bool) {
        cancelRequest()
        let token = generation
        loadingOriginal = original
        progress = 0
        error = nil
        let options = PHImageRequestOptions()
        options.deliveryMode = original ? .highQualityFormat : .opportunistic
        options.resizeMode = original ? .none : .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.progressHandler = { [weak self] progress, _, _, _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.progress = progress
            }
        }
        let target = original ? PHImageManagerMaximumSize : PhotoDetailLoadingState.previewSize(
            source: CGSize(width: asset.pixelWidth, height: asset.pixelHeight))
        requestID = PHImageManager.default().requestImage(
            for: asset.asset, targetSize: target,
            contentMode: .aspectFit, options: options
        ) { [weak self] image, info in
            let cancelled = info?[PHImageCancelledKey] as? Bool ?? false
            let degraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
            guard !cancelled else { return }
            if let image {
                // Decode away from the main thread to avoid stalling presentation/zoom.
                Task.detached(priority: .userInitiated) { [weak self] in
                    let prepared = image.preparingForDisplay() ?? image
                    await self?.receive(prepared, token: token, original: original, degraded: degraded)
                }
            } else {
                Task { @MainActor in
                    guard let self, self.generation == token, !cancelled, !degraded else { return }
                    self.error = original ? "细节暂时无法加载" : "照片暂时无法加载"
                    self.loadingOriginal = false
                    self.requestID = PHInvalidImageRequestID
                }
            }
        }
    }

    private var finalImageReceived = false

    private func receive(_ image: UIImage, token: UUID, original: Bool, degraded: Bool) {
        guard generation == token, !(degraded && finalImageReceived) else { return }
        #if DEBUG
        photoDetailLog.info("Detail image ready: original=\(original), degraded=\(degraded), width=\(image.size.width), height=\(image.size.height)")
        #endif
        self.image = image
        if !original { previewImage = image }
        if !degraded {
            finalImageReceived = true
            requestID = PHInvalidImageRequestID
            loadingOriginal = false
        }
    }

    private func cancelRequest() {
        generation = UUID()
        finalImageReceived = false
        if requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
    }

    func clear() {
        cancelRequest()
        activeAssetID = nil
        state = PhotoDetailLoadingState()
        image = nil
        previewImage = nil
        progress = 0
        loadingOriginal = false
        error = nil
    }
}

private struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    let onZoom: () -> Void

    func makeUIView(context: Context) -> PhotoZoomScrollView {
        PhotoZoomScrollView()
    }

    func updateUIView(_ view: PhotoZoomScrollView, context: Context) {
        view.onZoom = onZoom
        view.display(image)
    }
}

final class PhotoZoomScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var onZoom: (() -> Void)?
    var onReviewChanged: ((CGSize) -> Void)?
    var onReviewEnded: ((PhotoSwipeDecision?) -> Void)?
    var onOpen: (() -> Void)?
    private var reviewInteraction = PhotoInlineInteraction()
    private lazy var reviewPan = UIPanGestureRecognizer(target: self, action: #selector(reviewDragged(_:)))
    private let photo = UIImageView()
    private var fittedBounds: CGSize = .zero
    private var needsFit = true

    init() {
        super.init(frame: .zero)
        delegate = self
        backgroundColor = .black
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        panGestureRecognizer.isEnabled = false
        clipsToBounds = true
        photo.contentMode = .scaleAspectFit
        addSubview(photo)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        reviewPan.maximumNumberOfTouches = 1
        reviewPan.delegate = self
        addGestureRecognizer(reviewPan)
        pinchGestureRecognizer?.addTarget(self, action: #selector(pinched(_:)))
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(openTapped))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func display(_ image: UIImage) {
        guard photo.image !== image else { return }
        let replacingImage = photo.image != nil && !needsFit
        #if DEBUG
        photoDetailLog.info("Detail image display: replacement=\(replacingImage), zoom=\(self.zoomScale), viewWidth=\(self.bounds.width), viewHeight=\(self.bounds.height)")
        #endif
        photo.image = image
        if replacingImage {
            // A sharper version must not reset the region the user is inspecting.
            maximumZoomScale = PhotoDetailGeometry.maximumZoom(image: image.size, fitted: photo.bounds.size)
        } else {
            needsFit = true
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if (needsFit || fittedBounds != bounds.size), let image = photo.image,
           bounds.width > 0, bounds.height > 0 {
            #if DEBUG
            photoDetailLog.info("Detail fit reset: oldWidth=\(self.fittedBounds.width), oldHeight=\(self.fittedBounds.height), width=\(self.bounds.width), height=\(self.bounds.height), zoom=\(self.zoomScale)")
            #endif
            needsFit = false
            fittedBounds = bounds.size
            minimumZoomScale = 1
            zoomScale = 1
            let size = PhotoDetailGeometry.fittedSize(image: image.size, viewport: bounds.size)
            photo.frame = CGRect(origin: .zero, size: size)
            contentSize = size
            maximumZoomScale = PhotoDetailGeometry.maximumZoom(image: image.size, fitted: size)
        }
        centerPhoto()
    }

    private func centerPhoto() {
        photo.center = CGPoint(x: max(contentSize.width, bounds.width) / 2,
                               y: max(contentSize.height, bounds.height) / 2)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerPhoto()
        let zoomed = zoomScale > 1.01
        if panGestureRecognizer.isEnabled != zoomed { panGestureRecognizer.isEnabled = zoomed }
        if zoomScale > 1.05 { onZoom?() }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === reviewPan {
            return onReviewEnded != nil && zoomScale <= 1.01
                && pinchGestureRecognizer?.state != .began
                && pinchGestureRecognizer?.state != .changed
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer === reviewPan && otherGestureRecognizer === pinchGestureRecognizer)
            || (otherGestureRecognizer === reviewPan && gestureRecognizer === pinchGestureRecognizer)
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .began else { return }
        reviewInteraction.beginZoom()
        onReviewChanged?(.zero)
        // A second finger must cancel a classification that began with the first finger.
        reviewPan.isEnabled = false
        reviewPan.isEnabled = true
    }

    @objc private func reviewDragged(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.translation(in: self)
        let translation = CGSize(width: point.x, height: point.y)
        switch gesture.state {
        case .began:
            reviewInteraction.beginDrag(zoomScale: zoomScale, touches: gesture.numberOfTouches)
        case .changed:
            if reviewInteraction.canReview { onReviewChanged?(translation) }
        case .ended:
            onReviewEnded?(reviewInteraction.endDrag(translation: translation))
            onReviewChanged?(.zero)
        case .cancelled, .failed:
            reviewInteraction.beginZoom()
            onReviewChanged?(.zero)
        default: break
        }
    }

    @objc private func openTapped() {
        guard zoomScale <= 1.01 else { return }
        onOpen?()
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.05 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let scale = min(maximumZoomScale, 3)
            let point = gesture.location(in: photo)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }
}
