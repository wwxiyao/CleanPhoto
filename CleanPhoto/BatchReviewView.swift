import SwiftUI
import Photos

struct BatchReviewView: View {
    let assets: [PhotoAsset]
    let onRecover: (PhotoAsset) -> Void
    let onDeleteAll: () -> Void
    let onSkip: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppPalette.backgroundTop, AppPalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if assets.isEmpty {
                EmptyStateView(
                    title: "没有可删除的项目",
                    message: "您保留了本批次的所有照片。",
                    systemImage: "checkmark.circle",
                    accent: AppPalette.success,
                    actionTitle: "下一批",
                    action: onSkip
                )
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        summaryCard

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(assets) { asset in
                                ZStack(alignment: .topTrailing) {
                                    PhotoThumbnailView(asset: asset)
                                        .frame(height: 135)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            onRecover(asset)
                                        }
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(.white, AppPalette.primary)
                                    }
                                    .padding(8)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .safeAreaInset(edge: .bottom) {
                    actionBar
                }
            }
        }
        .navigationTitle("检查删除项")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("待删除 \(assets.count) 张")
                .font(.headline.weight(.bold))
            Text("点击右上角撤销按钮可恢复单张，确认后才会真正删除。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button(action: onDeleteAll) {
                Label("确认并删除 \(assets.count) 张照片", systemImage: "trash")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.danger)

            Button("保留本批，继续", action: onSkip)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.thinMaterial)
    }
}
