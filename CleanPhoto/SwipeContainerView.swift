import SwiftUI
import UIKit

struct SwipeContainerView: View {
    let assets: [PhotoAsset]
    let currentIndex: Int
    @ObservedObject var viewModel: LibraryViewModel
    let onSwipeUp: (PhotoAsset) -> Void
    let onSwipeLeft: (PhotoAsset) -> Void
    let onFinished: () -> Void

    @State private var detailSession: PhotoDetailSession?
    @State private var detailPreview: UIImage?

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                HStack(spacing: 16) {
                    photoArea
                    VStack(spacing: 16) {
                        headerView
                        Spacer(minLength: 0)
                        actionBar(isLandscape: true)
                    }
                    .frame(width: 210)
                    .padding(.vertical, 12)
                    .padding(.trailing, 16)
                }
            } else {
                VStack(spacing: 10) {
                    headerView
                        .padding(.horizontal, 16)
                    photoArea
                    actionBar(isLandscape: false)
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
        .fullScreenCover(item: $detailSession, onDismiss: { detailPreview = nil }) { session in
            PhotoDetailView(session: session, viewModel: viewModel, initialPreview: detailPreview)
        }
    }

    private var photoArea: some View {
        ZStack {
            if currentIndex < assets.count {
                SwipeCardView(
                    asset: assets[currentIndex],
                    onSwipeUp: handleDeleteTapped,
                    onSwipeLeft: handleKeepTapped,
                    viewModel: viewModel,
                    onOpen: { preview in
                        detailPreview = preview
                        detailSession = PhotoDetailSession(assets: assets, opening: assets[currentIndex])
                    }
                )
                .id(assets[currentIndex].id)
            } else {
                completionView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentAsset: PhotoAsset? {
        assets.indices.contains(currentIndex) ? assets[currentIndex] : nil
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("第 \(min(currentIndex + 1, assets.count)) / \(assets.count) 张 · 待删 \(viewModel.batchManager.pendingDeleteAssets.count) 张")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            HStack(spacing: 4) {
                ForEach(assets.indices, id: \.self) { index in
                    Capsule()
                        .fill(index < currentIndex ? AppPalette.primary : Color.primary.opacity(index == currentIndex ? 0.3 : 0.08))
                        .frame(height: 3)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("已整理 \(min(currentIndex, assets.count)) 张，共 \(assets.count) 张")
        }
        .padding(.vertical, 4)
    }

    private var reviewHint: String {
        #if targetEnvironment(macCatalyst)
        "K 保留 · D 待删除 · 本批结束后确认"
        #else
        "左滑保留 · 上滑待删除 · 本批结束后确认"
        #endif
    }

    private func actionBar(isLandscape: Bool) -> some View {
        VStack(spacing: 8) {
            if isLandscape {
                reviewButton(title: "保留", symbol: "checkmark", tint: AppPalette.success, action: handleKeepTapped)
                reviewButton(title: "待删除", symbol: "trash", tint: AppPalette.danger, action: handleDeleteTapped)
            } else {
                HStack(spacing: 12) {
                    reviewButton(title: "保留", symbol: "checkmark", tint: AppPalette.success, action: handleKeepTapped)
                    reviewButton(title: "待删除", symbol: "trash", tint: AppPalette.danger, action: handleDeleteTapped)
                }
            }
            Text(reviewHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .disabled(currentAsset == nil || detailSession != nil)
    }

    private func reviewButton(title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PhotoActionLabel(title: title, symbol: symbol, isActive: true, tint: tint, fillsWidth: true)
        }
        .buttonStyle(.plain)
        #if targetEnvironment(macCatalyst)
        .keyboardShortcut(title == "保留" ? KeyEquivalent("k") : KeyEquivalent("d"), modifiers: [])
        .help(title == "保留" ? "保留并进入下一张（K）" : "加入待删除并进入下一张（D）")
        #endif
        .accessibilityHint(title == "保留" ? "保留当前照片并进入下一张" : "加入待删除并进入下一张，本批结束后确认")
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppPalette.primary)
            Text("本批次完成")
                .font(.title3.bold())
            Text("在确认页检查待删除照片")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("检查待删除照片", action: onFinished)
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.primary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDeleteTapped() {
        guard currentIndex < assets.count else { return }
        triggerHaptic(style: .medium)
        onSwipeUp(assets[currentIndex])
    }

    private func handleKeepTapped() {
        guard currentIndex < assets.count else { return }
        triggerHaptic(style: .light)
        onSwipeLeft(assets[currentIndex])
    }

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if !targetEnvironment(macCatalyst)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}
