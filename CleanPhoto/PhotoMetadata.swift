import Foundation

struct PhotoMetadata {
    let dateText: String?
    var locationText: String?
    var deviceText: String?

    var lines: [String] {
        var items = [
            "日期: \(dateText ?? "未记录日期")",
            "位置: \(locationText ?? "未记录位置")"
        ]
        if let deviceText {
            items.append("设备: \(deviceText)")
        }
        return items
    }
}
