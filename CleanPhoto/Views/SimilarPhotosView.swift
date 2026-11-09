import SwiftUI

struct SimilarPhotosView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @StateObject private var queue: SimilarPhotoQueue
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("similarPhotos.columns") private var photoColumns = 3
    @AppStorage("similarPhotos.sortOrder") private var sortOrder: PhotoSortOrder = .newestFirst
    @State private var detailSession: PhotoDetailSession?
    @State private var galleryHasScrolled = false
    @State private var visibleGroupIDs: Set<UUID> = []

    init(viewModel: LibraryViewModel) {
        self.viewModel = viewModel
        let session = viewModel.similarPhotoSession {
            let service = SimilarityService(fetchResult: viewModel.assets)
            return SimilarPhotoQueue(scanPage: { request in
                await service.nextPage(groupLimit: request.groupLimit, assetBudget: request.photoBudget, featureBudget: request.featureBudget, sortOrder: request.sortOrder)
            })
        }
        _queue = StateObject(wrappedValue: session)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [AppPalette.backgroundTop, AppPalette.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if !queue.groups.isEmpty {
                    albumBrowser
                } else if queue.shouldShowSearchPlaceholder {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在寻找相似照片...")
                            .font(.headline)
                        Text("每次只准备少量照片，方便您慢慢整理。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    EmptyStateView(
                        title: queue.isExhausted ? "没有更多相似照片" : "查找已暂停",
                        message: queue.isExhausted ? "本次可访问的照片已查找完。" : "图库还没查找完。为避免持续占用手机，可继续查找后面的照片。",
                        systemImage: "checkmark.circle",
                        accent: AppPalette.success,
                        actionTitle: queue.isExhausted ? "返回" : "继续查找",
                        action: {
                            if queue.isExhausted { viewModel.exitSimilarMode() }
                            else { queue.requestRefill(force: true) }
                        }
                    )
                }
            }
        }
        .navigationTitle("相似照片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") {
                    viewModel.exitSimilarMode()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(PhotoSortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            if sortOrder == order { Label(order.title, systemImage: "checkmark") }
                            else { Text(order.title) }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("排序")
                .accessibilityValue(sortOrder.title)
            }
            if !queue.selectedAssets.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("删除", role: .destructive) {
                        let assets = queue.selectedAssets
                        guard !assets.isEmpty else { return }
                        viewModel.deleteSpecificAssets(assets) {}
                    }
                    .tint(AppPalette.danger)
                    .disabled(viewModel.isDeleting)
                }
            }
        }
        .fullScreenCover(item: $detailSession) { session in
            SimilarPhotoDetailView(session: session, queue: queue, viewModel: viewModel)
        }
        .onAppear {
            queue.setSortOrder(sortOrder)
            queue.setOverviewMode(true)
            queue.setActive(scenePhase == .active)
        }
        .onChange(of: sortOrder) { _, order in
            galleryHasScrolled = false
            visibleGroupIDs.removeAll()
            queue.setSortOrder(order)
        }
        .onChange(of: scenePhase) { _, phase in queue.setActive(phase == .active) }
        .onDisappear { queue.setActive(false) }
    }

    private var albumBrowser: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                    ForEach(queue.groups) { group in
                        Section {
                            SimilarAlbumGrid(
                                group: group,
                                columns: photoColumns == 1 ? 1 : 3,
                                width: proxy.size.width - 24,
                                onOpen: { asset in
                                    detailSession = PhotoDetailSession(group: group, opening: asset)
                                },
                                onToggle: { assetID in
                                    queue.toggleSelection(assetID, in: group.id)
                                }
                            )
                            .padding(.horizontal, 12)
                            .onAppear {
                                visibleGroupIDs.insert(group.id)
                                if galleryHasScrolled { queue.requestMoreForBrowsing(near: group.id) }
                            }
                            .onDisappear { visibleGroupIDs.remove(group.id) }
                        } header: {
                            albumGroupHeader(group)
                        }
                    }
                    if queue.isPreparing {
                        ProgressView("正在准备后续照片…")
                            .padding(20)
                    } else if !queue.isExhausted {
                        Button("继续查找更多照片") { queue.requestMoreForBrowsing() }
                            .buttonStyle(.bordered)
                            .padding(20)
                    } else {
                        Text("本次可访问的照片已查找完")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(20)
                    }
                }
                .padding(.bottom, 84)
            }
            .id(sortOrder)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating {
                    galleryHasScrolled = true
                    if let lastVisible = queue.groups.last(where: { visibleGroupIDs.contains($0.id) }) {
                        queue.requestMoreForBrowsing(near: lastVisible.id)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button { setColumns(photoColumns == 1 ? 3 : 1) } label: {
                    Image(systemName: photoColumns == 1
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(.regularMaterial, in: Circle())
                        .overlay { Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.primary)
                .accessibilityLabel(photoColumns == 1 ? "缩小为每行三张" : "放大为每行一张")
                .padding(16)
            }

        }
        .background(Color(.systemBackground))
    }

    private func setColumns(_ columns: Int) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { photoColumns = columns }
    }

    private func albumGroupHeader(_ group: SimilarGroup) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Text(SimilarGroupHeading.summary(for: group))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityLabel(SimilarGroupHeading.summary(for: group))
                Spacer(minLength: 0)
                Button { ignoreGroup(group) } label: {
                    Label("保留此组", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(AppPalette.primary)
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
    }

    private func ignoreGroup(_ group: SimilarGroup) {
        Task { await IgnoredGroupsService.shared.ignoreGroup(assets: group.assets) }
        withAnimation { queue.removeGroup(group.id) }
    }

}

private struct SimilarAlbumGrid: View {
    let group: SimilarGroup
    let columns: Int
    let width: CGFloat
    let onOpen: (PhotoAsset) -> Void
    let onToggle: (String) -> Void

    var body: some View {
        let items = Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: columns)
        LazyVGrid(columns: items, spacing: 4) {
            ForEach(group.assets) { asset in
                let selected = group.selectedForDelete.contains(asset.id)
                let size = AlbumPhotoLayout.tileSize(width: width, columns: columns, aspectRatio: asset.aspectRatio)
                ZStack(alignment: .topTrailing) {
                    Button { onOpen(asset) } label: {
                        PhotoThumbnailView(
                            asset: asset,
                            height: size.height,
                            cornerRadius: 6,
                            scaleMode: .fit,
                            highQuality: true,
                            displayWidth: size.width
                        )
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(selected ? AppPalette.danger : .clear, lineWidth: 3)
                        }
                        .opacity(selected ? 0.7 : 1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看照片")

                    Button { onToggle(asset.id) } label: {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(selected ? AppPalette.danger : .white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selected ? "取消待删选择" : "选为待删除")
                }

            }
        }
    }
}
