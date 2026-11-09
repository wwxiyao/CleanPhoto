import SwiftUI
import UIKit

struct PhotoFavoriteButton: View {
    let asset: PhotoAsset
    @ObservedObject var viewModel: LibraryViewModel
    var showsTitle = false

    var body: some View {
        let favorite = viewModel.isFavorite(asset)
        let saving = viewModel.isUpdatingFavorite(asset)
        Button {
            #if !targetEnvironment(macCatalyst)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            viewModel.toggleFavorite(asset)
        } label: {
            PhotoActionLabel(
                title: showsTitle ? "收藏" : nil,
                symbol: favorite ? "heart.fill" : "heart",
                isActive: favorite,
                tint: .pink
            )
                .overlay(alignment: .bottomTrailing) {
                    if saving {
                        ProgressView().controlSize(.mini)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .accessibilityLabel(favorite ? "取消收藏" : "加入苹果相册个人收藏")
        .accessibilityValue(saving ? "正在保存" : (favorite ? "已收藏" : "未收藏"))
    }
}

/// Shared geometry, type and neutral color for the viewer's two actions.
struct PhotoActionLabel: View {
    let title: String?
    let symbol: String
    let isActive: Bool
    let tint: Color
    var fillsWidth = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: title == nil ? 21 : 25, weight: .medium))
                .frame(width: 28, height: 28)
            if let title {
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
        }
        .foregroundStyle(isActive ? tint : Color.primary)
        .padding(.horizontal, title == nil ? 0 : 14)
        .frame(minWidth: title == nil ? 44 : 110, maxWidth: fillsWidth ? .infinity : nil, minHeight: 44, maxHeight: 44)
        .background(.thinMaterial, in: Capsule())
        .contentShape(Capsule())
    }
}
