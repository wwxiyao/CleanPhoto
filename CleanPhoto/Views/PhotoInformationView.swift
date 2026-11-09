import SwiftUI

struct PhotoInformationView: View {
    let asset: PhotoAsset
    @Environment(\.dismiss) private var dismiss
    @State private var device: String?
    @State private var loading = true

    private var dateText: String {
        guard let date = asset.creationDate else { return "未记录日期" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("拍摄时间", value: dateText)
                LabeledContent("相机", value: loading ? "正在读取…" : (device ?? "未记录相机信息"))
                LabeledContent("尺寸", value: "\(asset.pixelWidth) × \(asset.pixelHeight)")
            }
            .navigationTitle("照片信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task(id: asset.id) {
            loading = true
            let model = await SwipeMetadataCache.shared.deviceModel(for: asset)
            guard !Task.isCancelled else { return }
            device = model
            loading = false
        }
    }
}
