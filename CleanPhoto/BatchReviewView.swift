import SwiftUI
import Photos

struct BatchReviewView: View {
    let assets: [PhotoAsset]
    let onRecover: (PhotoAsset) -> Void
    let onDeleteAll: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack {
            if assets.isEmpty {
                EmptyStateView(
                    title: "没有可删除的项目",
                    message: "您保留了本批次的所有照片。",
                    actionTitle: "下一批",
                    action: onSkip
                )
            } else {
                List {
                    Section(header: Text("待删除项目 (\(assets.count))")) {
                        ForEach(assets) { asset in
                            HStack {
                                PhotoThumbnailView(asset: asset)
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(8)
                                
                                Spacer()
                                
                                Button("恢复") {
                                    onRecover(asset)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                
                VStack(spacing: 12) {
                    Button(action: onDeleteAll) {
                        Text("确认并删除 \(assets.count) 张照片")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button("暂时跳过", action: onSkip)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle("检查删除项")
    }
}
